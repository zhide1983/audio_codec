//============================================================================
// Module Name  : audio_codec_top.v
// Description  : 音频编解码器顶层模块 v3.0
//                支持顶层硬化配置，符合RTL设计规则
// Author       : Audio Codec Design Team  
// Date         : 2024-06-11
// Version      : v3.0 - 增加硬化配置和设计约束
//============================================================================

`timescale 1ns / 1ps

//============================================================================
// 顶层硬化配置 - 编译时确定
//============================================================================
`define MAX_SAMPLE_RATE_48K     // 支持最高48kHz采样率
//`define MAX_SAMPLE_RATE_96K   // 支持最高96kHz采样率 (可选)

`define SUPPORT_16BIT           // 支持16bit采样
//`define SUPPORT_24BIT         // 支持24bit采样 (可选)

//============================================================================
// 根据硬化配置生成参数
//============================================================================
`ifdef MAX_SAMPLE_RATE_96K
    `define MAX_SAMPLE_RATE 96000
    `define MDCT_MAX_LENGTH 1920  // 96kHz@20ms最大长度
    `define MAX_FRAME_SAMPLES 2400
`else
    `define MAX_SAMPLE_RATE 48000
    `define MDCT_MAX_LENGTH 960   // 48kHz@20ms最大长度  
    `define MAX_FRAME_SAMPLES 1200
`endif

`ifdef SUPPORT_24BIT
    `define MAX_SAMPLE_WIDTH 24
    `define INTERNAL_WIDTH 32     // 内部处理位宽
`else
    `define MAX_SAMPLE_WIDTH 16
    `define INTERNAL_WIDTH 24     // 内部处理位宽
`endif

//============================================================================
// 总线接口选择 - 编译时配置
//============================================================================
`define USE_AXI4_INTERFACE      // 使用AXI4接口
//`define USE_AHB_INTERFACE     // 使用AHB接口 (二选一)

module audio_codec_top (
    // 系统信号
    input                           clk,
    input                           rst_n,
    
    // APB从接口 - 寄存器配置
    input                           pclk,
    input                           presetn,
    input                           psel,
    input                           penable,
    input                           pwrite,
    input       [15:0]              paddr,
    input       [31:0]              pwdata,
    output      [31:0]              prdata,
    output                          pready,
    output                          pslverr,
    
`ifdef USE_AXI4_INTERFACE
    // AXI4主接口 - 存储器访问
    output      [3:0]               m_axi_awid,
    output      [31:0]              m_axi_awaddr,
    output      [7:0]               m_axi_awlen,
    output      [2:0]               m_axi_awsize,
    output      [1:0]               m_axi_awburst,
    output                          m_axi_awlock,
    output      [3:0]               m_axi_awcache,
    output      [2:0]               m_axi_awprot,
    output                          m_axi_awvalid,
    input                           m_axi_awready,
    
    output      [31:0]              m_axi_wdata,
    output      [3:0]               m_axi_wstrb,
    output                          m_axi_wlast,
    output                          m_axi_wvalid,
    input                           m_axi_wready,
    
    input       [3:0]               m_axi_bid,
    input       [1:0]               m_axi_bresp,
    input                           m_axi_bvalid,
    output                          m_axi_bready,
    
    output      [3:0]               m_axi_arid,
    output      [31:0]              m_axi_araddr,
    output      [7:0]               m_axi_arlen,
    output      [2:0]               m_axi_arsize,
    output      [1:0]               m_axi_arburst,
    output                          m_axi_arlock,
    output      [3:0]               m_axi_arcache,
    output      [2:0]               m_axi_arprot,
    output                          m_axi_arvalid,
    input                           m_axi_arready,
    
    input       [3:0]               m_axi_rid,
    input       [31:0]              m_axi_rdata,
    input       [1:0]               m_axi_rresp,
    input                           m_axi_rlast,
    input                           m_axi_rvalid,
    output                          m_axi_rready,
`endif

`ifdef USE_AHB_INTERFACE
    // AHB主接口 - 存储器访问
    output      [31:0]              haddr,
    output      [2:0]               hburst,
    output                          hmastlock,
    output      [3:0]               hprot,
    output      [2:0]               hsize,
    output      [1:0]               htrans,
    output      [31:0]              hwdata,
    output                          hwrite,
    input       [31:0]              hrdata,
    input                           hready,
    input       [1:0]               hresp,
`endif
    
    // 中断输出
    output                          irq
);

