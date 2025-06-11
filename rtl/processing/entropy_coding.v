//=============================================================================
// 熵编码模块 (Entropy Coding Module)
// 
// 功能：对量化MDCT系数进行算术编码，实现无损压缩
// 作者：Audio Codec Design Team
// 版本：v1.0
// 日期：2024-06-11
//=============================================================================

`timescale 1ns/1ps

module entropy_coding (
    // 系统信号
    input                       clk,
    input                       rst_n,
    
    // 配置接口
    input       [1:0]           frame_duration,     // 帧长配置
    input                       channel_mode,       // 通道模式
    input       [7:0]           target_bitrate,     // 目标比特率
    input                       enable,             // 模块使能
    
    // 输入数据接口 (来自量化控制)
    input                       quant_valid,        // 量化数据有效
    input       [15:0]          quantized_coeff,    // 量化后系数
    input       [7:0]           quantization_step,  // 量化步长
    input       [3:0]           scale_factor,       // 缩放因子
    input       [9:0]           coeff_index,        // 系数索引
    output                      quant_ready,        // 可接收量化数据
    
    // 输出数据接口 (到比特流打包)
    output                      output_valid,       // 输出数据有效
    output      [31:0]          encoded_bits,       // 编码后比特流
    output      [5:0]           bit_count,          // 有效比特数 (1-32)
    output                      frame_end,          // 帧结束标志
    input                       output_ready,       // 下游就绪信号
    
    // 存储器接口 (工作缓冲器)
    output                      mem_req_valid,      // 存储器请求有效
    output      [11:0]          mem_req_addr,       // 存储器地址
    output      [31:0]          mem_req_wdata,      // 写数据
    output                      mem_req_wen,        // 写使能
    input                       mem_req_ready,      // 存储器就绪
    input       [31:0]          mem_req_rdata,      // 读数据
    
    // 概率表ROM接口
    output                      prob_req_valid,     // 概率表请求有效
    output      [9:0]           prob_req_addr,      // 概率表地址
    input       [31:0]          prob_req_data,      // 概率表数据
    input                       prob_req_ready,     // 概率表就绪
    
    // 状态输出
    output                      coding_busy,        // 编码忙碌状态
    output                      frame_done,         // 帧编码完成
    output      [15:0]          bits_generated,     // 生成的比特数
    output      [15:0]          compression_ratio,  // 压缩比
    output      [31:0]          debug_info          // 调试信息
);

//=============================================================================
// 参数定义
//=============================================================================

// 帧长度计算常数
localparam FRAME_160_SAMPLES  = 2'b00;   // 2.5ms @ 64kHz
localparam FRAME_320_SAMPLES  = 2'b01;   // 5ms @ 64kHz  
localparam FRAME_640_SAMPLES  = 2'b10;   // 10ms @ 64kHz

// 状态机状态
localparam IDLE            = 3'b000;    // 空闲状态
localparam COEFF_COLLECT   = 3'b001;    // 收集量化系数
localparam SYMBOL_ANALYSIS = 3'b010;    // 符号分析和预处理
localparam CONTEXT_MODEL   = 3'b011;    // 上下文建模
localparam ARITHMETIC_CODE = 3'b100;    // 算术编码
localparam BIT_OUTPUT      = 3'b101;    // 比特输出
localparam FRAME_FINISH    = 3'b110;    // 帧结束处理
localparam ERROR           = 3'b111;    // 错误状态

// 存储器地址映射 
localparam COEFF_BUFFER_BASE   = 12'h800;  // 量化系数缓冲
localparam CONTEXT_BUFFER_BASE = 12'h880;  // 上下文历史缓冲
localparam FREQ_TABLE_BASE     = 12'h8C0;  // 符号频率统计表
localparam PROB_TABLE_BASE     = 12'h900;  // 累积概率表
localparam ARITH_STATE_BASE    = 12'h940;  // 算术编码状态
localparam OUTPUT_BUFFER_BASE  = 12'h960;  // 输出比特缓冲
localparam RUN_BUFFER_BASE     = 12'h980;  // 游程编码缓冲
localparam TEMP_BUFFER_BASE    = 12'h9A0;  // 临时计算缓冲

// 算术编码常数
localparam ARITH_PRECISION = 32;           // 算术编码精度
localparam MIN_INTERVAL    = 32'h0000_1000; // 最小区间
localparam MAX_SYMBOL      = 2048;         // 最大符号值
localparam PROB_BITS       = 16;           // 概率精度

// 错误代码
localparam NO_ERROR                = 4'h0;
localparam ERROR_INTERVAL_TOO_SMALL     = 4'h1;
localparam ERROR_INVALID_PROBABILITY    = 4'h2;
localparam ERROR_BIT_BUDGET_EXCEEDED    = 4'h3;
localparam ERROR_MEMORY_ACCESS          = 4'h4;

//=============================================================================
// 信号声明
//=============================================================================

// 状态机信号
reg     [2:0]           current_state, next_state;
reg                     state_changed;

// 帧参数
reg     [9:0]           frame_length;           // 当前帧系数数量
reg     [15:0]          target_frame_bits;      // 目标帧比特数
reg     [9:0]           coeff_count;           // 已处理系数计数
reg                     frame_start;           // 帧开始标志

// 量化系数处理
reg     [15:0]          coeff_buffer[0:639];   // 系数缓冲器
reg     [9:0]           coeff_write_ptr;       // 写指针
reg     [9:0]           coeff_read_ptr;        // 读指针
reg                     coeff_valid_reg;       // 延迟的有效信号

// 符号分析
reg     [7:0]           zero_run_length;       // 零游程长度
reg     [15:0]          symbol_magnitude;      // 符号幅度
reg                     symbol_sign;           // 符号符号位
reg     [7:0]           symbol_type;           // 符号类型
reg                     run_coding_active;     // 游程编码活跃

// 上下文建模
reg     [15:0]          context_history[0:7];  // 上下文历史
reg     [7:0]           context_hash;          // 上下文散列
reg     [1:0]           context_level;         // 上下文级别
reg     [15:0]          freq_table[0:255];     // 频率统计表
reg     [31:0]          total_freq_count;      // 总频率计数

// 算术编码状态
reg     [31:0]          arith_low;             // 编码区间下界
reg     [31:0]          arith_high;            // 编码区间上界
reg     [31:0]          arith_range;           // 区间范围
reg     [5:0]           scale_count;           // 归一化计数
reg     [15:0]          cum_prob_low;          // 累积概率下界
reg     [15:0]          cum_prob_high;         // 累积概率上界

// 比特输出
reg     [31:0]          output_bit_buffer;     // 输出比特缓冲
reg     [5:0]           output_bit_count;      // 输出比特数
reg     [31:0]          frame_bits_total;      // 帧总比特数
reg                     output_valid_reg;      // 输出有效寄存器

// 存储器访问
reg                     mem_req_valid_reg;
reg     [11:0]          mem_req_addr_reg;
reg     [31:0]          mem_req_wdata_reg;
reg                     mem_req_wen_reg;
wire                    mem_access_done;

// 概率表访问
reg                     prob_req_valid_reg;
reg     [9:0]           prob_req_addr_reg;
wire                    prob_access_done;

// 错误处理
reg     [3:0]           error_flag;
reg                     error_recovery;

// 性能统计
reg     [15:0]          original_bits;         // 原始比特数
reg     [15:0]          compressed_bits;       // 压缩后比特数
reg     [31:0]          encoding_cycles;       // 编码周期数

//=============================================================================
// 组合逻辑
//=============================================================================

// 帧长度配置
always @(*) begin
    case (frame_duration)
        FRAME_160_SAMPLES: frame_length = 10'd160;
        FRAME_320_SAMPLES: frame_length = 10'd320;
        FRAME_640_SAMPLES: frame_length = 10'd640;
        default:           frame_length = 10'd320;
    endcase
end

// 目标比特数计算
always @(*) begin
    case (frame_duration)
        FRAME_160_SAMPLES: target_frame_bits = (target_bitrate * 16'd10) / 16'd400; // 2.5ms
        FRAME_320_SAMPLES: target_frame_bits = (target_bitrate * 16'd20) / 16'd400; // 5ms
        FRAME_640_SAMPLES: target_frame_bits = (target_bitrate * 16'd40) / 16'd400; // 10ms
        default:           target_frame_bits = (target_bitrate * 16'd20) / 16'd400;
    endcase
end

// 存储器接口
assign mem_req_valid = mem_req_valid_reg;
assign mem_req_addr  = mem_req_addr_reg;
assign mem_req_wdata = mem_req_wdata_reg;
assign mem_req_wen   = mem_req_wen_reg;
assign mem_access_done = mem_req_valid_reg & mem_req_ready;

// 概率表ROM接口
assign prob_req_valid = prob_req_valid_reg;
assign prob_req_addr  = prob_req_addr_reg;
assign prob_access_done = prob_req_valid_reg & prob_req_ready;

// 输入握手
assign quant_ready = (current_state == COEFF_COLLECT) && (coeff_count < frame_length);

// 输出接口
assign output_valid   = output_valid_reg;
assign encoded_bits   = output_bit_buffer;
assign bit_count      = output_bit_count;
assign frame_end      = (current_state == FRAME_FINISH);

// 状态输出
assign coding_busy    = (current_state != IDLE);
assign frame_done     = (current_state == FRAME_FINISH);
assign bits_generated = compressed_bits;
assign compression_ratio = (original_bits != 0) ? ((original_bits * 256) / compressed_bits) : 16'h0000;

// 调试信息
assign debug_info = {
    error_flag[3:0],           // [31:28] 错误代码
    current_state[2:0],        // [27:25] 当前状态
    context_level[1:0],        // [24:23] 上下文级别
    zero_run_length[7:0],      // [22:15] 零游程长度
    coeff_count[9:0],          // [14:5]  系数计数
    scale_count[4:0]           // [4:0]   归一化计数
};

//=============================================================================
// 主状态机
//=============================================================================

// 状态寄存器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;
        state_changed <= 1'b0;
    end else begin
        current_state <= next_state;
        state_changed <= (current_state != next_state);
    end
end

// 状态转换逻辑
always @(*) begin
    next_state = current_state;
    
    case (current_state)
        IDLE: begin
            if (enable && quant_valid) begin
                next_state = COEFF_COLLECT;
            end
        end
        
        COEFF_COLLECT: begin
            if (coeff_count >= frame_length) begin
                next_state = SYMBOL_ANALYSIS;
            end
        end
        
        SYMBOL_ANALYSIS: begin
            if (coeff_read_ptr >= frame_length) begin
                next_state = CONTEXT_MODEL;
            end
        end
        
        CONTEXT_MODEL: begin
            if (total_freq_count > 32'd0) begin
                next_state = ARITHMETIC_CODE;
            end
        end
        
        ARITHMETIC_CODE: begin
            if (coeff_read_ptr >= frame_length) begin
                next_state = BIT_OUTPUT;
            end
        end
        
        BIT_OUTPUT: begin
            if (output_ready && output_valid_reg) begin
                next_state = FRAME_FINISH;
            end
        end
        
        FRAME_FINISH: begin
            next_state = IDLE;
        end
        
        ERROR: begin
            if (error_recovery) begin
                next_state = IDLE;
            end
        end
        
        default: begin
            next_state = ERROR;
        end
    endcase
    
    // 错误条件检查
    if (error_flag != NO_ERROR) begin
        next_state = ERROR;
    end
end

//=============================================================================
// 系数收集阶段
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        coeff_count <= 10'd0;
        coeff_write_ptr <= 10'd0;
        frame_start <= 1'b0;
    end else begin
        case (current_state)
            IDLE: begin
                coeff_count <= 10'd0;
                coeff_write_ptr <= 10'd0;
                frame_start <= 1'b0;
            end
            
            COEFF_COLLECT: begin
                if (quant_valid && quant_ready) begin
                    // 存储量化系数
                    coeff_buffer[coeff_write_ptr] <= quantized_coeff;
                    coeff_write_ptr <= coeff_write_ptr + 10'd1;
                    coeff_count <= coeff_count + 10'd1;
                    
                    if (coeff_count == 10'd0) begin
                        frame_start <= 1'b1;
                    end
                end
            end
            
            default: begin
                frame_start <= 1'b0;
            end
        endcase
    end
end

//=============================================================================
// 符号分析阶段
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        coeff_read_ptr <= 10'd0;
        zero_run_length <= 8'd0;
        symbol_magnitude <= 16'd0;
        symbol_sign <= 1'b0;
        symbol_type <= 8'd0;
        run_coding_active <= 1'b0;
    end else begin
        case (current_state)
            SYMBOL_ANALYSIS: begin
                if (coeff_read_ptr < frame_length) begin
                    // 读取当前系数
                    if (coeff_buffer[coeff_read_ptr] == 16'd0) begin
                        // 零系数，增加游程长度
                        zero_run_length <= zero_run_length + 8'd1;
                        run_coding_active <= 1'b1;
                    end else begin
                        // 非零系数，处理之前的游程
                        if (run_coding_active) begin
                            symbol_type <= 8'h01;  // 零游程符号
                            symbol_magnitude <= {8'd0, zero_run_length};
                            symbol_sign <= 1'b0;
                            zero_run_length <= 8'd0;
                            run_coding_active <= 1'b0;
                        end else begin
                            // 处理非零系数
                            symbol_type <= 8'h02;  // 非零符号
                            symbol_sign <= coeff_buffer[coeff_read_ptr][15];
                            if (coeff_buffer[coeff_read_ptr][15]) begin
                                // 负数，取绝对值
                                symbol_magnitude <= ~coeff_buffer[coeff_read_ptr] + 16'd1;
                            end else begin
                                // 正数
                                symbol_magnitude <= coeff_buffer[coeff_read_ptr];
                            end
                        end
                    end
                    
                    coeff_read_ptr <= coeff_read_ptr + 10'd1;
                end
            end
            
            CONTEXT_MODEL: begin
                coeff_read_ptr <= 10'd0;  // 重置读指针用于编码
            end
            
            default: begin
                if (state_changed && current_state == SYMBOL_ANALYSIS) begin
                    coeff_read_ptr <= 10'd0;
                    zero_run_length <= 8'd0;
                    run_coding_active <= 1'b0;
                end
            end
        endcase
    end
end

//=============================================================================
// 上下文建模
//=============================================================================

// 上下文散列函数
function [7:0] context_hash_func;
    input [15:0] coeff_prev1;
    input [15:0] coeff_prev2;
    input [3:0] band_index;
    begin
        // 简单散列：组合前两个系数和频带索引
        context_hash_func = coeff_prev1[7:0] ^ coeff_prev2[7:0] ^ {4'b0000, band_index};
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        context_level <= 2'd0;
        context_hash <= 8'd0;
        total_freq_count <= 32'd0;
        // 初始化上下文历史
        for (integer i = 0; i < 8; i = i + 1) begin
            context_history[i] <= 16'd0;
        end
        // 初始化频率表
        for (integer i = 0; i < 256; i = i + 1) begin
            freq_table[i] <= 16'd1;  // 初始频率为1
        end
    end else begin
        case (current_state)
            CONTEXT_MODEL: begin
                // 计算上下文散列
                if (coeff_read_ptr >= 10'd2) begin
                    context_hash <= context_hash_func(
                        context_history[0], 
                        context_history[1], 
                        scale_factor
                    );
                    context_level <= 2'd2;  // 二阶上下文
                end else if (coeff_read_ptr >= 10'd1) begin
                    context_hash <= context_history[0][7:0];
                    context_level <= 2'd1;  // 一阶上下文
                end else begin
                    context_hash <= 8'd0;
                    context_level <= 2'd0;  // 无上下文
                end
                
                // 统计总频率
                total_freq_count <= 32'd256;  // 初始总频率
            end
            
            ARITHMETIC_CODE: begin
                // 更新上下文历史
                if (coeff_read_ptr > 10'd0) begin
                    context_history[1] <= context_history[0];
                    context_history[0] <= coeff_buffer[coeff_read_ptr - 10'd1];
                end
                
                // 更新频率统计
                if (symbol_magnitude < 16'd256) begin
                    freq_table[symbol_magnitude[7:0]] <= freq_table[symbol_magnitude[7:0]] + 16'd1;
                    total_freq_count <= total_freq_count + 32'd1;
                end
            end
        endcase
    end
end

//=============================================================================
// 算术编码核心
//=============================================================================

// 算术编码函数
function [63:0] arithmetic_encode;
    input [31:0] low, high;
    input [15:0] cum_prob_low, cum_prob_high;
    
    reg [63:0] range;
    reg [63:0] new_low, new_high;
    begin
        // 计算区间范围
        range = {32'd0, high} - {32'd0, low};
        
        // 更新区间边界
        new_low = {32'd0, low} + ((range * {48'd0, cum_prob_low}) >> 16);
        new_high = {32'd0, low} + ((range * {48'd0, cum_prob_high}) >> 16);
        
        arithmetic_encode = {new_high[31:0], new_low[31:0]};
    end
endfunction

// 归一化处理
function [31:0] normalize_interval;
    input [31:0] low, high;
    input [5:0] scale_bits;
    
    reg [31:0] norm_low, norm_high;
    begin
        // 左移去除确定的高位比特
        norm_low = low << scale_bits;
        norm_high = high << scale_bits;
        
        normalize_interval = {norm_high[15:0], norm_low[15:0]};
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        arith_low <= 32'h0000_0000;
        arith_high <= 32'hFFFF_FFFF;
        arith_range <= 32'hFFFF_FFFF;
        scale_count <= 6'd0;
        cum_prob_low <= 16'd0;
        cum_prob_high <= 16'd0;
    end else begin
        case (current_state)
            ARITHMETIC_CODE: begin
                if (coeff_read_ptr < frame_length) begin
                    // 计算当前符号的累积概率
                    if (symbol_magnitude < 16'd256) begin
                        cum_prob_low <= (freq_table[symbol_magnitude[7:0]] * 16'd65535) / total_freq_count[15:0];
                        cum_prob_high <= ((freq_table[symbol_magnitude[7:0]] + 16'd1) * 16'd65535) / total_freq_count[15:0];
                    end else begin
                        cum_prob_low <= 16'd65534;
                        cum_prob_high <= 16'd65535;
                    end
                    
                    // 执行算术编码
                    {arith_high, arith_low} <= arithmetic_encode(arith_low, arith_high, cum_prob_low, cum_prob_high);
                    
                    // 检查是否需要归一化
                    arith_range <= arith_high - arith_low;
                    if (arith_range < MIN_INTERVAL) begin
                        scale_count <= scale_count + 6'd1;
                        {arith_high, arith_low} <= {normalize_interval(arith_low, arith_high, 6'd1), 32'd0};
                    end
                    
                    coeff_read_ptr <= coeff_read_ptr + 10'd1;
                end
            end
            
            BIT_OUTPUT: begin
                // 输出最终编码值
                output_bit_buffer <= arith_low;
                output_bit_count <= 6'd32;
                output_valid_reg <= 1'b1;
            end
            
            default: begin
                if (state_changed && current_state == ARITHMETIC_CODE) begin
                    arith_low <= 32'h0000_0000;
                    arith_high <= 32'hFFFF_FFFF;
                    scale_count <= 6'd0;
                    coeff_read_ptr <= 10'd0;
                end
                
                if (current_state != BIT_OUTPUT) begin
                    output_valid_reg <= 1'b0;
                end
            end
        endcase
    end
end

//=============================================================================
// 性能统计和错误处理
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        original_bits <= 16'd0;
        compressed_bits <= 16'd0;
        encoding_cycles <= 32'd0;
        error_flag <= NO_ERROR;
        error_recovery <= 1'b0;
    end else begin
        // 性能统计
        if (frame_start) begin
            original_bits <= frame_length * 16'd16;  // 原始16位系数
            compressed_bits <= 16'd0;
            encoding_cycles <= 32'd0;
        end
        
        if (coding_busy) begin
            encoding_cycles <= encoding_cycles + 32'd1;
        end
        
        if (output_valid_reg && output_ready) begin
            compressed_bits <= compressed_bits + {10'd0, bit_count};
        end
        
        // 错误检测
        if (current_state == ARITHMETIC_CODE) begin
            if (arith_high <= arith_low) begin
                error_flag <= ERROR_INTERVAL_TOO_SMALL;
            end else if (cum_prob_high <= cum_prob_low) begin
                error_flag <= ERROR_INVALID_PROBABILITY;
            end else if (compressed_bits > (target_frame_bits + 16'd64)) begin
                error_flag <= ERROR_BIT_BUDGET_EXCEEDED;
            end
        end
        
        // 错误恢复
        if (current_state == ERROR) begin
            error_recovery <= 1'b1;
        end else begin
            error_recovery <= 1'b0;
            if (current_state == IDLE) begin
                error_flag <= NO_ERROR;
            end
        end
    end
end

//=============================================================================
// 存储器和ROM访问控制
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_req_valid_reg <= 1'b0;
        mem_req_addr_reg <= 12'd0;
        mem_req_wdata_reg <= 32'd0;
        mem_req_wen_reg <= 1'b0;
        prob_req_valid_reg <= 1'b0;
        prob_req_addr_reg <= 10'd0;
    end else begin
        // 默认情况下关闭请求
        mem_req_valid_reg <= 1'b0;
        prob_req_valid_reg <= 1'b0;
        
        case (current_state)
            CONTEXT_MODEL: begin
                // 读取概率表
                prob_req_valid_reg <= 1'b1;
                prob_req_addr_reg <= {2'b00, context_hash};
            end
            
            ARITHMETIC_CODE: begin
                // 更新频率统计
                if (symbol_magnitude < 16'd256) begin
                    mem_req_valid_reg <= 1'b1;
                    mem_req_addr_reg <= FREQ_TABLE_BASE + {4'd0, symbol_magnitude[7:0]};
                    mem_req_wdata_reg <= {16'd0, freq_table[symbol_magnitude[7:0]]};
                    mem_req_wen_reg <= 1'b1;
                end
            end
        endcase
    end
end

endmodule 