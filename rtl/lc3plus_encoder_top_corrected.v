//============================================================================
// Module Name  : lc3plus_encoder_top.v  
// Description  : LC3plus音频编码器顶层模块 (完全修正版本)
//                包含硬件配置参数和正确的端口连接
// Author       : Audio Codec Design Team
// Date         : 2024-06-11
// Version      : v1.2
//============================================================================

`timescale 1ns / 1ps

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
    // 系统时钟和复位
    input                       clk,
    input                       rst_n,
    
    // LC3plus编码器配置
    input       [1:0]           frame_duration,     // 帧长: 00=2.5ms, 01=5ms, 10=10ms
    input                       channel_mode,       // 通道模式: 0=单声道, 1=立体声
    input       [7:0]           target_bitrate,     // 目标比特率 (kbps)
    input       [15:0]          sample_rate,        // 采样率 (Hz)
    input                       encoder_enable,     // 编码器使能
    
    // AXI4-Stream音频输入接口
    input                       s_axis_audio_tvalid,
    input       [31:0]          s_axis_audio_tdata,
    input                       s_axis_audio_tlast,
    output                      s_axis_audio_tready,
    
    // AXI4-Stream比特流输出接口
    output                      m_axis_bitstream_tvalid,
    output      [7:0]           m_axis_bitstream_tdata,
    output                      m_axis_bitstream_tlast,
    output      [15:0]          m_axis_bitstream_tuser,  // 帧大小
    input                       m_axis_bitstream_tready,
    
    // APB配置接口
    input                       pclk,
    input                       presetn,
    input                       psel,
    input                       penable,
    input                       pwrite,
    input       [11:0]          paddr,
    input       [31:0]          pwdata,
    output reg  [31:0]          prdata,
    output reg                  pready,
    output                      pslverr,
    
    // 系统存储器接口
    output reg                  mem_req_valid,
    output reg  [15:0]          mem_req_addr,
    output reg  [31:0]          mem_req_wdata,
    output reg                  mem_req_wen,
    input                       mem_req_ready,
    input       [31:0]          mem_req_rdata,
    
    // 状态和调试接口
    output                      encoding_active,
    output                      frame_processing,
    output      [2:0]           pipeline_stage,
    output      [31:0]          performance_info,
    output      [31:0]          error_status,
    output      [31:0]          debug_mdct,
    output      [31:0]          debug_spectral,
    output      [31:0]          debug_quantization,
    output      [31:0]          debug_entropy,
    output      [31:0]          debug_packing
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

//=============================================================================
// 信号声明
//=============================================================================

// 流水线控制信号
reg     [2:0]           current_pipeline_stage;
reg                     frame_boundary;
reg                     pipeline_active;

// 音频接口信号
wire    [9:0]           audio_sample_index;
reg     [9:0]           sample_counter;

// MDCT变换模块接口信号
wire                    mdct_input_ready;
wire                    mdct_output_valid;
wire    [15:0]          mdct_output_real;
wire    [15:0]          mdct_output_imag;
wire    [9:0]           mdct_output_index;
wire                    mdct_output_ready;
wire                    mdct_busy;
wire                    mdct_frame_done;

// 频谱分析模块接口信号
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

// 量化控制模块接口信号  
wire                    quant_spectral_valid;
wire    [23:0]          quant_spectral_data;
wire    [23:0]          quant_spectral_envelope;
wire    [15:0]          quant_spectral_masking;
wire    [7:0]           quant_spectral_bandwidth;
wire    [9:0]           quant_spectral_index;
wire                    quant_spectral_frame_end;
wire                    quant_spectral_ready;
wire                    quant_output_valid;
wire    [15:0]          quant_output_data;
wire    [7:0]           quant_step;
wire    [3:0]           quant_scale;
wire    [9:0]           quant_index;
wire                    quant_frame_end;
wire                    quant_output_ready;
wire                    quant_processing;
wire    [31:0]          quant_status;

// 存储器仲裁信号
wire                    mdct_mem_req_valid;
wire    [11:0]          mdct_mem_req_addr;
wire    [31:0]          mdct_mem_req_wdata;
wire                    mdct_mem_req_wen;
wire                    mdct_mem_req_ready;
wire    [31:0]          mdct_mem_req_rdata;

wire                    spectral_mem_req_valid;
wire    [11:0]          spectral_mem_req_addr;
wire    [31:0]          spectral_mem_req_wdata;
wire                    spectral_mem_req_wen;
wire                    spectral_mem_req_ready;
wire    [31:0]          spectral_mem_req_rdata;

wire                    quant_mem_req_valid;
wire    [11:0]          quant_mem_req_addr;
wire    [31:0]          quant_mem_req_wdata;
wire                    quant_mem_req_wen;
wire                    quant_mem_req_ready;
wire    [31:0]          quant_mem_req_rdata;

// APB配置寄存器
reg     [31:0]          ctrl_reg;
reg     [31:0]          config_reg;
reg     [31:0]          status_reg;
reg     [31:0]          error_reg;

//=============================================================================
// 硬件配置参数应用
//=============================================================================

// 根据配置参数设置内部参数
assign spectral_bandwidth_config = (MAX_SAMPLE_RATE == 96000) ? 5'b11111 : 5'b10111;

//=============================================================================
// 样本计数器
//=============================================================================

assign audio_sample_index = sample_counter;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sample_counter <= 10'h0;
    end else if (s_axis_audio_tvalid && s_axis_audio_tready) begin
        if (s_axis_audio_tlast) begin
            sample_counter <= 10'h0;
        end else begin
            sample_counter <= sample_counter + 1'b1;
        end
    end
end

//=============================================================================
// AXI4-Stream音频输入控制
//=============================================================================

assign s_axis_audio_tready = mdct_input_ready && encoder_enable;

//=============================================================================
// 流水线数据传输
//=============================================================================

// MDCT到频谱分析
assign spectral_input_valid = mdct_output_valid;
assign spectral_input_real = mdct_output_real;
assign spectral_input_imag = mdct_output_imag;
assign spectral_input_index = mdct_output_index;
assign mdct_output_ready = spectral_input_ready;

// 频谱分析到量化控制
assign quant_spectral_valid = spectral_output_valid;
assign quant_spectral_data = {8'h0, spectral_envelope}; // 扩展到24位
assign quant_spectral_envelope = {8'h0, spectral_envelope};
assign quant_spectral_masking = spectral_masking;
assign quant_spectral_bandwidth = 8'd64; // 简化设置
assign quant_spectral_index = spectral_band_index;
assign quant_spectral_frame_end = spectral_frame_done;
assign spectral_output_ready = quant_spectral_ready;

//=============================================================================
// 流水线控制
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_pipeline_stage <= STAGE_IDLE;
        pipeline_active <= 1'b0;
        frame_boundary <= 1'b0;
    end else begin
        frame_boundary <= 1'b0;
        
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
                if (quant_frame_end) begin
                    current_pipeline_stage <= STAGE_IDLE;
                    pipeline_active <= 1'b0;
                end
            end
            
            default: begin
                current_pipeline_stage <= STAGE_IDLE;
                pipeline_active <= 1'b0;
            end
        endcase
    end
end

//=============================================================================
// 存储器仲裁 (简化版本)
//=============================================================================

// 简单的优先级仲裁
always @(*) begin
    if (mdct_mem_req_valid) begin
        mem_req_valid = mdct_mem_req_valid;
        mem_req_addr = {4'h0, mdct_mem_req_addr};
        mem_req_wdata = mdct_mem_req_wdata;
        mem_req_wen = mdct_mem_req_wen;
    end else if (spectral_mem_req_valid) begin
        mem_req_valid = spectral_mem_req_valid;
        mem_req_addr = {4'h1, spectral_mem_req_addr};
        mem_req_wdata = spectral_mem_req_wdata;
        mem_req_wen = spectral_mem_req_wen;
    end else if (quant_mem_req_valid) begin
        mem_req_valid = quant_mem_req_valid;
        mem_req_addr = {4'h2, quant_mem_req_addr};
        mem_req_wdata = quant_mem_req_wdata;
        mem_req_wen = quant_mem_req_wen;
    end else begin
        mem_req_valid = 1'b0;
        mem_req_addr = 16'h0;
        mem_req_wdata = 32'h0;
        mem_req_wen = 1'b0;
    end
end

assign mdct_mem_req_ready = mdct_mem_req_valid ? mem_req_ready : 1'b0;
assign spectral_mem_req_ready = spectral_mem_req_valid ? mem_req_ready : 1'b0;
assign quant_mem_req_ready = quant_mem_req_valid ? mem_req_ready : 1'b0;

assign mdct_mem_req_rdata = mem_req_rdata;
assign spectral_mem_req_rdata = mem_req_rdata;
assign quant_mem_req_rdata = mem_req_rdata;

//=============================================================================
// APB接口实现
//=============================================================================

always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
        prdata <= 32'h0;
        pready <= 1'b0;
        ctrl_reg <= 32'h0;
        config_reg <= 32'h0;
        status_reg <= 32'h0;
        error_reg <= 32'h0;
    end else begin
        pready <= psel && !pready;
        
        if (psel && penable && pwrite && pready) begin
            case (paddr)
                12'h000: ctrl_reg <= pwdata;
                12'h004: config_reg <= pwdata;
                12'h00C: error_reg <= pwdata;
                default: ;
            endcase
        end
        
        if (psel && penable && !pwrite && pready) begin
            case (paddr)
                12'h000: prdata <= ctrl_reg;
                12'h004: prdata <= config_reg;
                12'h008: prdata <= status_reg;
                12'h00C: prdata <= error_reg;
                12'h01C: prdata <= 32'h01010000; // 版本信息
                default: prdata <= 32'h0;
            endcase
        end
    end
end

assign pslverr = 1'b0;

//=============================================================================
// 状态输出
//=============================================================================

assign encoding_active = pipeline_active;
assign frame_processing = (current_pipeline_stage != STAGE_IDLE);
assign pipeline_stage = current_pipeline_stage;
assign performance_info = {16'h0, sample_counter, 6'h0};
assign error_status = error_reg;

//=============================================================================
// 简化的输出接口
//=============================================================================

assign m_axis_bitstream_tvalid = quant_output_valid;
assign m_axis_bitstream_tdata = quant_output_data[7:0];
assign m_axis_bitstream_tlast = quant_frame_end;
assign m_axis_bitstream_tuser = 16'd64; // 简化的帧大小
assign quant_output_ready = m_axis_bitstream_tready;

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
    
    // 输入数据接口
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
    .coeff_req_valid        (),
    .coeff_req_addr         (),
    .coeff_req_data         (32'h40000000),
    .coeff_req_ready        (1'b1),
    
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
    
    // 输入数据接口
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
    .bark_req_valid         (),
    .bark_req_addr          (),
    .bark_req_data          (32'h20000000),
    .bark_req_ready         (1'b1),
    
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
    
    // 配置信号
    .frame_duration         (frame_duration),
    .target_bitrate         (target_bitrate),
    .sample_rate            (sample_rate),
    .channel_mode           (channel_mode),
    
    // 频谱分析输入接口
    .spectral_valid         (quant_spectral_valid),
    .spectral_data          (quant_spectral_data),
    .spectral_envelope      (quant_spectral_envelope),
    .spectral_masking       (quant_spectral_masking),
    .spectral_bandwidth     (quant_spectral_bandwidth),
    .spectral_index         (quant_spectral_index),
    .spectral_frame_end     (quant_spectral_frame_end),
    .spectral_ready         (quant_spectral_ready),
    
    // 量化输出接口
    .quant_valid            (quant_output_valid),
    .quant_data             (quant_output_data),
    .quant_step             (quant_step),
    .quant_scale            (quant_scale),
    .quant_index            (quant_index),
    .quant_frame_end        (quant_frame_end),
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
    .processing             (quant_processing),
    .status_reg             (quant_status),
    .debug_info             (debug_quantization)
);

//=============================================================================
// 简化的其他模块输出
//=============================================================================

assign debug_entropy = 32'h0;
assign debug_packing = 32'h0;

endmodule 