//============================================================================
// 参数定义 - 基于硬化配置
//============================================================================
parameter MAX_SAMPLE_RATE = `MAX_SAMPLE_RATE;
parameter MAX_SAMPLE_WIDTH = `MAX_SAMPLE_WIDTH;
parameter INTERNAL_WIDTH = `INTERNAL_WIDTH;
parameter MAX_FRAME_SAMPLES = `MAX_FRAME_SAMPLES;
parameter MDCT_MAX_LENGTH = `MDCT_MAX_LENGTH;

// 编解码器类型
parameter CODEC_LC3PLUS = 2'b00;
parameter CODEC_LC3     = 2'b01;
parameter CODEC_OPUS    = 2'b10;

// 帧时长配置
parameter FRAME_2P5MS = 2'b00;
parameter FRAME_5MS   = 2'b01; 
parameter FRAME_10MS  = 2'b10;

// 通道配置
parameter MONO_MODE   = 1'b0;
parameter STEREO_MODE = 1'b1;

//============================================================================
// 内部信号定义
//============================================================================
// APB寄存器接口
wire [31:0] reg_version;
wire [31:0] reg_feature_flags;
wire [31:0] reg_control;
wire [31:0] reg_status;
wire [31:0] reg_lc3plus_config;
wire [31:0] reg_bandwidth_config;
wire [31:0] reg_error_protection;
wire [31:0] reg_interrupt_enable;
wire [31:0] reg_interrupt_status;

// 配置信号解析
wire        codec_enable;
wire        mode_select;         // 0=编码器, 1=解码器
wire        soft_reset;

wire [1:0]  frame_duration;      // 帧时长配置
wire        channel_config;      // 0=单声道, 1=立体声
wire [4:0]  sample_rate_sel;     // 采样率选择
wire [1:0]  sample_width_sel;    // 采样位宽选择
wire [7:0]  bit_rate_config;     // 比特率配置

// 存储器接口 - 单端口SRAM
wire [11:0] audio_mem_addr;
wire [31:0] audio_mem_wdata;
wire        audio_mem_wen;
wire        audio_mem_ren;
wire [31:0] audio_mem_rdata;

wire [11:0] work_mem_addr;
wire [31:0] work_mem_wdata;
wire        work_mem_wen;
wire        work_mem_ren;
wire [31:0] work_mem_rdata;

wire [13:0] coeff_mem_addr;
wire [31:0] coeff_mem_rdata;
wire        coeff_mem_ren;

// 处理模块间接口
wire        time_domain_valid;
wire        time_domain_ready;
wire [`INTERNAL_WIDTH-1:0] time_domain_data;

wire        mdct_valid;
wire        mdct_ready;
wire [31:0] mdct_data_real;
wire [31:0] mdct_data_imag;

wire        spectral_valid;
wire        spectral_ready;
wire [31:0] spectral_data;

wire        quant_valid;
wire        quant_ready;
wire [15:0] quant_data;

wire        entropy_valid;
wire        entropy_ready;
wire [7:0]  entropy_data;

// 中断信号
wire        frame_done_irq;
wire        error_irq;
wire        buffer_full_irq;

//============================================================================
// 配置信号解析
//============================================================================
assign codec_enable     = reg_control[0];
assign mode_select      = reg_control[1];
assign soft_reset       = reg_control[2];

assign frame_duration   = reg_lc3plus_config[1:0];
assign channel_config   = reg_lc3plus_config[2];
assign sample_rate_sel  = reg_lc3plus_config[7:3];
assign sample_width_sel = reg_lc3plus_config[9:8];
assign bit_rate_config  = reg_lc3plus_config[17:10];

//============================================================================
// 特性标志寄存器 - 硬化配置反映
//============================================================================
assign reg_feature_flags = {
    24'h000000,                    // [31:8] 保留
    4'b0001,                       // [7:4] 编解码器支持: LC3plus
    `ifdef SUPPORT_24BIT
    2'b01,                         // [3:2] 最大采样位宽: 24bit
    `else
    2'b00,                         // [3:2] 最大采样位宽: 16bit
    `endif
    `ifdef MAX_SAMPLE_RATE_96K
    2'b01                          // [1:0] 最大采样率: 96kHz
    `else
    2'b00                          // [1:0] 最大采样率: 48kHz
    `endif
};

