//============================================================================
// Module Name  : lc3plus_encoder_top.v
// Description  : LC3plus音频编码器顶层模块 (完整修复版本)
//                包含硬件配置参数和正确的端口连接
// Author       : Audio Codec Design Team
// Date         : 2024-06-11
// Version      : v1.1
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
    output      [31:0]          prdata,
    output                      pready,
    output                      pslverr,
    
    // 系统存储器接口
    output                      mem_req_valid,
    output      [15:0]          mem_req_addr,
    output      [31:0]          mem_req_wdata,
    output                      mem_req_wen,
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

// APB寄存器地址
localparam CTRL_REG_ADDR    = 12'h000;  // 控制寄存器
localparam CONFIG_REG_ADDR  = 12'h004;  // 配置寄存器
localparam STATUS_REG_ADDR  = 12'h008;  // 状态寄存器
localparam ERROR_REG_ADDR   = 12'h00C;  // 错误寄存器

// 版本信息
localparam VERSION_MAJOR = 8'h01;
localparam VERSION_MINOR = 8'h01;
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
wire    [31:0]          version_reg;

// 音频接口信号
wire    [9:0]           audio_sample_index;
reg     [9:0]           sample_counter;

// MDCT变换模块接口
wire                    mdct_input_ready;
wire                    mdct_output_valid;
wire    [15:0]          mdct_output_real;
wire    [15:0]          mdct_output_imag;
wire    [9:0]           mdct_output_index;
wire                    mdct_output_ready;
wire                    mdct_busy;
wire                    mdct_frame_done;
wire                    mdct_coeff_req_valid;
wire    [13:0]          mdct_coeff_req_addr;
wire    [31:0]          mdct_coeff_req_data;
wire                    mdct_coeff_req_ready;

// 频谱分析模块接口
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
wire                    spectral_bark_req_valid;
wire    [7:0]           spectral_bark_req_addr;
wire    [31:0]          spectral_bark_req_data;
wire                    spectral_bark_req_ready;

// 量化控制模块接口
wire                    quant_input_valid;
wire    [15:0]          quant_input_real;
wire    [15:0]          quant_input_imag;
wire    [15:0]          quant_envelope;
wire    [15:0]          quant_masking;
wire                    quant_input_ready;
wire                    quant_output_valid;
wire    [15:0]          quant_output_data;
wire    [7:0]           quant_step;
wire    [3:0]           quant_scale;
wire    [9:0]           quant_index;
wire                    quant_frame_done;
wire                    quant_output_ready;

// 熵编码模块接口
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

// 比特流打包模块接口
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

wire                    entropy_mem_req_valid;
wire    [11:0]          entropy_mem_req_addr;
wire    [31:0]          entropy_mem_req_wdata;
wire                    entropy_mem_req_wen;
wire                    entropy_mem_req_ready;
wire    [31:0]          entropy_mem_req_rdata;

wire                    packing_mem_req_valid;
wire    [11:0]          packing_mem_req_addr;
wire    [31:0]          packing_mem_req_wdata;
wire                    packing_mem_req_wen;
wire                    packing_mem_req_ready;
wire    [31:0]          packing_mem_req_rdata;

//=============================================================================
// 硬件配置参数应用
//=============================================================================

// 根据配置参数设置内部参数
assign spectral_bandwidth_config = (MAX_SAMPLE_RATE == 96000) ? 5'b11111 : 5'b10111;

//=============================================================================
// 版本寄存器
//=============================================================================

assign version_reg = {VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH};

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
assign quant_input_valid = spectral_output_valid;
assign quant_input_real = spectral_envelope; // 简化连接
assign quant_input_imag = 16'h0;
assign quant_envelope = spectral_envelope;
assign quant_masking = spectral_masking;
assign spectral_output_ready = quant_input_ready;

// 量化控制到熵编码
assign entropy_input_valid = quant_output_valid;
assign entropy_input_data = quant_output_data;
assign entropy_quant_step = quant_step;
assign entropy_scale_factor = quant_scale;
assign entropy_coeff_index = quant_index;
assign quant_output_ready = entropy_input_ready;

// 熵编码到比特流打包
assign packing_input_valid = entropy_output_valid;
assign packing_input_bits = entropy_output_bits;
assign packing_bit_count = entropy_bit_count;
assign packing_frame_end = entropy_frame_end;
assign entropy_output_ready = packing_input_ready;

//=============================================================================
// AXI4-Stream比特流输出
//=============================================================================

assign m_axis_bitstream_tvalid = packing_output_valid;
assign m_axis_bitstream_tdata = packing_output_byte;
assign m_axis_bitstream_tlast = packing_frame_complete;
assign m_axis_bitstream_tuser = packing_frame_size;
assign packing_output_ready = m_axis_bitstream_tready;

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
assign mem_req_valid = mdct_mem_req_valid | spectral_mem_req_valid | 
                      quant_mem_req_valid | entropy_mem_req_valid | 
                      packing_mem_req_valid;

