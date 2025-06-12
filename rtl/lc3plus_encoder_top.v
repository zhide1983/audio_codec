//=============================================================================
// LC3plus音频编码器顶层模块 (LC3plus Encoder Top Module)
// 
// 功能：集成完整的LC3plus编码流水线和系统管理功能
// 作者：Audio Codec Design Team
// 版本：v1.0
// 日期：2024-06-11
//=============================================================================

`timescale 1ns/1ps

module lc3plus_encoder_top #(
    // 硬件配置参数
    parameter BUS_TYPE          = "AXI4",      // 总线类型: "AXI4" 或 "AHB3"
    parameter MAX_SAMPLE_RATE   = 48000,       // 最高支持采样率: 48000 或 96000
    parameter MAX_CHANNELS      = 2,           // 最大通道数: 1, 2, 4, 8
    parameter BUFFER_DEPTH      = 2048,        // 内部缓冲深度
    parameter PRECISION_MODE    = "HIGH",      // 精度模式: "HIGH", "MEDIUM", "LOW"
    parameter POWER_OPT         = "BALANCED",  // 功耗优化: "LOW", "BALANCED", "HIGH_PERF"
    parameter PIPELINE_STAGES   = 6,           // 流水线级数
    parameter MEMORY_TYPE       = "SINGLE",    // 存储器类型: "SINGLE", "DUAL", "MULTI"
    parameter DEBUG_ENABLE      = 1            // 调试功能使能
) (
    // 系统信号
    input                       clk,
    input                       rst_n,
    
    // 主配置接口
    input       [1:0]           frame_duration,     // 帧长配置
    input                       channel_mode,       // 通道模式
    input       [7:0]           target_bitrate,     // 目标比特率
    input       [15:0]          sample_rate,        // 采样率
    input                       encoder_enable,     // 编码器总使能
    
    // AXI4-Stream音频输入接口
    input                       s_axis_audio_tvalid, // 音频数据有效
    input       [31:0]          s_axis_audio_tdata,  // 音频数据
    input                       s_axis_audio_tlast,  // 帧结束标志
    output                      s_axis_audio_tready, // 音频输入就绪
    
    // AXI4-Stream比特流输出接口
    output                      m_axis_bitstream_tvalid, // 比特流数据有效
    output      [7:0]           m_axis_bitstream_tdata,  // 比特流字节数据
    output                      m_axis_bitstream_tlast,  // 帧结束标志
    output      [15:0]          m_axis_bitstream_tuser,  // 帧大小信息
    input                       m_axis_bitstream_tready, // 比特流输出就绪
    
    // APB配置接口
    input                       pclk,               // APB时钟
    input                       presetn,            // APB复位
    input                       psel,               // APB选择
    input                       penable,            // APB使能
    input                       pwrite,             // APB写使能
    input       [11:0]          paddr,              // APB地址
    input       [31:0]          pwdata,             // APB写数据
    output      [31:0]          prdata,             // APB读数据
    output                      pready,             // APB就绪
    output                      pslverr,            // APB错误
    
    // 系统存储器接口
    output reg                  mem_req_valid,      // 存储器请求有效
    output reg  [15:0]          mem_req_addr,       // 存储器地址
    output reg  [31:0]          mem_req_wdata,      // 写数据
    output reg                  mem_req_wen,        // 写使能
    input                       mem_req_ready,      // 存储器就绪
    input       [31:0]          mem_req_rdata,      // 读数据
    
    // 系统状态输出
    output                      encoding_active,    // 编码活跃状态
    output                      frame_processing,   // 帧处理状态
    output      [2:0]           pipeline_stage,     // 当前流水线阶段
    output      [31:0]          performance_info,   // 性能信息
    output      [31:0]          error_status,       // 错误状态
    
    // 调试接口
    output      [31:0]          debug_mdct,         // MDCT模块调试信息
    output      [31:0]          debug_spectral,     // 频谱分析调试信息
    output      [31:0]          debug_quantization, // 量化控制调试信息
    output      [31:0]          debug_entropy,      // 熵编码调试信息
    output      [31:0]          debug_packing       // 比特流打包调试信息
);

//=============================================================================
// 参数定义
//=============================================================================

// 流水线阶段定义
localparam STAGE_IDLE      = 3'b000;    // 空闲阶段
localparam STAGE_MDCT      = 3'b001;    // MDCT变换阶段
localparam STAGE_SPECTRAL  = 3'b010;    // 频谱分析阶段
localparam STAGE_QUANTIZE  = 3'b011;    // 量化控制阶段
localparam STAGE_ENTROPY   = 3'b100;    // 熵编码阶段
localparam STAGE_PACKING   = 3'b101;    // 比特流打包阶段
localparam STAGE_OUTPUT    = 3'b110;    // 输出阶段
localparam STAGE_ERROR     = 3'b111;    // 错误阶段

// APB寄存器地址
localparam CTRL_REG_ADDR    = 12'h000;  // 控制寄存器
localparam CONFIG_REG_ADDR  = 12'h004;  // 配置寄存器
localparam STATUS_REG_ADDR  = 12'h008;  // 状态寄存器
localparam ERROR_REG_ADDR   = 12'h00C;  // 错误寄存器
localparam PERF_REG0_ADDR   = 12'h010;  // 性能寄存器0
localparam PERF_REG1_ADDR   = 12'h014;  // 性能寄存器1
localparam DEBUG_REG_ADDR   = 12'h018;  // 调试寄存器
localparam VERSION_REG_ADDR = 12'h01C;  // 版本寄存器

// 版本信息
localparam VERSION_MAJOR = 8'h01;
localparam VERSION_MINOR = 8'h00;
localparam VERSION_PATCH = 16'h0000;

//=============================================================================
// 信号声明
//=============================================================================

// 流水线控制信号
reg     [2:0]           current_pipeline_stage;
reg                     frame_boundary;
reg                     pipeline_active;

// APB配置寄存器
reg     [31:0]          ctrl_reg;
reg     [31:0]          config_reg;
reg     [31:0]          status_reg;
reg     [31:0]          error_reg;
reg     [31:0]          perf_reg0;
reg     [31:0]          perf_reg1;
reg     [31:0]          debug_reg;
wire    [31:0]          version_reg;

// 模块间连接信号 - MDCT
wire                    mdct_input_ready;
wire                    mdct_output_valid;
wire    [15:0]          mdct_output_real;
wire    [15:0]          mdct_output_imag;
wire    [9:0]           mdct_output_index;
wire                    mdct_output_ready;
wire                    mdct_busy;
wire                    mdct_frame_done;

// MDCT系数ROM接口
wire                    mdct_coeff_req_valid;
wire    [13:0]          mdct_coeff_req_addr;
wire    [31:0]          mdct_coeff_req_data;
wire                    mdct_coeff_req_ready;

// 音频样本索引计数器和其他缺失信号
reg     [9:0]           audio_sample_index;
wire    [31:0]          spectral_input_data;

// 模块间连接信号 - Spectral Analysis
wire    [4:0]           spectral_bandwidth_config;
wire                    spectral_input_valid;
wire    [15:0]          spectral_input_real;
wire    [15:0]          spectral_input_imag;
wire    [9:0]           spectral_input_index;
wire                    spectral_input_ready;
wire                    spectral_output_valid;
wire    [15:0]          spectral_envelope;
wire    [15:0]          spectral_masking;
wire    [15:0]          spectral_noise_shaping;
wire    [9:0]           spectral_band_index;
wire                    spectral_output_ready;
wire                    spectral_busy;
wire                    spectral_frame_done;
wire    [31:0]          spectral_stats;

// Bark尺度系数ROM接口
wire                    spectral_bark_req_valid;
wire    [7:0]           spectral_bark_req_addr;
wire    [31:0]          spectral_bark_req_data;
wire                    spectral_bark_req_ready;

// 模块间连接信号 - Quantization Control
wire                    quant_input_valid;
wire    [23:0]          quant_input_data;
wire    [23:0]          quant_envelope;
wire    [15:0]          quant_masking;
wire                    quant_input_ready;
wire                    quant_output_valid;
wire    [15:0]          quant_output_data;
wire    [7:0]           quant_step;
wire    [3:0]           quant_scale;
wire    [9:0]           quant_index;
wire                    quant_frame_done;
wire                    quant_output_ready;

// 模块间连接信号 - Entropy Coding
wire                    entropy_input_valid;
wire    [15:0]          entropy_input_data;
wire    [7:0]           entropy_quant_step;
wire    [3:0]           entropy_scale_factor;
wire    [9:0]           entropy_coeff_index;
wire                    entropy_input_ready;
wire                    entropy_output_valid;
wire    [31:0]          entropy_output_bits;
wire    [5:0]           entropy_bit_count;
wire                    entropy_frame_end;
wire                    entropy_output_ready;

// 模块间连接信号 - Bitstream Packing
wire                    packing_input_valid;
wire    [31:0]          packing_input_bits;
wire    [5:0]           packing_bit_count;
wire                    packing_frame_end;
wire                    packing_input_ready;
wire                    packing_output_valid;
wire    [7:0]           packing_output_byte;
wire                    packing_frame_start;
wire                    packing_frame_complete;
wire    [15:0]          packing_frame_size;
wire                    packing_output_ready;

// 存储器仲裁信号
wire                    mdct_mem_req_valid;
wire    [11:0]          mdct_mem_req_addr;
wire    [31:0]          mdct_mem_req_wdata;
wire                    mdct_mem_req_wen;
reg                     mdct_mem_req_ready;
wire    [31:0]          mdct_mem_req_rdata;

wire                    spectral_mem_req_valid;
wire    [11:0]          spectral_mem_req_addr;
wire    [31:0]          spectral_mem_req_wdata;
wire                    spectral_mem_req_wen;
reg                     spectral_mem_req_ready;
wire    [31:0]          spectral_mem_req_rdata;

wire                    quant_mem_req_valid;
wire    [11:0]          quant_mem_req_addr;
wire    [31:0]          quant_mem_req_wdata;
wire                    quant_mem_req_wen;
reg                     quant_mem_req_ready;
wire    [31:0]          quant_mem_req_rdata;

wire                    entropy_mem_req_valid;
wire    [11:0]          entropy_mem_req_addr;
wire    [31:0]          entropy_mem_req_wdata;
wire                    entropy_mem_req_wen;
reg                     entropy_mem_req_ready;
wire    [31:0]          entropy_mem_req_rdata;

wire                    packing_mem_req_valid;
wire    [11:0]          packing_mem_req_addr;
wire    [31:0]          packing_mem_req_wdata;
wire                    packing_mem_req_wen;
reg                     packing_mem_req_ready;
wire    [31:0]          packing_mem_req_rdata;

// 性能统计信号
reg     [31:0]          frame_count;
reg     [31:0]          cycle_count;
reg     [31:0]          error_count;
reg     [31:0]          max_frame_cycles;
reg     [31:0]          current_frame_cycles;

//=============================================================================
// 版本寄存器
//=============================================================================

assign version_reg = {VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH};

//=============================================================================
// 流水线控制
//=============================================================================

// 流水线状态机
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_pipeline_stage <= STAGE_IDLE;
        pipeline_active <= 1'b0;
        frame_boundary <= 1'b0;
    end else begin
        frame_boundary <= 1'b0; // 默认为0
        
        case (current_pipeline_stage)
            STAGE_IDLE: begin
                pipeline_active <= 1'b0;
                if (encoder_enable && s_axis_audio_tvalid) begin
                    current_pipeline_stage <= STAGE_MDCT;
                    pipeline_active <= 1'b1;
                    frame_boundary <= 1'b1;
                end
            end
            
            STAGE_MDCT: begin
                if (mdct_frame_done) begin
                    current_pipeline_stage <= STAGE_SPECTRAL;
                end
            end
            
            STAGE_SPECTRAL: begin
                if (spectral_frame_done) begin
                    current_pipeline_stage <= STAGE_QUANTIZE;
                end
            end
            
            STAGE_QUANTIZE: begin
                if (quant_frame_done) begin
                    current_pipeline_stage <= STAGE_ENTROPY;
                end
            end
            
            STAGE_ENTROPY: begin
                if (entropy_frame_end) begin
                    current_pipeline_stage <= STAGE_PACKING;
                end
            end
            
            STAGE_PACKING: begin
                if (packing_frame_complete) begin
                    current_pipeline_stage <= STAGE_OUTPUT;
                end
            end
            
            STAGE_OUTPUT: begin
                if (m_axis_bitstream_tready && m_axis_bitstream_tvalid && m_axis_bitstream_tlast) begin
                    current_pipeline_stage <= STAGE_IDLE;
                    frame_boundary <= 1'b1;
                end
            end
            
            default: begin
                current_pipeline_stage <= STAGE_ERROR;
            end
        endcase
    end
end

//=============================================================================
// MDCT变换模块实例化
//=============================================================================

mdct_transform u_mdct_transform (
    .clk                    (clk),
    .rst_n                  (rst_n),
    
    // 配置接口
    .frame_duration         (frame_duration),
    .channel_mode           (channel_mode),
    .enable                 (encoder_enable && (current_pipeline_stage == STAGE_MDCT)),
    
    // 输入数据接口 (正确的端口名称)
    .input_valid            (s_axis_audio_tvalid),
    .input_data             (s_axis_audio_tdata[23:0]),
    .input_index            (audio_sample_index),
    .input_ready            (mdct_input_ready),
    
    // 输出数据接口
    .output_valid           (mdct_output_valid),
    .output_real            (mdct_output_real),
    .output_imag            (mdct_output_imag),
    .output_index           (mdct_output_index),
    .output_ready           (mdct_output_ready),
    
    // 存储器接口
    .mem_req_valid          (mdct_mem_req_valid),
    .mem_req_addr           (mdct_mem_req_addr),
    .mem_req_wdata          (mdct_mem_req_wdata),
    .mem_req_wen            (mdct_mem_req_wen),
    .mem_req_ready          (mdct_mem_req_ready),
    .mem_req_rdata          (mdct_mem_req_rdata),
    
    // 系数ROM接口
    .coeff_req_valid        (mdct_coeff_req_valid),
    .coeff_req_addr         (mdct_coeff_req_addr),
    .coeff_req_data         (mdct_coeff_req_data),
    .coeff_req_ready        (mdct_coeff_req_ready),
    
    // 状态输出
    .transform_busy         (mdct_busy),
    .frame_done             (mdct_frame_done),
    .debug_info             (debug_mdct)
);

//=============================================================================
// 频谱分析模块实例化
//=============================================================================

spectral_analysis u_spectral_analysis (
    .clk                    (clk),
    .rst_n                  (rst_n),
    
    // 配置接口
    .frame_duration         (frame_duration),
    .channel_mode           (channel_mode),
    .bandwidth_config       (spectral_bandwidth_config),
    .enable                 (encoder_enable && (current_pipeline_stage == STAGE_SPECTRAL)),
    
    // 输入数据接口 (正确的端口名称)
    .input_valid            (spectral_input_valid),
    .input_real             (spectral_input_real),
    .input_imag             (spectral_input_imag),
    .input_index            (spectral_input_index),
    .input_ready            (spectral_input_ready),
    
    // 输出数据接口
    .output_valid           (spectral_output_valid),
    .spectral_envelope      (spectral_envelope),
    .masking_threshold      (spectral_masking),
    .noise_shaping          (spectral_noise_shaping),
    .band_index             (spectral_band_index),
    .output_ready           (spectral_output_ready),
    
    // 存储器接口
    .mem_req_valid          (spectral_mem_req_valid),
    .mem_req_addr           (spectral_mem_req_addr),
    .mem_req_wdata          (spectral_mem_req_wdata),
    .mem_req_wen            (spectral_mem_req_wen),
    .mem_req_ready          (spectral_mem_req_ready),
    .mem_req_rdata          (spectral_mem_req_rdata),
    
    // Bark尺度系数ROM接口
    .bark_req_valid         (spectral_bark_req_valid),
    .bark_req_addr          (spectral_bark_req_addr),
    .bark_req_data          (spectral_bark_req_data),
    .bark_req_ready         (spectral_bark_req_ready),
    
    // 状态输出
    .analysis_busy          (spectral_busy),
    .frame_done             (spectral_frame_done),
    .spectral_stats         (spectral_stats),
    .debug_info             (debug_spectral)
);

//=============================================================================
// 量化控制模块实例化
//=============================================================================

quantization_control u_quantization_control (
    .clk                    (clk),
    .rst_n                  (rst_n),
    
    // 配置接口
    .frame_duration         (frame_duration),
    .target_bitrate         (target_bitrate),
    .sample_rate            (sample_rate),
    .channel_mode           (channel_mode),
    
    // 频谱分析输入接口
    .spectral_valid         (quant_input_valid),
    .spectral_data          (quant_input_data[23:0]),
    .spectral_envelope      (quant_envelope[23:0]),
    .spectral_masking       (quant_masking[15:0]),
    .spectral_bandwidth     (8'hFF), // 满带宽
    .spectral_index         (quant_index),
    .spectral_frame_end     (quant_frame_done),
    .spectral_ready         (quant_input_ready),
    
    // 量化输出接口
    .quant_valid            (quant_output_valid),
    .quant_data             (quant_output_data),
    .quant_step             (quant_step),
    .quant_scale            (quant_scale),
    .quant_index            (/* unused */),
    .quant_frame_end        (/* unused */),
    .quant_ready            (quant_output_ready),
    
    // 存储器接口
    .mem_req_valid          (quant_mem_req_valid),
    .mem_req_addr           (quant_mem_req_addr),
    .mem_req_wdata          (quant_mem_req_wdata),
    .mem_req_wen            (quant_mem_req_wen),
    .mem_req_ready          (quant_mem_req_ready),
    .mem_req_rdata          (quant_mem_req_rdata),
    
    // 控制和状态信号
    .enable                 (encoder_enable && (current_pipeline_stage == STAGE_QUANTIZE)),
    .processing             (),
    .status_reg             (),
    .debug_info             (debug_quantization)
);

//=============================================================================
// 熵编码模块实例化
//=============================================================================

entropy_coding u_entropy_coding (
    .clk                    (clk),
    .rst_n                  (rst_n),
    
    // 配置接口
    .frame_duration         (frame_duration),
    .channel_mode           (channel_mode),
    .target_bitrate         (target_bitrate),
    .enable                 (encoder_enable && (current_pipeline_stage == STAGE_ENTROPY)),
    
    // 量化输入接口
    .quant_valid            (entropy_input_valid),
    .quantized_coeff        (entropy_input_data),
    .quantization_step      (entropy_quant_step),
    .scale_factor           (entropy_scale_factor),
    .coeff_index            (entropy_coeff_index),
    .quant_ready            (entropy_input_ready),
    
    // 编码输出接口
    .output_valid           (entropy_output_valid),
    .encoded_bits           (entropy_output_bits),
    .bit_count              (entropy_bit_count),
    .frame_end              (entropy_frame_end),
    .output_ready           (entropy_output_ready),
    
    // 存储器接口
    .mem_req_valid          (entropy_mem_req_valid),
    .mem_req_addr           (entropy_mem_req_addr),
    .mem_req_wdata          (entropy_mem_req_wdata),
    .mem_req_wen            (entropy_mem_req_wen),
    .mem_req_ready          (entropy_mem_req_ready),
    .mem_req_rdata          (entropy_mem_req_rdata),
    
    // 概率表ROM接口
    .prob_req_valid         (),
    .prob_req_addr          (),
    .prob_req_data          (32'h0),
    .prob_req_ready         (1'b1),
    
    // 状态输出
    .coding_busy            (),
    .frame_done             (),
    .bits_generated         (),
    .compression_ratio      (),
    .debug_info             (debug_entropy)
);

//=============================================================================
// 比特流打包模块实例化
//=============================================================================

bitstream_packing u_bitstream_packing (
    .clk                    (clk),
    .rst_n                  (rst_n),
    
    // 配置接口
    .frame_duration         (frame_duration),
    .channel_mode           (channel_mode),
    .target_bitrate         (target_bitrate),
    .sample_rate            (sample_rate),
    .enable                 (encoder_enable && (current_pipeline_stage == STAGE_PACKING)),
    
    // 熵编码输入接口
    .entropy_valid          (packing_input_valid),
    .entropy_bits           (packing_input_bits),
    .entropy_bit_count      (packing_bit_count),
    .entropy_frame_end      (packing_frame_end),
    .entropy_ready          (packing_input_ready),
    
    // 比特流输出接口
    .output_valid           (packing_output_valid),
    .output_byte            (packing_output_byte),
    .frame_start            (packing_frame_start),
    .frame_complete         (packing_frame_complete),
    .frame_size_bytes       (packing_frame_size),
    .output_ready           (packing_output_ready),
    
    // 存储器接口
    .mem_req_valid          (packing_mem_req_valid),
    .mem_req_addr           (packing_mem_req_addr),
    .mem_req_wdata          (packing_mem_req_wdata),
    .mem_req_wen            (packing_mem_req_wen),
    .mem_req_ready          (packing_mem_req_ready),
    .mem_req_rdata          (packing_mem_req_rdata),
    
    // 状态输出
    .packing_busy           (),
    .frame_done             (),
    .bytes_packed           (),
    .crc_value              (),
    .debug_info             (debug_packing)
);

//=============================================================================
// MDCT系数ROM简单处理 (简化版本)
//=============================================================================

// 简化的MDCT系数ROM响应 - 返回固定系数
assign mdct_coeff_req_ready = 1'b1;
assign mdct_coeff_req_data  = 32'h40000000; // 固定系数值 (1.0 in fixed point)

//=============================================================================
// 模块间连接逻辑
//=============================================================================

// MDCT到频谱分析连接
assign spectral_input_valid = mdct_output_valid;
assign spectral_input_data  = {mdct_output_real, mdct_output_imag}; // 组合实部和虚部
assign spectral_input_index = mdct_output_index;
assign mdct_output_ready    = spectral_input_ready;

// 频谱分析到量化控制连接
assign quant_input_valid = spectral_output_valid;
assign quant_input_data  = spectral_input_data[23:0];  // MDCT数据传递，取低24位
assign quant_envelope    = spectral_envelope[23:0];    // 转换为24位
assign quant_masking     = spectral_masking;
assign spectral_output_ready = quant_input_ready;

// 量化控制到熵编码连接
assign entropy_input_valid    = quant_output_valid;
assign entropy_input_data     = quant_output_data;
assign entropy_quant_step     = quant_step;
assign entropy_scale_factor   = quant_scale;
assign entropy_coeff_index    = quant_index;
assign quant_output_ready     = entropy_input_ready;

// 熵编码到比特流打包连接
assign packing_input_valid = entropy_output_valid;
assign packing_input_bits  = entropy_output_bits;
assign packing_bit_count   = entropy_bit_count;
assign packing_frame_end   = entropy_frame_end;
assign entropy_output_ready = packing_input_ready;

//=============================================================================
// 外部接口连接
//=============================================================================

// 音频输入接口
assign s_axis_audio_tready = mdct_input_ready && (current_pipeline_stage == STAGE_MDCT);

// 比特流输出接口
assign m_axis_bitstream_tvalid = packing_output_valid && (current_pipeline_stage == STAGE_OUTPUT);
assign m_axis_bitstream_tdata  = packing_output_byte;
assign m_axis_bitstream_tlast  = packing_frame_complete;
assign m_axis_bitstream_tuser  = packing_frame_size;
assign packing_output_ready    = m_axis_bitstream_tready && (current_pipeline_stage == STAGE_OUTPUT);

// 系统状态输出
assign encoding_active   = pipeline_active;
assign frame_processing  = (current_pipeline_stage != STAGE_IDLE);
assign pipeline_stage    = current_pipeline_stage;
assign performance_info  = perf_reg0;
assign error_status      = error_reg;

//=============================================================================
// 音频样本索引计数器
//=============================================================================

// 音频样本索引计数器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        audio_sample_index <= 10'b0;
    end else begin
        if (s_axis_audio_tvalid && s_axis_audio_tready) begin
            if (s_axis_audio_tlast) begin
                audio_sample_index <= 10'b0;  // 帧结束时重置
            end else begin
                audio_sample_index <= audio_sample_index + 1'b1;
            end
        end
    end
end

//=============================================================================
// 存储器仲裁器（简化版本）
//=============================================================================

// 存储器访问仲裁（轮询方式）
reg [2:0] mem_arbiter_state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_arbiter_state <= 3'b000;
    end else begin
        mem_arbiter_state <= mem_arbiter_state + 3'b001;
    end
end

// 存储器请求路由
always @(*) begin
    // 默认值
    mem_req_valid = 1'b0;
    mem_req_addr = 16'h0000;
    mem_req_wdata = 32'h0000_0000;
    mem_req_wen = 1'b0;
    
    // 清除所有ready信号
    mdct_mem_req_ready = 1'b0;
    spectral_mem_req_ready = 1'b0;
    quant_mem_req_ready = 1'b0;
    entropy_mem_req_ready = 1'b0;
    packing_mem_req_ready = 1'b0;
    
    // 简化的优先级仲裁
    if (mdct_mem_req_valid) begin
        mem_req_valid = mdct_mem_req_valid;
        mem_req_addr = {4'h0, mdct_mem_req_addr};
        mem_req_wdata = mdct_mem_req_wdata;
        mem_req_wen = mdct_mem_req_wen;
        mdct_mem_req_ready = mem_req_ready;
    end else if (spectral_mem_req_valid) begin
        mem_req_valid = spectral_mem_req_valid;
        mem_req_addr = {4'h2, spectral_mem_req_addr};
        mem_req_wdata = spectral_mem_req_wdata;
        mem_req_wen = spectral_mem_req_wen;
        spectral_mem_req_ready = mem_req_ready;
    end else if (quant_mem_req_valid) begin
        mem_req_valid = quant_mem_req_valid;
        mem_req_addr = {4'h4, quant_mem_req_addr};
        mem_req_wdata = quant_mem_req_wdata;
        mem_req_wen = quant_mem_req_wen;
        quant_mem_req_ready = mem_req_ready;
    end else if (entropy_mem_req_valid) begin
        mem_req_valid = entropy_mem_req_valid;
        mem_req_addr = {4'h8, entropy_mem_req_addr};
        mem_req_wdata = entropy_mem_req_wdata;
        mem_req_wen = entropy_mem_req_wen;
        entropy_mem_req_ready = mem_req_ready;
    end else if (packing_mem_req_valid) begin
        mem_req_valid = packing_mem_req_valid;
        mem_req_addr = {4'hA, packing_mem_req_addr};
        mem_req_wdata = packing_mem_req_wdata;
        mem_req_wen = packing_mem_req_wen;
        packing_mem_req_ready = mem_req_ready;
    end
end

// 存储器读数据分发
assign mdct_mem_req_rdata = mem_req_rdata;
assign spectral_mem_req_rdata = mem_req_rdata;
assign quant_mem_req_rdata = mem_req_rdata;
assign entropy_mem_req_rdata = mem_req_rdata;
assign packing_mem_req_rdata = mem_req_rdata;

//=============================================================================
// APB配置接口
//=============================================================================

// APB读写控制
reg [31:0] prdata_reg;
reg        pready_reg;

always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
        ctrl_reg <= 32'h0000_0001;     // 默认使能
        config_reg <= 32'hBB80_0040;   // 48kHz, 64kbps
        debug_reg <= 32'h0000_0000;
        prdata_reg <= 32'h0000_0000;
        pready_reg <= 1'b0;
    end else begin
        pready_reg <= psel && !pready_reg;
        
        if (psel && penable && pwrite) begin
            // APB写操作
            case (paddr)
                CTRL_REG_ADDR:   ctrl_reg <= pwdata;
                CONFIG_REG_ADDR: config_reg <= pwdata;
                DEBUG_REG_ADDR:  debug_reg <= pwdata;
                default: begin end
            endcase
        end else if (psel && penable && !pwrite) begin
            // APB读操作
            case (paddr)
                CTRL_REG_ADDR:    prdata_reg <= ctrl_reg;
                CONFIG_REG_ADDR:  prdata_reg <= config_reg;
                STATUS_REG_ADDR:  prdata_reg <= status_reg;
                ERROR_REG_ADDR:   prdata_reg <= error_reg;
                PERF_REG0_ADDR:   prdata_reg <= perf_reg0;
                PERF_REG1_ADDR:   prdata_reg <= perf_reg1;
                DEBUG_REG_ADDR:   prdata_reg <= debug_reg;
                VERSION_REG_ADDR: prdata_reg <= version_reg;
                default:          prdata_reg <= 32'h0000_0000;
            endcase
        end
    end
end

assign prdata = prdata_reg;
assign pready = pready_reg;
assign pslverr = 1'b0;

//=============================================================================
// 性能统计
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_count <= 32'h0000_0000;
        cycle_count <= 32'h0000_0000;
        error_count <= 32'h0000_0000;
        max_frame_cycles <= 32'h0000_0000;
        current_frame_cycles <= 32'h0000_0000;
        
        status_reg <= 32'h0000_0000;
        error_reg <= 32'h0000_0000;
        perf_reg0 <= 32'h0000_0000;
        perf_reg1 <= 32'h0000_0000;
    end else begin
        cycle_count <= cycle_count + 32'h0000_0001;
        
        // 帧计数
        if (frame_boundary && (current_pipeline_stage == STAGE_IDLE)) begin
            frame_count <= frame_count + 32'h0000_0001;
            
            // 更新最大帧处理时间
            if (current_frame_cycles > max_frame_cycles) begin
                max_frame_cycles <= current_frame_cycles;
            end
            current_frame_cycles <= 32'h0000_0000;
        end else if (pipeline_active) begin
            current_frame_cycles <= current_frame_cycles + 32'h0000_0001;
        end
        
        // 更新状态寄存器
        status_reg <= {frame_count[15:0], 13'h0000, current_pipeline_stage};
        
        // 更新性能寄存器
        perf_reg0 <= {frame_count[15:0], max_frame_cycles[15:0]};
        perf_reg1 <= {error_count[15:0], cycle_count[15:0]};
    end
end

endmodule 