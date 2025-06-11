//=============================================================================
// LC3plus量化控制模块 (Quantization Control Module)
// 
// 功能：实现自适应量化步长控制和率失真优化的比特分配算法
// 作者：Audio Codec Design Team
// 版本：v1.0  
// 日期：2024-06-11
//=============================================================================

`timescale 1ns/1ps

module quantization_control (
    // 系统信号
    input                       clk,
    input                       rst_n,
    
    // 配置信号
    input       [1:0]           frame_duration,     // 帧长配置: 0=2.5ms, 1=5ms, 2=10ms
    input       [7:0]           target_bitrate,     // 目标比特率(kbps)
    input       [15:0]          sample_rate,        // 采样率
    input                       channel_mode,       // 0=单声道, 1=立体声
    
    // 频谱分析输入接口
    input                       spectral_valid,     // 频谱数据有效
    input       [23:0]          spectral_data,      // 频谱系数数据
    input       [23:0]          spectral_envelope,  // 频谱包络
    input       [15:0]          spectral_masking,   // 遮蔽阈值
    input       [7:0]           spectral_bandwidth, // 有效带宽
    input       [9:0]           spectral_index,     // 频谱索引
    input                       spectral_frame_end, // 帧结束标志
    output                      spectral_ready,     // 频谱输入就绪
    
    // 量化输出接口
    output                      quant_valid,        // 量化数据有效
    output      [15:0]          quant_data,         // 量化后的系数
    output      [7:0]           quant_step,         // 量化步长
    output      [3:0]           quant_scale,        // 缩放因子
    output      [9:0]           quant_index,        // 系数索引
    output                      quant_frame_end,    // 帧结束标志
    input                       quant_ready,        // 量化输出就绪
    
    // 存储器接口
    output                      mem_req_valid,      // 存储器请求有效
    output      [11:0]          mem_req_addr,       // 存储器地址
    output      [31:0]          mem_req_wdata,      // 写数据
    output                      mem_req_wen,        // 写使能
    input                       mem_req_ready,      // 存储器就绪
    input       [31:0]          mem_req_rdata,      // 读数据
    
    // 控制和状态信号
    input                       enable,             // 模块使能
    output                      processing,         // 处理中标志
    output      [31:0]          status_reg,         // 状态寄存器
    output      [31:0]          debug_info          // 调试信息
);

//=============================================================================
// 参数定义
//=============================================================================

// 状态机状态定义
localparam STATE_IDLE           = 4'b0000;    // 空闲状态
localparam STATE_LOAD_CONFIG    = 4'b0001;    // 加载配置
localparam STATE_COLLECT_SPEC   = 4'b0010;    // 收集频谱数据
localparam STATE_CALC_TARGET    = 4'b0011;    // 计算目标比特数
localparam STATE_INIT_QUANT     = 4'b0100;    // 初始化量化参数
localparam STATE_RATE_LOOP      = 4'b0101;    // 率失真循环
localparam STATE_QUANTIZE       = 4'b0110;    // 执行量化
localparam STATE_COUNT_BITS     = 4'b0111;    // 统计比特数
localparam STATE_ADJUST_RATE    = 4'b1000;    // 调整码率
localparam STATE_OUTPUT         = 4'b1001;    // 输出结果
localparam STATE_FRAME_END      = 4'b1010;    // 帧结束处理
localparam STATE_ERROR          = 4'b1111;    // 错误状态

// 量化参数
localparam MAX_COEFFS           = 640;        // 最大系数数量
localparam MIN_QUANT_STEP       = 8'd1;       // 最小量化步长
localparam MAX_QUANT_STEP       = 8'd255;     // 最大量化步长
localparam RATE_LOOP_MAX        = 4'd8;       // 最大率失真迭代次数

// 存储器地址映射
localparam ADDR_SPECTRAL_BASE   = 12'h000;    // 频谱系数基地址
localparam ADDR_ENVELOPE_BASE   = 12'h400;    // 包络数据基地址  
localparam ADDR_MASKING_BASE    = 12'h500;    // 遮蔽阈值基地址
localparam ADDR_QUANT_BASE      = 12'h600;    // 量化结果基地址
localparam ADDR_CONFIG_BASE     = 12'h700;    // 配置数据基地址

//=============================================================================
// 信号声明
//=============================================================================

// 状态机控制
reg     [3:0]           current_state;
reg     [3:0]           next_state;
reg                     state_changed;

// 帧处理控制
reg     [9:0]           frame_size;            // 当前帧大小
reg     [9:0]           collect_counter;       // 收集计数器
reg     [9:0]           output_counter;        // 输出计数器
reg                     frame_active;          // 帧处理活跃

// 配置寄存器
reg     [15:0]          target_bits;           // 目标比特数
reg     [7:0]           base_quant_step;       // 基础量化步长
reg     [7:0]           current_quant_step;    // 当前量化步长
reg     [3:0]           global_scale;          // 全局缩放因子
reg     [7:0]           effective_bandwidth;   // 有效带宽

// 率失真优化
reg     [3:0]           rate_loop_count;       // 率失真循环计数
reg     [15:0]          estimated_bits;        // 估计比特数
reg     [15:0]          actual_bits;           // 实际比特数
reg     [7:0]           step_adjust;           // 步长调整量
reg                     rate_converged;        // 率失真收敛标志

// 存储器控制
reg                     mem_req_valid_r;
reg     [11:0]          mem_req_addr_r;
reg     [31:0]          mem_req_wdata_r;
reg                     mem_req_wen_r;
reg                     mem_operation_pending;

// 输入缓冲
reg     [23:0]          input_spectral_data;
reg     [23:0]          input_envelope;
reg     [15:0]          input_masking;
reg     [9:0]           input_index;

// 输出缓冲
reg                     output_valid_r;
reg     [15:0]          output_data_r;
reg     [7:0]           output_step_r;
reg     [3:0]           output_scale_r;
reg     [9:0]           output_index_r;
reg                     output_frame_end_r;

// 量化计算信号
wire    [31:0]          quant_input;
wire    [31:0]          quant_threshold;
wire    [15:0]          quant_result;
wire    [7:0]           effective_step;

// 统计信号
reg     [31:0]          coeffs_processed;
reg     [31:0]          nonzero_coeffs;
reg     [31:0]          total_energy;
reg     [15:0]          peak_amplitude;

//=============================================================================
// 主状态机
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= STATE_IDLE;
        state_changed <= 1'b0;
    end else begin
        if (current_state != next_state) begin
            current_state <= next_state;
            state_changed <= 1'b1;
        end else begin
            state_changed <= 1'b0;
        end
    end
end

always @(*) begin
    next_state = current_state;
    
    case (current_state)
        STATE_IDLE: begin
            if (enable && spectral_valid) begin
                next_state = STATE_LOAD_CONFIG;
            end
        end
        
        STATE_LOAD_CONFIG: begin
            next_state = STATE_COLLECT_SPEC;
        end
        
        STATE_COLLECT_SPEC: begin
            if (spectral_frame_end) begin
                next_state = STATE_CALC_TARGET;
            end
        end
        
        STATE_CALC_TARGET: begin
            next_state = STATE_INIT_QUANT;
        end
        
        STATE_INIT_QUANT: begin
            next_state = STATE_RATE_LOOP;
        end
        
        STATE_RATE_LOOP: begin
            if (rate_converged || rate_loop_count >= RATE_LOOP_MAX) begin
                next_state = STATE_OUTPUT;
            end else begin
                next_state = STATE_QUANTIZE;
            end
        end
        
        STATE_QUANTIZE: begin
            if (collect_counter >= frame_size) begin
                next_state = STATE_COUNT_BITS;
            end
        end
        
        STATE_COUNT_BITS: begin
            next_state = STATE_ADJUST_RATE;
        end
        
        STATE_ADJUST_RATE: begin
            next_state = STATE_RATE_LOOP;
        end
        
        STATE_OUTPUT: begin
            if (output_counter >= frame_size && quant_ready) begin
                next_state = STATE_FRAME_END;
            end
        end
        
        STATE_FRAME_END: begin
            next_state = STATE_IDLE;
        end
        
        STATE_ERROR: begin
            if (!enable) begin
                next_state = STATE_IDLE;
            end
        end
        
        default: begin
            next_state = STATE_ERROR;
        end
    endcase
end

//=============================================================================
// 帧大小计算
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_size <= 10'd160;  // 默认160点(16kHz@10ms)
    end else if (current_state == STATE_LOAD_CONFIG) begin
        case ({sample_rate[15:12], frame_duration})
            {4'h1, 2'b10}: frame_size <= 10'd160;  // 16kHz, 10ms
            {4'h1, 2'b01}: frame_size <= 10'd80;   // 16kHz, 5ms
            {4'h2, 2'b10}: frame_size <= 10'd240;  // 24kHz, 10ms
            {4'h2, 2'b01}: frame_size <= 10'd120;  // 24kHz, 5ms
            {4'h3, 2'b10}: frame_size <= 10'd480;  // 48kHz, 10ms
            {4'h3, 2'b01}: frame_size <= 10'd240;  // 48kHz, 5ms
            default: frame_size <= 10'd160;
        endcase
    end
end

//=============================================================================
// 目标比特数计算
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        target_bits <= 16'd320;  // 默认320比特
    end else if (current_state == STATE_CALC_TARGET) begin
        case (frame_duration)
            2'b10: begin  // 10ms帧
                target_bits <= {target_bitrate, 3'b000} + {1'b0, target_bitrate, 2'b00}; // target_bitrate * 10
            end
            2'b01: begin  // 5ms帧  
                target_bits <= {1'b0, target_bitrate, 2'b00} + {2'b00, target_bitrate, 1'b0}; // target_bitrate * 5
            end
            default: begin
                target_bits <= {target_bitrate, 3'b000} + {1'b0, target_bitrate, 2'b00}; // 默认10ms
            end
        endcase
    end
end

//=============================================================================
// 频谱数据收集
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        collect_counter <= 10'd0;
        input_spectral_data <= 24'd0;
        input_envelope <= 24'd0;
        input_masking <= 16'd0;
        input_index <= 10'd0;
        frame_active <= 1'b0;
    end else begin
        case (current_state)
            STATE_COLLECT_SPEC: begin
                if (spectral_valid && spectral_ready) begin
                    input_spectral_data <= spectral_data;
                    input_envelope <= spectral_envelope;
                    input_masking <= spectral_masking;
                    input_index <= spectral_index;
                    
                    if (collect_counter < frame_size) begin
                        collect_counter <= collect_counter + 10'd1;
                    end
                    
                    frame_active <= 1'b1;
                end
            end
            
            STATE_LOAD_CONFIG: begin
                collect_counter <= 10'd0;
                frame_active <= 1'b0;
            end
            
            STATE_QUANTIZE: begin
                if (collect_counter < frame_size) begin
                    collect_counter <= collect_counter + 10'd1;
                end
            end
        endcase
    end
end

//=============================================================================
// 初始量化参数设置
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        base_quant_step <= 8'd16;      // 默认量化步长
        current_quant_step <= 8'd16;
        global_scale <= 4'd0;
        effective_bandwidth <= 8'd160;
    end else if (current_state == STATE_INIT_QUANT) begin
        // 根据目标比特率初始化量化步长
        case (target_bitrate)
            8'd16, 8'd24, 8'd32: begin
                base_quant_step <= 8'd64;   // 低比特率
                global_scale <= 4'd3;
            end
            8'd48, 8'd64: begin
                base_quant_step <= 8'd32;   // 中比特率
                global_scale <= 4'd2;
            end
            8'd96, 8'd128: begin
                base_quant_step <= 8'd16;   // 高比特率
                global_scale <= 4'd1;
            end
            default: begin
                base_quant_step <= 8'd8;    // 极高比特率
                global_scale <= 4'd0;
            end
        endcase
        
        current_quant_step <= base_quant_step;
        effective_bandwidth <= spectral_bandwidth;
    end
end

//=============================================================================
// 率失真优化循环
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rate_loop_count <= 4'd0;
        estimated_bits <= 16'd0;
        actual_bits <= 16'd0;
        step_adjust <= 8'd0;
        rate_converged <= 1'b0;
    end else begin
        case (current_state)
            STATE_RATE_LOOP: begin
                if (rate_loop_count == 4'd0) begin
                    // 首次进入，估计比特数
                    estimated_bits <= estimate_bit_count(current_quant_step, effective_bandwidth);
                    rate_converged <= 1'b0;
                end
                rate_loop_count <= rate_loop_count + 4'd1;
            end
            
            STATE_COUNT_BITS: begin
                // 统计实际比特数(简化模型)
                actual_bits <= nonzero_coeffs[15:0] + (nonzero_coeffs[15:0] >> 2); // 近似计算
            end
            
            STATE_ADJUST_RATE: begin
                // 调整量化步长
                if (actual_bits > target_bits + 16'd8) begin
                    // 比特数过多，增大量化步长
                    if (current_quant_step < MAX_QUANT_STEP - 8'd8) begin
                        current_quant_step <= current_quant_step + 8'd8;
                    end
                end else if (actual_bits < target_bits - 16'd8) begin
                    // 比特数过少，减小量化步长
                    if (current_quant_step > MIN_QUANT_STEP + 8'd4) begin
                        current_quant_step <= current_quant_step - 8'd4;
                    end
                end else begin
                    // 比特数接近目标，收敛
                    rate_converged <= 1'b1;
                end
            end
            
            STATE_INIT_QUANT: begin
                rate_loop_count <= 4'd0;
                rate_converged <= 1'b0;
            end
        endcase
    end
end

//=============================================================================
// 量化计算模块
//=============================================================================

// 量化输入处理
assign quant_input = {input_spectral_data, 8'h00};
assign quant_threshold = {input_masking, 16'h0000};
assign effective_step = current_quant_step + {4'h0, global_scale};

// 量化运算 - 简化的均匀量化器
quantizer_core u_quantizer (
    .clk            (clk),
    .rst_n          (rst_n),
    .enable         (current_state == STATE_QUANTIZE),
    .input_data     (quant_input),
    .quant_step     (effective_step),
    .threshold      (quant_threshold),
    .quant_result   (quant_result)
);

//=============================================================================
// 统计计算
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        coeffs_processed <= 32'd0;
        nonzero_coeffs <= 32'd0;
        total_energy <= 32'd0;
        peak_amplitude <= 16'd0;
    end else begin
        case (current_state)
            STATE_COLLECT_SPEC: begin
                if (spectral_valid && spectral_ready) begin
                    coeffs_processed <= coeffs_processed + 32'd1;
                    
                    // 统计非零系数
                    if (|spectral_data) begin
                        nonzero_coeffs <= nonzero_coeffs + 32'd1;
                    end
                    
                    // 累计能量
                    total_energy <= total_energy + {8'h00, spectral_data};
                    
                    // 更新峰值
                    if (spectral_data[15:0] > peak_amplitude) begin
                        peak_amplitude <= spectral_data[15:0];
                    end
                end
            end
            
            STATE_LOAD_CONFIG: begin
                coeffs_processed <= 32'd0;
                nonzero_coeffs <= 32'd0;
                total_energy <= 32'd0;
                peak_amplitude <= 16'd0;
            end
        endcase
    end
end

//=============================================================================
// 输出控制
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        output_counter <= 10'd0;
        output_valid_r <= 1'b0;
        output_data_r <= 16'd0;
        output_step_r <= 8'd0;
        output_scale_r <= 4'd0;
        output_index_r <= 10'd0;
        output_frame_end_r <= 1'b0;
    end else begin
        case (current_state)
            STATE_OUTPUT: begin
                if (quant_ready) begin
                    output_valid_r <= 1'b1;
                    output_data_r <= quant_result;
                    output_step_r <= current_quant_step;
                    output_scale_r <= global_scale;
                    output_index_r <= output_counter;
                    
                    if (output_counter >= frame_size - 10'd1) begin
                        output_frame_end_r <= 1'b1;
                        output_counter <= 10'd0;
                    end else begin
                        output_frame_end_r <= 1'b0;
                        output_counter <= output_counter + 10'd1;
                    end
                end
            end
            
            STATE_FRAME_END: begin
                output_valid_r <= 1'b0;
                output_frame_end_r <= 1'b0;
            end
            
            default: begin
                if (!quant_ready) begin
                    output_valid_r <= 1'b0;
                end
            end
        endcase
    end
end

//=============================================================================
// 存储器接口控制
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_req_valid_r <= 1'b0;
        mem_req_addr_r <= 12'h000;
        mem_req_wdata_r <= 32'h00000000;
        mem_req_wen_r <= 1'b0;
        mem_operation_pending <= 1'b0;
    end else begin
        // 存储器访问状态机(简化实现)
        case (current_state)
            STATE_COLLECT_SPEC: begin
                if (spectral_valid && spectral_ready && !mem_operation_pending) begin
                    // 存储频谱数据
                    mem_req_valid_r <= 1'b1;
                    mem_req_addr_r <= ADDR_SPECTRAL_BASE + {2'b00, input_index};
                    mem_req_wdata_r <= {8'h00, input_spectral_data};
                    mem_req_wen_r <= 1'b1;
                    mem_operation_pending <= 1'b1;
                end
            end
            
            default: begin
                if (mem_req_ready) begin
                    mem_req_valid_r <= 1'b0;
                    mem_operation_pending <= 1'b0;
                end
            end
        endcase
    end
end

//=============================================================================
// 比特数估计函数
//=============================================================================

function [15:0] estimate_bit_count;
    input [7:0] step;
    input [7:0] bandwidth;
    reg [15:0] base_bits;
    reg [3:0] complexity_factor;
begin
    // 简化的比特数估计模型
    base_bits = {bandwidth, 3'b000} >> 2;  // bandwidth * 2
    
    case (step)
        8'd1, 8'd2, 8'd4: complexity_factor = 4'd8;    // 小步长，高复杂度
        8'd8, 8'd16: complexity_factor = 4'd4;         // 中步长，中复杂度
        8'd32, 8'd64: complexity_factor = 4'd2;        // 大步长，低复杂度
        default: complexity_factor = 4'd1;             // 极大步长，极低复杂度
    endcase
    
    estimate_bit_count = base_bits + (base_bits >> complexity_factor);
end
endfunction

//=============================================================================
// 输出接口连接
//=============================================================================

assign spectral_ready = (current_state == STATE_COLLECT_SPEC) && !mem_operation_pending;
assign quant_valid = output_valid_r;
assign quant_data = output_data_r;
assign quant_step = output_step_r;
assign quant_scale = output_scale_r;
assign quant_index = output_index_r;
assign quant_frame_end = output_frame_end_r;

assign mem_req_valid = mem_req_valid_r;
assign mem_req_addr = mem_req_addr_r;
assign mem_req_wdata = mem_req_wdata_r;
assign mem_req_wen = mem_req_wen_r;

assign processing = (current_state != STATE_IDLE);

//=============================================================================
// 状态和调试信息
//=============================================================================

assign status_reg = {
    4'h0,                       // [31:28] 保留
    current_state,              // [27:24] 当前状态
    4'h0,                       // [23:20] 保留  
    rate_loop_count,            // [19:16] 率失真循环计数
    target_bits                 // [15:0]  目标比特数
};

assign debug_info = {
    8'h00,                      // [31:24] 保留
    current_quant_step,         // [23:16] 当前量化步长
    effective_bandwidth,        // [15:8]  有效带宽
    global_scale,               // [7:4]   全局缩放
    3'b000,                     // [3:1]   保留
    rate_converged              // [0]     收敛标志
};

endmodule

//=============================================================================
// 量化器核心模块
//=============================================================================

module quantizer_core (
    input                       clk,
    input                       rst_n,
    input                       enable,
    input       [31:0]          input_data,
    input       [7:0]           quant_step,
    input       [31:0]          threshold,
    output reg  [15:0]          quant_result
);

// 量化计算
wire [31:0] abs_input;
wire [31:0] scaled_threshold;
wire [31:0] quantized;
wire        sign_bit;

assign sign_bit = input_data[31];
assign abs_input = sign_bit ? (~input_data + 1'b1) : input_data;
assign scaled_threshold = threshold >> 2;  // 阈值缩放

// 简化的均匀量化器
assign quantized = (abs_input > scaled_threshold) ? 
                   (abs_input / {24'h000000, quant_step}) : 32'h00000000;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        quant_result <= 16'h0000;
    end else if (enable) begin
        // 应用符号并限制输出范围
        if (quantized[15:0] == 16'h0000) begin
            quant_result <= 16'h0000;
        end else begin
            quant_result <= sign_bit ? (~quantized[15:0] + 1'b1) : quantized[15:0];
        end
    end
end

endmodule 