assign mem_req_addr = mdct_mem_req_valid ? {4'h0, mdct_mem_req_addr} :
                     spectral_mem_req_valid ? {4'h1, spectral_mem_req_addr} :
                     quant_mem_req_valid ? {4'h2, quant_mem_req_addr} :
                     entropy_mem_req_valid ? {4'h3, entropy_mem_req_addr} :
                     packing_mem_req_valid ? {4'h4, packing_mem_req_addr} : 16'h0;

assign mem_req_wdata = mdct_mem_req_valid ? mdct_mem_req_wdata :
                      spectral_mem_req_valid ? spectral_mem_req_wdata :
                      quant_mem_req_valid ? quant_mem_req_wdata :
                      entropy_mem_req_valid ? entropy_mem_req_wdata :
                      packing_mem_req_wdata;

assign mem_req_wen = mdct_mem_req_valid ? mdct_mem_req_wen :
                    spectral_mem_req_valid ? spectral_mem_req_wen :
                    quant_mem_req_valid ? quant_mem_req_wen :
                    entropy_mem_req_valid ? entropy_mem_req_wen :
                    packing_mem_req_wen;

assign mdct_mem_req_ready = mdct_mem_req_valid ? mem_req_ready : 1'b0;
assign spectral_mem_req_ready = spectral_mem_req_valid ? mem_req_ready : 1'b0;
assign quant_mem_req_ready = quant_mem_req_valid ? mem_req_ready : 1'b0;
assign entropy_mem_req_ready = entropy_mem_req_valid ? mem_req_ready : 1'b0;
assign packing_mem_req_ready = packing_mem_req_valid ? mem_req_ready : 1'b0;

assign mdct_mem_req_rdata = mem_req_rdata;
assign spectral_mem_req_rdata = mem_req_rdata;
assign quant_mem_req_rdata = mem_req_rdata;
assign entropy_mem_req_rdata = mem_req_rdata;
assign packing_mem_req_rdata = mem_req_rdata;

//=============================================================================
// 系数ROM接口 (简化实现)
//=============================================================================

assign mdct_coeff_req_data = 32'h40000000; // 简化的系数数据
assign mdct_coeff_req_ready = 1'b1;

assign spectral_bark_req_data = 32'h20000000; // 简化的Bark系数
assign spectral_bark_req_ready = 1'b1;

//=============================================================================
// APB接口实现
//=============================================================================

reg [31:0] prdata_reg;
reg pready_reg;

always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
        prdata_reg <= 32'h0;
        pready_reg <= 1'b0;
        ctrl_reg <= 32'h0;
        config_reg <= 32'h0;
        status_reg <= 32'h0;
        error_reg <= 32'h0;
    end else begin
        pready_reg <= psel && !pready_reg;
        
        if (psel && penable && pwrite && pready_reg) begin
            case (paddr)
                CTRL_REG_ADDR: ctrl_reg <= pwdata;
                CONFIG_REG_ADDR: config_reg <= pwdata;
                ERROR_REG_ADDR: error_reg <= pwdata;
                default: ;
            endcase
        end
        
        if (psel && penable && !pwrite && pready_reg) begin
            case (paddr)
                CTRL_REG_ADDR: prdata_reg <= ctrl_reg;
                CONFIG_REG_ADDR: prdata_reg <= config_reg;
                STATUS_REG_ADDR: prdata_reg <= status_reg;
                ERROR_REG_ADDR: prdata_reg <= error_reg;
                12'h01C: prdata_reg <= version_reg;
                default: prdata_reg <= 32'h0;
            endcase
        end
    end
end

assign prdata = prdata_reg;
assign pready = pready_reg;
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
// 简化的其他模块实例化 (占位实现)
//=============================================================================

// 量化控制模块
assign quant_input_ready = 1'b1;
assign quant_output_valid = quant_input_valid;
assign quant_output_data = quant_input_real;
assign quant_step = 8'h10;
assign quant_scale = 4'h2;
assign quant_index = 10'h0;
assign quant_frame_done = spectral_frame_done;
assign debug_quantization = 32'h0;

// 熵编码模块
assign entropy_input_ready = 1'b1;
assign entropy_output_valid = entropy_input_valid;
assign entropy_output_bits = {16'h0, entropy_input_data};
assign entropy_bit_count = 6'd16;
assign entropy_frame_end = quant_frame_done;
assign debug_entropy = 32'h0;

// 比特流打包模块
assign packing_input_ready = 1'b1;
assign packing_output_valid = packing_input_valid;
assign packing_output_byte = packing_input_bits[7:0];
assign packing_frame_start = 1'b0;
assign packing_frame_complete = packing_frame_end;
assign packing_frame_size = 16'd64;
assign debug_packing = 32'h0;

endmodule 