//============================================================================
// APB寄存器接口模块
//============================================================================
apb_registers #(
    .MAX_SAMPLE_RATE(MAX_SAMPLE_RATE),
    .MAX_SAMPLE_WIDTH(MAX_SAMPLE_WIDTH)
) u_apb_registers (
    .pclk                   (pclk),
    .presetn                (presetn),
    .psel                   (psel),
    .penable                (penable),
    .pwrite                 (pwrite),
    .paddr                  (paddr),
    .pwdata                 (pwdata),
    .prdata                 (prdata),
    .pready                 (pready),
    .pslverr                (pslverr),
    
    // 寄存器输出
    .reg_version            (reg_version),
    .reg_feature_flags      (reg_feature_flags),
    .reg_control            (reg_control),
    .reg_status             (reg_status),
    .reg_lc3plus_config     (reg_lc3plus_config),
    .reg_bandwidth_config   (reg_bandwidth_config),
    .reg_error_protection   (reg_error_protection),
    .reg_interrupt_enable   (reg_interrupt_enable),
    .reg_interrupt_status   (reg_interrupt_status),
    
    // 状态输入
    .frame_done_irq         (frame_done_irq),
    .error_irq              (error_irq),
    .buffer_full_irq        (buffer_full_irq)
);

//============================================================================
// 存储器子系统
//============================================================================
// 音频缓冲器 - 单端口SRAM + 仲裁器
audio_buffer_ram u_audio_buffer (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .addr                   (audio_mem_addr),
    .wdata                  (audio_mem_wdata),
    .wen                    (audio_mem_wen),
    .ren                    (audio_mem_ren),
    .rdata                  (audio_mem_rdata)
);

// 工作缓冲器 - 单端口SRAM + 仲裁器  
work_buffer_ram u_work_buffer (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .addr                   (work_mem_addr),
    .wdata                  (work_mem_wdata),
    .wen                    (work_mem_wen),
    .ren                    (work_mem_ren),
    .rdata                  (work_mem_rdata)
);

// 系数存储器 - ROM
coeff_storage_rom u_coeff_storage (
    .clk                    (clk),
    .addr                   (coeff_mem_addr),
    .ren                    (coeff_mem_ren),
    .rdata                  (coeff_mem_rdata)
);

//============================================================================
// LC3plus编码器处理模块
//============================================================================
generate
    if (1) begin : gen_encoder
        // 时域预处理模块
        time_domain_proc #(
            .SAMPLE_WIDTH(MAX_SAMPLE_WIDTH),
            .INTERNAL_WIDTH(INTERNAL_WIDTH)
        ) u_time_domain_proc (
            .clk                (clk),
            .rst_n              (rst_n),
            .enable             (codec_enable & ~mode_select),
            
            // 配置
            .frame_duration     (frame_duration),
            .channel_config     (channel_config),
            .sample_rate_sel    (sample_rate_sel),
            
            // 存储器接口 (通过仲裁器)
            .mem_req_valid      (/* 连接到仲裁器 */),
            .mem_req_addr       (/* 连接到仲裁器 */),
            .mem_req_wdata      (/* 连接到仲裁器 */),
            .mem_req_wen        (/* 连接到仲裁器 */),
            .mem_req_ready      (/* 来自仲裁器 */),
            .mem_req_rdata      (/* 来自仲裁器 */),
            
            // 输出到下一阶段
            .output_valid       (time_domain_valid),
            .output_ready       (time_domain_ready),
            .output_data        (time_domain_data)
        );
        
        // MDCT变换模块 (待实现)
        // 频谱分析模块 (待实现)  
        // 量化控制模块 (待实现)
        // 熵编码模块 (待实现)
        // 比特流打包模块 (待实现)
    end
endgenerate

//============================================================================
// 存储器仲裁器 - 管理单端口SRAM访问
//============================================================================
// 音频缓冲器仲裁器
audio_buffer_arbiter u_audio_arbiter (
    .clk                    (clk),
    .rst_n                  (rst_n),
    
    // 编码器访问
    .enc_req_valid          (/* 来自编码器模块 */),
    .enc_req_addr           (/* 来自编码器模块 */),
    .enc_req_wdata          (/* 来自编码器模块 */),
    .enc_req_wen            (/* 来自编码器模块 */),
    .enc_req_ready          (/* 到编码器模块 */),
    .enc_req_rdata          (/* 到编码器模块 */),
    
    // 解码器访问
    .dec_req_valid          (/* 来自解码器模块 */),
    .dec_req_addr           (/* 来自解码器模块 */),
    .dec_req_wdata          (/* 来自解码器模块 */),
    .dec_req_wen            (/* 来自解码器模块 */),
    .dec_req_ready          (/* 到解码器模块 */),
    .dec_req_rdata          (/* 到解码器模块 */),
    
    // 单端口存储器
    .mem_addr               (audio_mem_addr),
    .mem_wdata              (audio_mem_wdata),
    .mem_wen                (audio_mem_wen),
    .mem_ren                (audio_mem_ren),
    .mem_rdata              (audio_mem_rdata)
);

