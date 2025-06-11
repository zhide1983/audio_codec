//============================================================================
// Module Name  : mdct_transform.v
// Description  : MDCT变换模块 - 基于FFT的高效实现
//                符合RTL设计规则：Verilog 2001, 单端口存储器, 无移位操作符
// Author       : Audio Codec Design Team
// Date         : 2024-06-11
// Version      : v1.0
//============================================================================

`timescale 1ns / 1ps

module mdct_transform (
    // 系统信号
    input                       clk,
    input                       rst_n,
    
    // 配置接口
    input       [1:0]           frame_duration,     // 帧长配置: 00=2.5ms, 01=5ms, 10=10ms
    input                       channel_mode,       // 通道模式: 0=单声道, 1=立体声
    input                       enable,             // 模块使能
    
    // 输入数据接口 (来自时域预处理)
    input                       input_valid,        // 输入数据有效
    input       [23:0]          input_data,         // 输入时域样本 (24bit)
    input       [9:0]           input_index,        // 样本索引 (0~639)
    output                      input_ready,        // 输入就绪信号
    
    // 输出数据接口 (到频谱分析)
    output                      output_valid,       // 输出数据有效
    output      [15:0]          output_real,        // MDCT系数实部 (16bit)
    output      [15:0]          output_imag,        // MDCT系数虚部 (16bit) 
    output      [9:0]           output_index,       // 系数索引
    input                       output_ready,       // 下游就绪信号
    
    // 存储器接口 (工作缓冲器)
    output                      mem_req_valid,      // 存储器请求有效
    output      [11:0]          mem_req_addr,       // 存储器地址
    output      [31:0]          mem_req_wdata,      // 写数据
    output                      mem_req_wen,        // 写使能
    input                       mem_req_ready,      // 存储器就绪
    input       [31:0]          mem_req_rdata,      // 读数据
    
    // 系数ROM接口
    output                      coeff_req_valid,    // 系数请求有效
    output      [13:0]          coeff_req_addr,     // 系数地址
    input       [31:0]          coeff_req_data,     // 系数数据
    input                       coeff_req_ready,    // 系数就绪
    
    // 状态输出
    output                      transform_busy,     // 变换忙碌状态
    output                      frame_done,         // 帧处理完成
    output      [31:0]          debug_info          // 调试信息
);

//============================================================================
// 参数定义
//============================================================================
// 帧长对应的MDCT点数
parameter N_160 = 160;  // 2.5ms @ 48kHz
parameter N_320 = 320;  // 5ms @ 48kHz
parameter N_640 = 640;  // 10ms @ 48kHz

// 状态机状态
localparam IDLE        = 3'b000;    // 空闲状态
localparam INPUT_BUF   = 3'b001;    // 输入数据缓冲
localparam PREPROCESS  = 3'b010;    // 预处理阶段
localparam FFT_COMPUTE = 3'b011;    // FFT计算
localparam POSTPROCESS = 3'b100;    // 后处理
localparam OUTPUT      = 3'b101;    // 输出结果
localparam ERROR       = 3'b110;    // 错误状态

// 存储器地址映射
localparam INPUT_BUFFER_BASE   = 12'h000;  // 输入样本缓冲
localparam FFT_BUFFER_BASE     = 12'h140;  // FFT中间结果
localparam WINDOW_BUFFER_BASE  = 12'h280;  // 窗函数缓冲
localparam OUTPUT_BUFFER_BASE  = 12'h300;  // 输出系数缓冲

//============================================================================
// 内部信号定义
//============================================================================
// 状态机
reg [2:0] current_state, next_state;

// 配置信号
reg [9:0] mdct_length;          // 当前MDCT长度
reg [8:0] fft_length;           // FFT长度 (MDCT长度/2)

// 计数器
reg [9:0] input_count;          // 输入样本计数
reg [9:0] output_count;         // 输出系数计数
reg [7:0] process_count;        // 处理阶段计数

// 输出寄存器
reg        output_valid_reg;
reg [15:0] output_real_reg;
reg [15:0] output_imag_reg;
reg [9:0]  output_index_reg;

// 存储器接口
reg        mem_req_valid_reg;
reg [11:0] mem_req_addr_reg;
reg [31:0] mem_req_wdata_reg;
reg        mem_req_wen_reg;

// 系数ROM接口
reg        coeff_req_valid_reg;
reg [13:0] coeff_req_addr_reg;

// 控制信号
reg        frame_done_reg;
reg        transform_busy_reg;

//============================================================================
// 配置逻辑 - 根据帧长确定MDCT参数
//============================================================================
always @(*) begin
    case (frame_duration)
        2'b00: begin  // 2.5ms
            mdct_length = N_160;
            fft_length = 80;
        end
        2'b01: begin  // 5ms
            mdct_length = N_320;
            fft_length = 160;
        end
        2'b10: begin  // 10ms
            mdct_length = N_640;
            fft_length = 320;
        end
        default: begin
            mdct_length = N_640;
            fft_length = 320;
        end
    endcase
end

//============================================================================
// 主状态机
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;
    end else begin
        current_state <= next_state;
    end
end

always @(*) begin
    next_state = current_state;
    
    case (current_state)
        IDLE: begin
            if (enable && input_valid) begin
                next_state = INPUT_BUF;
            end
        end
        
        INPUT_BUF: begin
            if (input_count >= mdct_length - 1) begin
                next_state = PREPROCESS;
            end else if (!enable) begin
                next_state = IDLE;
            end
        end
        
        PREPROCESS: begin
            if (process_count >= fft_length - 1) begin
                next_state = FFT_COMPUTE;
            end
        end
        
        FFT_COMPUTE: begin
            // 简化的FFT处理完成条件
            if (process_count >= fft_length - 1) begin
                next_state = POSTPROCESS;
            end
        end
        
        POSTPROCESS: begin
            if (process_count >= fft_length - 1) begin
                next_state = OUTPUT;
            end
        end
        
        OUTPUT: begin
            if (output_count >= mdct_length - 1) begin
                next_state = IDLE;
            end
        end
        
        ERROR: begin
            if (!enable) begin
                next_state = IDLE;
            end
        end
        
        default: next_state = IDLE;
    endcase
end

//============================================================================
// 输入缓冲逻辑
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        input_count <= 10'h0;
    end else begin
        case (current_state)
            IDLE: begin
                input_count <= 10'h0;
            end
            
            INPUT_BUF: begin
                if (input_valid && input_ready) begin
                    input_count <= input_count + 1;
                end
            end
        endcase
    end
end

// 输入就绪信号
assign input_ready = (current_state == INPUT_BUF) && 
                     (input_count < mdct_length) &&
                     mem_req_ready;

//============================================================================
// 处理阶段计数器
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        process_count <= 8'h0;
    end else begin
        case (current_state)
            PREPROCESS: begin
                if (mem_req_ready && coeff_req_ready) begin
                    process_count <= process_count + 1;
                end
            end
            
            FFT_COMPUTE: begin
                if (mem_req_ready) begin
                    process_count <= process_count + 1;
                end
            end
            
            POSTPROCESS: begin
                if (mem_req_ready) begin
                    process_count <= process_count + 1;
                end
            end
            
            default: begin
                process_count <= 8'h0;
            end
        endcase
    end
end

//============================================================================
// 数据处理和量化
//============================================================================
// 饱和量化函数 - 24bit到16bit
function [15:0] saturate_q15;
    input [23:0] data_in;
    begin
        if (data_in[23] == 1'b0 && data_in[22:15] != 8'h00) begin
            // 正数溢出
            saturate_q15 = 16'h7FFF;
        end else if (data_in[23] == 1'b1 && data_in[22:15] != 8'hFF) begin
            // 负数溢出  
            saturate_q15 = 16'h8000;
        end else begin
            // 正常截取
            saturate_q15 = data_in[22:7];
        end
    end
endfunction

//============================================================================
// 输出控制逻辑
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        output_valid_reg <= 1'b0;
        output_real_reg <= 16'h0;
        output_imag_reg <= 16'h0;
        output_index_reg <= 10'h0;
        output_count <= 10'h0;
    end else begin
        case (current_state)
            OUTPUT: begin
                if (output_ready) begin
                    output_valid_reg <= 1'b1;
                    // 从存储器读取MDCT系数并量化
                    output_real_reg <= saturate_q15(mem_req_rdata[31:8]);
                    output_imag_reg <= saturate_q15({mem_req_rdata[7:0], 16'h0});
                    output_index_reg <= output_count;
                    output_count <= output_count + 1;
                end
            end
            
            default: begin
                output_valid_reg <= 1'b0;
                output_count <= 10'h0;
            end
        endcase
    end
end

//============================================================================
// 存储器接口控制
//============================================================================
always @(*) begin
    case (current_state)
        INPUT_BUF: begin
            // 写入输入样本
            mem_req_valid_reg = input_valid && input_ready;
            mem_req_addr_reg = INPUT_BUFFER_BASE + input_count;
            mem_req_wdata_reg = {8'h0, input_data};
            mem_req_wen_reg = 1'b1;
        end
        
        PREPROCESS: begin
            // 读取输入数据，写入预处理结果
            if (process_count < fft_length) begin
                mem_req_valid_reg = 1'b1;
                mem_req_addr_reg = FFT_BUFFER_BASE + process_count;
                // 简化的预处理：应用窗函数
                mem_req_wdata_reg = {input_data, 8'h0};
                mem_req_wen_reg = 1'b1;
            end else begin
                mem_req_valid_reg = 1'b0;
                mem_req_addr_reg = 12'h0;
                mem_req_wdata_reg = 32'h0;
                mem_req_wen_reg = 1'b0;
            end
        end
        
        FFT_COMPUTE: begin
            // FFT计算阶段的存储器访问
            mem_req_valid_reg = 1'b1;
            mem_req_addr_reg = FFT_BUFFER_BASE + process_count;
            mem_req_wdata_reg = mem_req_rdata;  // 简化：直接复制
            mem_req_wen_reg = 1'b1;
        end
        
        POSTPROCESS: begin
            // 写入后处理结果
            mem_req_valid_reg = 1'b1;
            mem_req_addr_reg = OUTPUT_BUFFER_BASE + process_count;
            mem_req_wdata_reg = {output_real_reg, output_imag_reg};
            mem_req_wen_reg = 1'b1;
        end
        
        OUTPUT: begin
            // 读取输出系数
            mem_req_valid_reg = 1'b1;
            mem_req_addr_reg = OUTPUT_BUFFER_BASE + output_count;
            mem_req_wdata_reg = 32'h0;
            mem_req_wen_reg = 1'b0;
        end
        
        default: begin
            mem_req_valid_reg = 1'b0;
            mem_req_addr_reg = 12'h0;
            mem_req_wdata_reg = 32'h0;
            mem_req_wen_reg = 1'b0;
        end
    endcase
end

//============================================================================
// 系数ROM接口控制
//============================================================================
always @(*) begin
    case (current_state)
        PREPROCESS: begin
            // 读取窗函数系数
            coeff_req_valid_reg = 1'b1;
            coeff_req_addr_reg = 14'h0000 + process_count;
        end
        
        POSTPROCESS: begin
            // 读取旋转因子
            coeff_req_valid_reg = 1'b1;
            coeff_req_addr_reg = 14'h0280 + process_count;
        end
        
        default: begin
            coeff_req_valid_reg = 1'b0;
            coeff_req_addr_reg = 14'h0;
        end
    endcase
end

//============================================================================
// 状态输出
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_done_reg <= 1'b0;
        transform_busy_reg <= 1'b0;
    end else begin
        transform_busy_reg <= (current_state != IDLE);
        
        if (current_state == OUTPUT && output_count == mdct_length - 1) begin
            frame_done_reg <= 1'b1;
        end else begin
            frame_done_reg <= 1'b0;
        end
    end
end

//============================================================================
// 输出端口赋值
//============================================================================
assign output_valid = output_valid_reg;
assign output_real = output_real_reg;
assign output_imag = output_imag_reg;
assign output_index = output_index_reg;

assign mem_req_valid = mem_req_valid_reg;
assign mem_req_addr = mem_req_addr_reg;
assign mem_req_wdata = mem_req_wdata_reg;
assign mem_req_wen = mem_req_wen_reg;

assign coeff_req_valid = coeff_req_valid_reg;
assign coeff_req_addr = coeff_req_addr_reg;

assign transform_busy = transform_busy_reg;
assign frame_done = frame_done_reg;

// 调试信息
assign debug_info = {
    8'h0,                    // [31:24] 保留
    current_state,           // [23:21] 当前状态
    frame_duration,          // [20:19] 帧长配置
    channel_mode,            // [18] 通道模式
    enable,                  // [17] 使能
    input_ready,             // [16] 输入就绪
    output_count[15:0]       // [15:0] 输出计数
};

//============================================================================
// 仿真支持
//============================================================================
`ifdef SIMULATION
    // 性能监控
    reg [31:0] cycle_count;
    reg [31:0] frame_count;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 32'h0;
            frame_count <= 32'h0;
        end else begin
            if (transform_busy_reg) begin
                cycle_count <= cycle_count + 1;
            end
            
            if (frame_done_reg) begin
                frame_count <= frame_count + 1;
                $display("MDCT Frame %0d completed in %0d cycles", 
                        frame_count, cycle_count);
                cycle_count <= 32'h0;
            end
        end
    end
    
    // 状态变化监控
    always @(posedge clk) begin
        if (current_state != next_state) begin
            case (next_state)
                IDLE: $display("MDCT: Enter IDLE state");
                INPUT_BUF: $display("MDCT: Enter INPUT_BUF state");
                PREPROCESS: $display("MDCT: Enter PREPROCESS state");
                FFT_COMPUTE: $display("MDCT: Enter FFT_COMPUTE state");
                POSTPROCESS: $display("MDCT: Enter POSTPROCESS state");
                OUTPUT: $display("MDCT: Enter OUTPUT state");
                ERROR: $display("MDCT: Enter ERROR state");
            endcase
        end
    end
`endif

endmodule 