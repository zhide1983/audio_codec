//============================================================================
// Module Name  : spectral_analysis.v
// Description  : 频谱分析模块 - 实现频谱包络估计和掩蔽分析
//                符合RTL设计规则：Verilog 2001, 单端口存储器, 无移位操作符
// Author       : Audio Codec Design Team
// Date         : 2024-06-11
// Version      : v1.0
//============================================================================

`timescale 1ns / 1ps

module spectral_analysis (
    // 系统信号
    input                       clk,
    input                       rst_n,
    
    // 配置接口
    input       [1:0]           frame_duration,     // 帧长配置
    input                       channel_mode,       // 通道模式
    input       [4:0]           bandwidth_config,   // 带宽配置 (4-24kHz)
    input                       enable,             // 模块使能
    
    // 输入数据接口 (来自MDCT变换)
    input                       input_valid,        // 输入数据有效
    input       [15:0]          input_real,         // MDCT系数实部
    input       [15:0]          input_imag,         // MDCT系数虚部
    input       [9:0]           input_index,        // 系数索引
    output                      input_ready,        // 输入就绪信号
    
    // 输出数据接口 (到量化控制)
    output                      output_valid,       // 输出数据有效
    output      [15:0]          spectral_envelope,  // 频谱包络
    output      [15:0]          masking_threshold,  // 掩蔽阈值
    output      [15:0]          noise_shaping,      // 噪声整形参数
    output      [9:0]           band_index,         // 频带索引
    input                       output_ready,       // 下游就绪信号
    
    // 存储器接口 (工作缓冲器)
    output                      mem_req_valid,      // 存储器请求有效
    output      [11:0]          mem_req_addr,       // 存储器地址 
    output      [31:0]          mem_req_wdata,      // 写数据
    output                      mem_req_wen,        // 写使能
    input                       mem_req_ready,      // 存储器就绪
    input       [31:0]          mem_req_rdata,      // 读数据
    
    // Bark尺度系数ROM接口
    output                      bark_req_valid,     // Bark系数请求有效
    output      [7:0]           bark_req_addr,      // Bark系数地址
    input       [31:0]          bark_req_data,      // Bark系数数据
    input                       bark_req_ready,     // Bark系数就绪
    
    // 状态输出
    output                      analysis_busy,      // 分析忙碌状态
    output                      frame_done,         // 帧分析完成
    output      [31:0]          spectral_stats,     // 频谱统计信息
    output      [31:0]          debug_info          // 调试信息
);

//============================================================================
// 参数定义
//============================================================================
// 帧长对应的系数数量
parameter N_160_COEFFS = 80;   // 160点MDCT -> 80个系数
parameter N_320_COEFFS = 160;  // 320点MDCT -> 160个系数  
parameter N_640_COEFFS = 320;  // 640点MDCT -> 320个系数

// Bark频带数量
parameter NUM_BARK_BANDS = 64;

// 状态机状态
localparam IDLE           = 3'b000;    // 空闲状态
localparam INPUT_COLLECT  = 3'b001;    // 收集MDCT系数
localparam POWER_CALC     = 3'b010;    // 功率谱计算
localparam BARK_MAPPING   = 3'b011;    // Bark频带映射
localparam ENVELOPE_EST   = 3'b100;    // 包络估计
localparam MASKING_CALC   = 3'b101;    // 掩蔽计算
localparam OUTPUT_GEN     = 3'b110;    // 输出生成
localparam ERROR          = 3'b111;    // 错误状态

// 存储器地址映射
localparam MDCT_BUFFER_BASE    = 12'h400;  // MDCT系数缓冲
localparam POWER_BUFFER_BASE   = 12'h480;  // 功率谱缓冲
localparam ENVELOPE_BASE       = 12'h4C0;  // 频谱包络
localparam THRESHOLD_BASE      = 12'h4E0;  // 掩蔽阈值
localparam SHAPING_BASE        = 12'h500;  // 噪声整形参数

//============================================================================
// 内部信号定义
//============================================================================
// 状态机
reg [2:0] current_state, next_state;

// 配置信号
reg [9:0] max_coefficients;     // 最大系数数量
reg [5:0] num_bands;            // 有效频带数量

// 计数器
reg [9:0] coefficient_count;    // 系数计数
reg [9:0] process_count;        // 处理计数
reg [5:0] band_count;           // 频带计数
reg [5:0] output_count;         // 输出计数

// 数据寄存器
reg [31:0] power_accumulator;   // 功率累积器
reg [31:0] band_energy;         // 频带能量

// 输出寄存器  
reg        output_valid_reg;
reg [15:0] spectral_envelope_reg;
reg [15:0] masking_threshold_reg;
reg [15:0] noise_shaping_reg;
reg [9:0]  band_index_reg;

// 存储器接口
reg        mem_req_valid_reg;
reg [11:0] mem_req_addr_reg;
reg [31:0] mem_req_wdata_reg;
reg        mem_req_wen_reg;

// Bark ROM接口
reg        bark_req_valid_reg;
reg [7:0]  bark_req_addr_reg;

// 状态信号
reg        analysis_busy_reg;
reg        frame_done_reg;
reg [31:0] spectral_stats_reg;

//============================================================================
// 配置逻辑
//============================================================================
always @(*) begin
    case (frame_duration)
        2'b00: begin  // 2.5ms
            max_coefficients = N_160_COEFFS;
            num_bands = 32;  // 减少频带数以适应较短帧长
        end
        2'b01: begin  // 5ms
            max_coefficients = N_320_COEFFS;
            num_bands = 48;
        end
        2'b10: begin  // 10ms
            max_coefficients = N_640_COEFFS;
            num_bands = NUM_BARK_BANDS;
        end
        default: begin
            max_coefficients = N_640_COEFFS;
            num_bands = NUM_BARK_BANDS;
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
                next_state = INPUT_COLLECT;
            end
        end
        
        INPUT_COLLECT: begin
            if (coefficient_count >= max_coefficients - 1) begin
                next_state = POWER_CALC;
            end else if (!enable) begin
                next_state = IDLE;
            end
        end
        
        POWER_CALC: begin
            if (process_count >= max_coefficients - 1) begin
                next_state = BARK_MAPPING;
            end
        end
        
        BARK_MAPPING: begin
            if (band_count >= num_bands - 1) begin
                next_state = ENVELOPE_EST;
            end
        end
        
        ENVELOPE_EST: begin
            if (band_count >= num_bands - 1) begin
                next_state = MASKING_CALC;
            end
        end
        
        MASKING_CALC: begin
            if (band_count >= num_bands - 1) begin
                next_state = OUTPUT_GEN;
            end
        end
        
        OUTPUT_GEN: begin
            if (output_count >= num_bands - 1) begin
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
// 系数输入缓冲
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        coefficient_count <= 10'h0;
    end else begin
        case (current_state)
            IDLE: begin
                coefficient_count <= 10'h0;
            end
            
            INPUT_COLLECT: begin
                if (input_valid && input_ready) begin
                    coefficient_count <= coefficient_count + 1;
                end
            end
        endcase
    end
end

assign input_ready = (current_state == INPUT_COLLECT) && 
                     (coefficient_count < max_coefficients) &&
                     mem_req_ready;

//============================================================================
// 处理计数器
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        process_count <= 10'h0;
        band_count <= 6'h0;
        output_count <= 6'h0;
    end else begin
        case (current_state)
            POWER_CALC: begin
                if (mem_req_ready) begin
                    process_count <= process_count + 1;
                end
            end
            
            BARK_MAPPING, ENVELOPE_EST, MASKING_CALC: begin
                if (mem_req_ready && bark_req_ready) begin
                    band_count <= band_count + 1;
                end
            end
            
            OUTPUT_GEN: begin
                if (output_ready && output_valid_reg) begin
                    output_count <= output_count + 1;
                end
            end
            
            default: begin
                process_count <= 10'h0;
                band_count <= 6'h0;
                output_count <= 6'h0;
            end
        endcase
    end
end

//============================================================================
// 算法处理函数
//============================================================================
// 功率谱计算
function [31:0] power_spectrum;
    input [15:0] real_part, imag_part;
    reg [31:0] real_sq, imag_sq;
    begin
        real_sq = real_part * real_part;
        imag_sq = imag_part * imag_part;
        power_spectrum = real_sq + imag_sq;
    end
endfunction

//============================================================================
// 数据处理逻辑
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        power_accumulator <= 32'h0;
        band_energy <= 32'h0;
    end else begin
        case (current_state)
            POWER_CALC: begin
                if (mem_req_ready) begin
                    // 计算功率谱
                    power_accumulator <= power_spectrum(input_real, input_imag);
                end
            end
            
            BARK_MAPPING: begin
                if (mem_req_ready && bark_req_ready) begin
                    // 累积频带能量
                    band_energy <= band_energy + power_accumulator;
                end
            end
            
            default: begin
                if (current_state == IDLE) begin
                    band_energy <= 32'h0;
                end
            end
        endcase
    end
end

//============================================================================
// 输出控制
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        output_valid_reg <= 1'b0;
        spectral_envelope_reg <= 16'h0;
        masking_threshold_reg <= 16'h0;
        noise_shaping_reg <= 16'h0;
        band_index_reg <= 10'h0;
    end else begin
        case (current_state)
            OUTPUT_GEN: begin
                if (output_ready) begin
                    output_valid_reg <= 1'b1;
                    
                    // 读取存储的包络数据
                    spectral_envelope_reg <= mem_req_rdata[31:16];
                    masking_threshold_reg <= mem_req_rdata[15:0];
                    noise_shaping_reg <= bark_req_data[15:0];
                    band_index_reg <= output_count;
                end
            end
            
            default: begin
                output_valid_reg <= 1'b0;
            end
        endcase
    end
end

//============================================================================
// 存储器接口控制
//============================================================================
always @(*) begin
    case (current_state)
        INPUT_COLLECT: begin
            // 存储MDCT系数
            mem_req_valid_reg = input_valid && input_ready;
            mem_req_addr_reg = MDCT_BUFFER_BASE + coefficient_count;
            mem_req_wdata_reg = {input_real, input_imag};
            mem_req_wen_reg = 1'b1;
        end
        
        POWER_CALC: begin
            // 读取MDCT系数，写入功率谱
            mem_req_valid_reg = 1'b1;
            mem_req_addr_reg = POWER_BUFFER_BASE + process_count;
            mem_req_wdata_reg = power_accumulator;
            mem_req_wen_reg = 1'b1;
        end
        
        ENVELOPE_EST: begin
            // 写入频谱包络
            mem_req_valid_reg = 1'b1;
            mem_req_addr_reg = ENVELOPE_BASE + band_count;
            mem_req_wdata_reg = {band_energy[31:16], band_energy[15:0]};
            mem_req_wen_reg = 1'b1;
        end
        
        OUTPUT_GEN: begin
            // 读取分析结果
            mem_req_valid_reg = 1'b1;
            mem_req_addr_reg = ENVELOPE_BASE + output_count;
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
// Bark ROM接口控制
//============================================================================
always @(*) begin
    case (current_state)
        BARK_MAPPING: begin
            // 读取Bark频带映射
            bark_req_valid_reg = 1'b1;
            bark_req_addr_reg = 8'h00 + band_count;
        end
        
        OUTPUT_GEN: begin
            // 读取噪声整形相关系数
            bark_req_valid_reg = 1'b1;
            bark_req_addr_reg = 8'h80 + output_count;
        end
        
        default: begin
            bark_req_valid_reg = 1'b0;
            bark_req_addr_reg = 8'h0;
        end
    endcase
end

//============================================================================
// 状态输出
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        analysis_busy_reg <= 1'b0;
        frame_done_reg <= 1'b0;
        spectral_stats_reg <= 32'h0;
    end else begin
        analysis_busy_reg <= (current_state != IDLE);
        
        if (current_state == OUTPUT_GEN && output_count == num_bands - 1) begin
            frame_done_reg <= 1'b1;
        end else begin
            frame_done_reg <= 1'b0;
        end
        
        // 更新频谱统计信息
        spectral_stats_reg <= {band_energy[31:16], band_energy[15:0]};
    end
end

//============================================================================
// 输出端口赋值
//============================================================================
assign output_valid = output_valid_reg;
assign spectral_envelope = spectral_envelope_reg;
assign masking_threshold = masking_threshold_reg;
assign noise_shaping = noise_shaping_reg;
assign band_index = band_index_reg;

assign mem_req_valid = mem_req_valid_reg;
assign mem_req_addr = mem_req_addr_reg;
assign mem_req_wdata = mem_req_wdata_reg;
assign mem_req_wen = mem_req_wen_reg;

assign bark_req_valid = bark_req_valid_reg;
assign bark_req_addr = bark_req_addr_reg;

assign analysis_busy = analysis_busy_reg;
assign frame_done = frame_done_reg;
assign spectral_stats = spectral_stats_reg;

// 调试信息
assign debug_info = {
    8'h0,                    // [31:24] 保留
    current_state,           // [23:21] 当前状态
    frame_duration,          // [20:19] 帧长配置
    channel_mode,            // [18] 通道模式
    enable,                  // [17] 使能
    input_ready,             // [16] 输入就绪
    coefficient_count[15:0]  // [15:0] 系数计数
};

endmodule 