// 工作缓冲器仲裁器
work_buffer_arbiter u_work_arbiter (
    .clk                    (clk),
    .rst_n                  (rst_n),
    
    // MDCT模块访问
    .mdct_req_valid         (/* 来自MDCT模块 */),
    .mdct_req_addr          (/* 来自MDCT模块 */),
    .mdct_req_wdata         (/* 来自MDCT模块 */),
    .mdct_req_wen           (/* 来自MDCT模块 */),
    .mdct_req_ready         (/* 到MDCT模块 */),
    .mdct_req_rdata         (/* 到MDCT模块 */),
    
    // 频谱分析模块访问
    .spec_req_valid         (/* 来自频谱分析模块 */),
    .spec_req_addr          (/* 来自频谱分析模块 */),
    .spec_req_wdata         (/* 来自频谱分析模块 */),
    .spec_req_wen           (/* 来自频谱分析模块 */),
    .spec_req_ready         (/* 到频谱分析模块 */),
    .spec_req_rdata         (/* 到频谱分析模块 */),
    
    // 量化模块访问
    .quant_req_valid        (/* 来自量化模块 */),
    .quant_req_addr         (/* 来自量化模块 */),
    .quant_req_wdata        (/* 来自量化模块 */),
    .quant_req_wen          (/* 来自量化模块 */),
    .quant_req_ready        (/* 到量化模块 */),
    .quant_req_rdata        (/* 到量化模块 */),
    
    // 熵编码模块访问
    .entropy_req_valid      (/* 来自熵编码模块 */),
    .entropy_req_addr       (/* 来自熵编码模块 */),
    .entropy_req_wdata      (/* 来自熵编码模块 */),
    .entropy_req_wen        (/* 来自熵编码模块 */),
    .entropy_req_ready      (/* 到熵编码模块 */),
    .entropy_req_rdata      (/* 到熵编码模块 */),
    
    // 单端口存储器
    .mem_addr               (work_mem_addr),
    .mem_wdata              (work_mem_wdata),
    .mem_wen                (work_mem_wen),
    .mem_ren                (work_mem_ren),
    .mem_rdata              (work_mem_rdata)
);

//============================================================================
// 中断管理
//============================================================================
assign irq = (reg_interrupt_enable[0] & frame_done_irq) |
             (reg_interrupt_enable[1] & error_irq) |
             (reg_interrupt_enable[2] & buffer_full_irq);

//============================================================================
// 状态管理  
//============================================================================
assign reg_status = {
    28'h0000000,                   // [31:4] 保留
    buffer_full_irq,               // [3] 缓冲器满
    time_domain_valid,             // [2] 帧处理中
    error_irq,                     // [1] 错误状态
    ~time_domain_valid             // [0] 就绪状态
};

//============================================================================
// 总线接口模块 (根据硬化配置选择)
//============================================================================
`ifdef USE_AXI4_INTERFACE
    // AXI4主接口实现
    axi4_master_interface u_axi4_master (
        .clk                (clk),
        .rst_n              (rst_n),
        
        // 内部请求接口
        .req_valid          (/* 内部请求 */),
        .req_addr           (/* 内部地址 */),
        .req_data           (/* 内部数据 */),
        .req_write          (/* 读写控制 */),
        .req_ready          (/* 就绪信号 */),
        .resp_data          (/* 响应数据 */),
        .resp_valid         (/* 响应有效 */),
        
        // AXI4外部接口
        .m_axi_awid         (m_axi_awid),
        .m_axi_awaddr       (m_axi_awaddr),
        .m_axi_awlen        (m_axi_awlen),
        .m_axi_awsize       (m_axi_awsize),
        .m_axi_awburst      (m_axi_awburst),
        .m_axi_awlock       (m_axi_awlock),
        .m_axi_awcache      (m_axi_awcache),
        .m_axi_awprot       (m_axi_awprot),
        .m_axi_awvalid      (m_axi_awvalid),
        .m_axi_awready      (m_axi_awready),
        .m_axi_wdata        (m_axi_wdata),
        .m_axi_wstrb        (m_axi_wstrb),
        .m_axi_wlast        (m_axi_wlast),
        .m_axi_wvalid       (m_axi_wvalid),
        .m_axi_wready       (m_axi_wready),
        .m_axi_bid          (m_axi_bid),
        .m_axi_bresp        (m_axi_bresp),
        .m_axi_bvalid       (m_axi_bvalid),
        .m_axi_bready       (m_axi_bready),
        .m_axi_arid         (m_axi_arid),
        .m_axi_araddr       (m_axi_araddr),
        .m_axi_arlen        (m_axi_arlen),
        .m_axi_arsize       (m_axi_arsize),
        .m_axi_arburst      (m_axi_arburst),
        .m_axi_arlock       (m_axi_arlock),
        .m_axi_arcache      (m_axi_arcache),
        .m_axi_arprot       (m_axi_arprot),
        .m_axi_arvalid      (m_axi_arvalid),
        .m_axi_arready      (m_axi_arready),
        .m_axi_rid          (m_axi_rid),
        .m_axi_rdata        (m_axi_rdata),
        .m_axi_rresp        (m_axi_rresp),
        .m_axi_rlast        (m_axi_rlast),
        .m_axi_rvalid       (m_axi_rvalid),
        .m_axi_rready       (m_axi_rready)
    );
`endif

