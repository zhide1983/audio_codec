/*
 * Audio Codec Hardware Accelerator - Top Level Module
 * 
 * This is the top-level module for the audio codec hardware accelerator,
 * supporting LC3plus audio encoding and decoding with future extensions
 * for LC3 and Opus.
 */

module audio_codec_top #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_ID_WIDTH   = 4,
    parameter CHANNELS       = 8,          // Maximum supported channels
    parameter SAMPLE_WIDTH   = 16          // Sample bit width
) (
    // Clock and Reset
    input  logic                        clk,
    input  logic                        rst_n,
    
    // AXI4 Slave Interface for Control/Status
    input  logic [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  logic [2:0]                  s_axi_awprot,
    input  logic                        s_axi_awvalid,
    output logic                        s_axi_awready,
    
    input  logic [AXI_DATA_WIDTH-1:0]  s_axi_wdata,
    input  logic [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                        s_axi_wvalid,
    output logic                        s_axi_wready,
    
    output logic [1:0]                  s_axi_bresp,
    output logic                        s_axi_bvalid,
    input  logic                        s_axi_bready,
    
    input  logic [AXI_ADDR_WIDTH-1:0]  s_axi_araddr,
    input  logic [2:0]                  s_axi_arprot,
    input  logic                        s_axi_arvalid,
    output logic                        s_axi_arready,
    
    output logic [AXI_DATA_WIDTH-1:0]  s_axi_rdata,
    output logic [1:0]                  s_axi_rresp,
    output logic                        s_axi_rvalid,
    input  logic                        s_axi_rready,
    
    // AXI4 Master Interface for Memory Access
    output logic [AXI_ID_WIDTH-1:0]    m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0]  m_axi_awaddr,
    output logic [7:0]                  m_axi_awlen,
    output logic [2:0]                  m_axi_awsize,
    output logic [1:0]                  m_axi_awburst,
    output logic                        m_axi_awlock,
    output logic [3:0]                  m_axi_awcache,
    output logic [2:0]                  m_axi_awprot,
    output logic                        m_axi_awvalid,
    input  logic                        m_axi_awready,
    
    output logic [AXI_DATA_WIDTH-1:0]  m_axi_wdata,
    output logic [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output logic                        m_axi_wlast,
    output logic                        m_axi_wvalid,
    input  logic                        m_axi_wready,
    
    input  logic [AXI_ID_WIDTH-1:0]    m_axi_bid,
    input  logic [1:0]                  m_axi_bresp,
    input  logic                        m_axi_bvalid,
    output logic                        m_axi_bready,
    
    output logic [AXI_ID_WIDTH-1:0]    m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0]  m_axi_araddr,
    output logic [7:0]                  m_axi_arlen,
    output logic [2:0]                  m_axi_arsize,
    output logic [1:0]                  m_axi_arburst,
    output logic                        m_axi_arlock,
    output logic [3:0]                  m_axi_arcache,
    output logic [2:0]                  m_axi_arprot,
    output logic                        m_axi_arvalid,
    input  logic                        m_axi_arready,
    
    input  logic [AXI_ID_WIDTH-1:0]    m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]  m_axi_rdata,
    input  logic [1:0]                  m_axi_rresp,
    input  logic                        m_axi_rlast,
    input  logic                        m_axi_rvalid,
    output logic                        m_axi_rready,
    
    // Interrupt Output
    output logic                        irq,
    
    // Debug Interface
    output logic [31:0]                 debug_status,
    output logic [31:0]                 debug_counter
);

    // Internal signals
    logic [31:0] ctrl_reg_addr;
    logic [31:0] ctrl_reg_wdata;
    logic [31:0] ctrl_reg_rdata;
    logic        ctrl_reg_wen;
    logic        ctrl_reg_ren;
    
    // Configuration and Status
    logic [31:0] config_sample_rate;
    logic [31:0] config_bitrate;
    logic [31:0] config_frame_length;
    logic [2:0]  config_channels;
    logic [1:0]  config_codec_type;    // 00: LC3plus, 01: LC3, 10: Opus
    logic        config_encode_enable;
    logic        config_decode_enable;
    
    logic [31:0] status_encoder;
    logic [31:0] status_decoder;
    logic [31:0] status_dma;
    logic        irq_encoder_done;
    logic        irq_decoder_done;
    logic        irq_error;
    
    // Processing Engine Signals
    logic        proc_start;
    logic        proc_done;
    logic        proc_error;
    
    // Memory Management
    logic [31:0] input_buffer_addr;
    logic [31:0] output_buffer_addr;
    logic [15:0] buffer_size;
    
    //==========================================================================
    // AXI4 Slave Interface (Control/Status Registers)
    //==========================================================================
    axi4_slave_reg #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_axi_slave (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI Interface
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        
        // Register Interface
        .reg_addr       (ctrl_reg_addr),
        .reg_wdata      (ctrl_reg_wdata),
        .reg_rdata      (ctrl_reg_rdata),
        .reg_wen        (ctrl_reg_wen),
        .reg_ren        (ctrl_reg_ren)
    );

    //==========================================================================
    // Register Bank
    //==========================================================================
    register_bank #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) u_register_bank (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Control Interface
        .reg_addr               (ctrl_reg_addr),
        .reg_wdata              (ctrl_reg_wdata),
        .reg_rdata              (ctrl_reg_rdata),
        .reg_wen                (ctrl_reg_wen),
        .reg_ren                (ctrl_reg_ren),
        
        // Configuration Outputs
        .config_sample_rate     (config_sample_rate),
        .config_bitrate         (config_bitrate),
        .config_frame_length    (config_frame_length),
        .config_channels        (config_channels),
        .config_codec_type      (config_codec_type),
        .config_encode_enable   (config_encode_enable),
        .config_decode_enable   (config_decode_enable),
        
        // Status Inputs
        .status_encoder         (status_encoder),
        .status_decoder         (status_decoder),
        .status_dma             (status_dma),
        
        // Buffer Management
        .input_buffer_addr      (input_buffer_addr),
        .output_buffer_addr     (output_buffer_addr),
        .buffer_size            (buffer_size),
        
        // Control Signals
        .proc_start             (proc_start)
    );

    //==========================================================================
    // LC3plus Processing Core
    //==========================================================================
    lc3plus_core #(
        .CHANNELS       (CHANNELS),
        .SAMPLE_WIDTH   (SAMPLE_WIDTH)
    ) u_lc3plus_core (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Configuration
        .config_sample_rate     (config_sample_rate),
        .config_bitrate         (config_bitrate),
        .config_frame_length    (config_frame_length),
        .config_channels        (config_channels),
        .config_encode_enable   (config_encode_enable),
        .config_decode_enable   (config_decode_enable),
        
        // Control
        .start                  (proc_start & (config_codec_type == 2'b00)),
        .done                   (proc_done),
        .error                  (proc_error),
        
        // Status
        .encoder_status         (status_encoder),
        .decoder_status         (status_decoder),
        
        // Memory Interface (connected to DMA)
        .input_buffer_addr      (input_buffer_addr),
        .output_buffer_addr     (output_buffer_addr),
        .buffer_size            (buffer_size),
        
        // AXI Master Interface (for memory access)
        .m_axi_awid     (m_axi_awid),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awlock   (m_axi_awlock),
        .m_axi_awcache  (m_axi_awcache),
        .m_axi_awprot   (m_axi_awprot),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bid      (m_axi_bid),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        .m_axi_arid     (m_axi_arid),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arlock   (m_axi_arlock),
        .m_axi_arcache  (m_axi_arcache),
        .m_axi_arprot   (m_axi_arprot),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );

    //==========================================================================
    // Interrupt Controller
    //==========================================================================
    interrupt_controller u_irq_ctrl (
        .clk                (clk),
        .rst_n              (rst_n),
        
        // Interrupt Sources
        .irq_encoder_done   (proc_done & config_encode_enable),
        .irq_decoder_done   (proc_done & config_decode_enable),
        .irq_error          (proc_error),
        
        // Interrupt Output
        .irq                (irq)
    );

    //==========================================================================
    // Debug and Performance Monitoring
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debug_status  <= 32'h0;
            debug_counter <= 32'h0;
        end else begin
            debug_status <= {
                24'h0,
                proc_error,         // [7]
                proc_done,          // [6] 
                proc_start,         // [5]
                config_decode_enable, // [4]
                config_encode_enable, // [3]
                config_codec_type   // [2:0]
            };
            
            if (proc_start) begin
                debug_counter <= debug_counter + 1;
            end
        end
    end

endmodule 