`ifdef USE_AHB_INTERFACE
    // AHB主接口实现
    ahb_master_interface u_ahb_master (
        .clk                (clk),
        .rst_n              (rst_n),
        
        // 内部请求接口
        .req_valid          (/* 内部请求 */),
        .req_addr           (/* 内部地址 */),
        .req_data           (/* 内部数据 */),
        .req_write          (/* 读写控制 */),
        .req_ready          (/* 就绪信号 */),
        .resp_data          (/* 响应数据 */),
        .resp_valid         (/* 响应有效 */),
        
        // AHB外部接口
        .haddr              (haddr),
        .hburst             (hburst),
        .hmastlock          (hmastlock),
        .hprot              (hprot),
        .hsize              (hsize),
        .htrans             (htrans),
        .hwdata             (hwdata),
        .hwrite             (hwrite),
        .hrdata             (hrdata),
        .hready             (hready),
        .hresp              (hresp)
    );
`endif

//============================================================================
// 设计约束验证 (仅仿真)
//============================================================================
`ifdef SIMULATION
    // 检查硬化配置一致性
    initial begin
        $display("=== 音频编解码器顶层模块配置 ===");
        $display("最大采样率: %0d Hz", MAX_SAMPLE_RATE);
        $display("最大采样位宽: %0d bit", MAX_SAMPLE_WIDTH);
        $display("内部处理位宽: %0d bit", INTERNAL_WIDTH);
        $display("最大帧样本数: %0d", MAX_FRAME_SAMPLES);
        $display("最大MDCT长度: %0d", MDCT_MAX_LENGTH);
        
        `ifdef USE_AXI4_INTERFACE
        $display("总线接口: AXI4");
        `endif
        `ifdef USE_AHB_INTERFACE  
        $display("总线接口: AHB");
        `endif
        
        $display("=================================");
    end
    
    // 采样率配置合法性检查
    always @(posedge clk) begin
        if (codec_enable) begin
            case (sample_rate_sel)
                5'd6, 5'd7: begin // 88.2kHz, 96kHz
                    `ifndef MAX_SAMPLE_RATE_96K
                    $error("ERROR: High sample rate selected but MAX_SAMPLE_RATE_96K not defined");
                    `endif
                end
            endcase
            
            case (sample_width_sel)
                2'b01: begin // 24bit
                    `ifndef SUPPORT_24BIT
                    $error("ERROR: 24-bit sample width selected but SUPPORT_24BIT not defined");
                    `endif
                end
            endcase
        end
    end
`endif

endmodule

//============================================================================
// 编译时配置摘要
//============================================================================
// 
// 顶层硬化配置选项:
// 1. MAX_SAMPLE_RATE_48K / MAX_SAMPLE_RATE_96K
//    - 影响: MDCT长度, 存储器大小, 时序要求
//    - 优化: 48K配置可减少约20%面积
//
// 2. SUPPORT_16BIT / SUPPORT_24BIT  
//    - 影响: 数据路径位宽, 精度, 功耗
//    - 优化: 16bit配置可减少约15%面积
//
// 3. USE_AXI4_INTERFACE / USE_AHB_INTERFACE
//    - 影响: 总线协议, 接口复杂度
//    - 选择: 根据目标系统总线类型
//
// RTL设计约束:
// - 禁用移位操作符 (<<, >>, >>>)
// - 禁用变量循环次数的for语句  
// - 仅使用单端口SRAM + 仲裁器
// - 严格遵循Verilog 2001标准
//
//============================================================================ 