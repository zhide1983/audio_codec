/*
 * Audio Codec Hardware Accelerator - Top Level Module v2.0
 * 
 * Enhanced version supporting:
 * - Configurable AXI4/AHB master interface
 * - APB slave interface for register access
 * - JSON-based register configuration
 * - Improved SoC integration capabilities
 */

module audio_codec_top #(
    // Bus interface configuration
    parameter string BUS_TYPE        = "AXI4",     // "AXI4" or "AHB"
    parameter        ADDR_WIDTH      = 32,
    parameter        DATA_WIDTH      = 32,
    parameter        MASTER_ID_WIDTH = 4,
    
    // Audio codec parameters
    parameter        CHANNELS        = 8,          // Maximum supported channels
    parameter        SAMPLE_WIDTH    = 16,         // Sample bit width
    
    // Register map configuration
    parameter string REG_MAP_FILE    = "../docs/specifications/register_map.json"
) (
    // Clock and Reset
    input  logic                        clk,
    input  logic                        rst_n,
    
    //==========================================================================
    // APB Slave Interface for Register Access
    //==========================================================================
    input  logic [ADDR_WIDTH-1:0]      s_apb_paddr,
    input  logic                        s_apb_psel,
    input  logic                        s_apb_penable,
    input  logic                        s_apb_pwrite,
    input  logic [DATA_WIDTH-1:0]      s_apb_pwdata,
    input  logic [DATA_WIDTH/8-1:0]    s_apb_pstrb,
    output logic [DATA_WIDTH-1:0]      s_apb_prdata,
    output logic                        s_apb_pready,
    output logic                        s_apb_pslverr,
    
    //==========================================================================
    // AXI4 Master Interface (when BUS_TYPE = "AXI4")
    //==========================================================================
    // Write Address Channel
    output logic [MASTER_ID_WIDTH-1:0] m_axi_awid,
    output logic [ADDR_WIDTH-1:0]      m_axi_awaddr,
    output logic [7:0]                  m_axi_awlen,
    output logic [2:0]                  m_axi_awsize,
    output logic [1:0]                  m_axi_awburst,
    output logic                        m_axi_awlock,
    output logic [3:0]                  m_axi_awcache,
    output logic [2:0]                  m_axi_awprot,
    output logic [3:0]                  m_axi_awqos,
    output logic                        m_axi_awvalid,
    input  logic                        m_axi_awready,
    
    // Write Data Channel
    output logic [DATA_WIDTH-1:0]      m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0]    m_axi_wstrb,
    output logic                        m_axi_wlast,
    output logic                        m_axi_wvalid,
    input  logic                        m_axi_wready,
    
    // Write Response Channel
    input  logic [MASTER_ID_WIDTH-1:0] m_axi_bid,
    input  logic [1:0]                  m_axi_bresp,
    input  logic                        m_axi_bvalid,
    output logic                        m_axi_bready,
    
    // Read Address Channel
    output logic [MASTER_ID_WIDTH-1:0] m_axi_arid,
    output logic [ADDR_WIDTH-1:0]      m_axi_araddr,
    output logic [7:0]                  m_axi_arlen,
    output logic [2:0]                  m_axi_arsize,
    output logic [1:0]                  m_axi_arburst,
    output logic                        m_axi_arlock,
    output logic [3:0]                  m_axi_arcache,
    output logic [2:0]                  m_axi_arprot,
    output logic [3:0]                  m_axi_arqos,
    output logic                        m_axi_arvalid,
    input  logic                        m_axi_arready,
    
    // Read Data Channel
    input  logic [MASTER_ID_WIDTH-1:0] m_axi_rid,
    input  logic [DATA_WIDTH-1:0]      m_axi_rdata,
    input  logic [1:0]                  m_axi_rresp,
    input  logic                        m_axi_rlast,
    input  logic                        m_axi_rvalid,
    output logic                        m_axi_rready,
    
    //==========================================================================
    // AHB Master Interface (when BUS_TYPE = "AHB")
    //==========================================================================
    output logic [ADDR_WIDTH-1:0]      m_ahb_haddr,
    output logic [2:0]                  m_ahb_hsize,
    output logic [1:0]                  m_ahb_htrans,
    output logic [DATA_WIDTH-1:0]      m_ahb_hwdata,
    output logic                        m_ahb_hwrite,
    output logic [2:0]                  m_ahb_hburst,
    output logic [3:0]                  m_ahb_hprot,
    input  logic [DATA_WIDTH-1:0]      m_ahb_hrdata,
    input  logic                        m_ahb_hready,
    input  logic [1:0]                  m_ahb_hresp,
    
    //==========================================================================
    // Interrupt and Debug
    //==========================================================================
    output logic                        irq,
    output logic [31:0]                 debug_status,
    output logic [31:0]                 debug_counter
);

    // Internal bus interface signals (unified)
    logic [ADDR_WIDTH-1:0]      mem_addr;
    logic [DATA_WIDTH-1:0]      mem_wdata;
    logic [DATA_WIDTH-1:0]      mem_rdata;
    logic [DATA_WIDTH/8-1:0]    mem_wstrb;
    logic                       mem_valid;
    logic                       mem_ready;
    logic                       mem_write;
    logic [7:0]                 mem_len;        // Burst length
    logic                       mem_error;
    
    // Register interface signals
    logic [ADDR_WIDTH-1:0]      reg_addr;
    logic [DATA_WIDTH-1:0]      reg_wdata;
    logic [DATA_WIDTH-1:0]      reg_rdata;
    logic                       reg_wen;
    logic                       reg_ren;
    logic                       reg_ready;
    logic                       reg_error;
    
    // Configuration signals from registers
    logic [31:0]                config_sample_rate;
    logic [31:0]                config_bitrate;
    logic [31:0]                config_frame_length;
    logic [3:0]                 config_channels;
    logic [1:0]                 config_codec_type;
    logic [1:0]                 config_mode;
    logic                       config_enable;
    logic                       config_start;
    logic                       config_soft_reset;
    logic                       config_irq_enable;
    
    // Status signals to registers
    logic [31:0]                status_main;
    logic [31:0]                status_irq;
    logic [31:0]                status_frame_count;
    logic [31:0]                status_perf_counter;
    logic [31:0]                status_debug0;
    logic [31:0]                status_debug1;
    
    // Processing control signals
    logic                       proc_start;
    logic                       proc_done;
    logic                       proc_error;
    logic                       proc_idle;
    
    // Buffer management
    logic [31:0]                input_buffer_addr;
    logic [31:0]                output_buffer_addr;
    logic [15:0]                input_buffer_size;
    logic [15:0]                output_buffer_size;
    
    // Interrupt sources
    logic                       irq_frame_done;
    logic                       irq_encode_done;
    logic                       irq_decode_done;
    logic                       irq_error;
    
    //==========================================================================
    // APB Slave Interface for Register Access
    //==========================================================================
    apb_slave_regs #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .REG_MAP_FILE   (REG_MAP_FILE)
    ) u_apb_slave (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // APB Interface
        .s_apb_paddr    (s_apb_paddr),
        .s_apb_psel     (s_apb_psel),
        .s_apb_penable  (s_apb_penable),
        .s_apb_pwrite   (s_apb_pwrite),
        .s_apb_pwdata   (s_apb_pwdata),
        .s_apb_pstrb    (s_apb_pstrb),
        .s_apb_prdata   (s_apb_prdata),
        .s_apb_pready   (s_apb_pready),
        .s_apb_pslverr  (s_apb_pslverr),
        
        // Register Interface
        .reg_addr       (reg_addr),
        .reg_wdata      (reg_wdata),
        .reg_rdata      (reg_rdata),
        .reg_wen        (reg_wen),
        .reg_ren        (reg_ren),
        .reg_ready      (reg_ready),
        .reg_error      (reg_error)
    );
    
    //==========================================================================
    // Register Bank (JSON-configured)
    //==========================================================================
    audio_codec_regs #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .REG_MAP_FILE   (REG_MAP_FILE)
    ) u_register_bank (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Register Interface
        .reg_addr               (reg_addr),
        .reg_wdata              (reg_wdata),
        .reg_rdata              (reg_rdata),
        .reg_wen                (reg_wen),
        .reg_ren                (reg_ren),
        .reg_ready              (reg_ready),
        .reg_error              (reg_error),
        
        // Configuration Outputs
        .config_sample_rate     (config_sample_rate),
        .config_bitrate         (config_bitrate),
        .config_frame_length    (config_frame_length),
        .config_channels        (config_channels),
        .config_codec_type      (config_codec_type),
        .config_mode            (config_mode),
        .config_enable          (config_enable),
        .config_start           (config_start),
        .config_soft_reset      (config_soft_reset),
        .config_irq_enable      (config_irq_enable),
        
        // Status Inputs
        .status_main            (status_main),
        .status_irq             (status_irq),
        .status_frame_count     (status_frame_count),
        .status_perf_counter    (status_perf_counter),
        .status_debug0          (status_debug0),
        .status_debug1          (status_debug1),
        
        // Buffer Configuration
        .input_buffer_addr      (input_buffer_addr),
        .output_buffer_addr     (output_buffer_addr),
        .input_buffer_size      (input_buffer_size),
        .output_buffer_size     (output_buffer_size),
        
        // Interrupt Status
        .irq_frame_done         (irq_frame_done),
        .irq_encode_done        (irq_encode_done),
        .irq_decode_done        (irq_decode_done),
        .irq_error_in           (irq_error)
    );
    
    //==========================================================================
    // Master Bus Interface Adapter
    //==========================================================================
    generate
        if (BUS_TYPE == "AXI4") begin : gen_axi_master
            axi4_master_adapter #(
                .ADDR_WIDTH     (ADDR_WIDTH),
                .DATA_WIDTH     (DATA_WIDTH),
                .ID_WIDTH       (MASTER_ID_WIDTH)
            ) u_master_adapter (
                .clk            (clk),
                .rst_n          (rst_n),
                
                // Internal Memory Interface
                .mem_addr       (mem_addr),
                .mem_wdata      (mem_wdata),
                .mem_rdata      (mem_rdata),
                .mem_wstrb      (mem_wstrb),
                .mem_valid      (mem_valid),
                .mem_ready      (mem_ready),
                .mem_write      (mem_write),
                .mem_len        (mem_len),
                .mem_error      (mem_error),
                
                // AXI4 Master Interface
                .m_axi_awid     (m_axi_awid),
                .m_axi_awaddr   (m_axi_awaddr),
                .m_axi_awlen    (m_axi_awlen),
                .m_axi_awsize   (m_axi_awsize),
                .m_axi_awburst  (m_axi_awburst),
                .m_axi_awlock   (m_axi_awlock),
                .m_axi_awcache  (m_axi_awcache),
                .m_axi_awprot   (m_axi_awprot),
                .m_axi_awqos    (m_axi_awqos),
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
                .m_axi_arqos    (m_axi_arqos),
                .m_axi_arvalid  (m_axi_arvalid),
                .m_axi_arready  (m_axi_arready),
                .m_axi_rid      (m_axi_rid),
                .m_axi_rdata    (m_axi_rdata),
                .m_axi_rresp    (m_axi_rresp),
                .m_axi_rlast    (m_axi_rlast),
                .m_axi_rvalid   (m_axi_rvalid),
                .m_axi_rready   (m_axi_rready)
            );
            
            // Tie off AHB signals
            assign m_ahb_haddr  = '0;
            assign m_ahb_hsize  = '0;
            assign m_ahb_htrans = '0;
            assign m_ahb_hwdata = '0;
            assign m_ahb_hwrite = '0;
            assign m_ahb_hburst = '0;
            assign m_ahb_hprot  = '0;
            
        end else if (BUS_TYPE == "AHB") begin : gen_ahb_master
            ahb_master_adapter #(
                .ADDR_WIDTH     (ADDR_WIDTH),
                .DATA_WIDTH     (DATA_WIDTH)
            ) u_master_adapter (
                .clk            (clk),
                .rst_n          (rst_n),
                
                // Internal Memory Interface
                .mem_addr       (mem_addr),
                .mem_wdata      (mem_wdata),
                .mem_rdata      (mem_rdata),
                .mem_wstrb      (mem_wstrb),
                .mem_valid      (mem_valid),
                .mem_ready      (mem_ready),
                .mem_write      (mem_write),
                .mem_len        (mem_len),
                .mem_error      (mem_error),
                
                // AHB Master Interface
                .m_ahb_haddr    (m_ahb_haddr),
                .m_ahb_hsize    (m_ahb_hsize),
                .m_ahb_htrans   (m_ahb_htrans),
                .m_ahb_hwdata   (m_ahb_hwdata),
                .m_ahb_hwrite   (m_ahb_hwrite),
                .m_ahb_hburst   (m_ahb_hburst),
                .m_ahb_hprot    (m_ahb_hprot),
                .m_ahb_hrdata   (m_ahb_hrdata),
                .m_ahb_hready   (m_ahb_hready),
                .m_ahb_hresp    (m_ahb_hresp)
            );
            
            // Tie off AXI signals
            assign m_axi_awid    = '0;
            assign m_axi_awaddr  = '0;
            assign m_axi_awlen   = '0;
            assign m_axi_awsize  = '0;
            assign m_axi_awburst = '0;
            assign m_axi_awlock  = '0;
            assign m_axi_awcache = '0;
            assign m_axi_awprot  = '0;
            assign m_axi_awqos   = '0;
            assign m_axi_awvalid = '0;
            assign m_axi_wdata   = '0;
            assign m_axi_wstrb   = '0;
            assign m_axi_wlast   = '0;
            assign m_axi_wvalid  = '0;
            assign m_axi_bready  = '0;
            assign m_axi_arid    = '0;
            assign m_axi_araddr  = '0;
            assign m_axi_arlen   = '0;
            assign m_axi_arsize  = '0;
            assign m_axi_arburst = '0;
            assign m_axi_arlock  = '0;
            assign m_axi_arcache = '0;
            assign m_axi_arprot  = '0;
            assign m_axi_arqos   = '0;
            assign m_axi_arvalid = '0;
            assign m_axi_rready  = '0;
            
        end else begin : gen_error
            // Invalid bus type
            initial begin
                $fatal(1, "Invalid BUS_TYPE parameter: %s. Must be 'AXI4' or 'AHB'", BUS_TYPE);
            end
        end
    endgenerate
    
    //==========================================================================
    // Audio Codec Processing Core
    //==========================================================================
    audio_codec_core #(
        .CHANNELS       (CHANNELS),
        .SAMPLE_WIDTH   (SAMPLE_WIDTH)
    ) u_codec_core (
        .clk                    (clk),
        .rst_n                  (rst_n & ~config_soft_reset),
        
        // Configuration
        .config_sample_rate     (config_sample_rate),
        .config_bitrate         (config_bitrate),
        .config_frame_length    (config_frame_length),
        .config_channels        (config_channels[2:0]),
        .config_codec_type      (config_codec_type),
        .config_mode            (config_mode),
        .config_enable          (config_enable),
        
        // Control
        .start                  (config_start),
        .done                   (proc_done),
        .error                  (proc_error),
        .idle                   (proc_idle),
        
        // Buffer Configuration
        .input_buffer_addr      (input_buffer_addr),
        .output_buffer_addr     (output_buffer_addr),
        .input_buffer_size      (input_buffer_size),
        .output_buffer_size     (output_buffer_size),
        
        // Memory Interface
        .mem_addr               (mem_addr),
        .mem_wdata              (mem_wdata),
        .mem_rdata              (mem_rdata),
        .mem_wstrb              (mem_wstrb),
        .mem_valid              (mem_valid),
        .mem_ready              (mem_ready),
        .mem_write              (mem_write),
        .mem_len                (mem_len),
        .mem_error              (mem_error),
        
        // Status and Debug
        .frame_count            (status_frame_count),
        .perf_counter           (status_perf_counter),
        .debug_info0            (status_debug0),
        .debug_info1            (status_debug1)
    );
    
    //==========================================================================
    // Status Generation
    //==========================================================================
    always_comb begin
        status_main = {
            24'h0,                  // [31:8] Reserved
            proc_error,             // [7] Error
            1'b0,                   // [6] Overflow (TBD)
            1'b0,                   // [5] Underflow (TBD)
            ~proc_idle,             // [4] Processing
            proc_done,              // [3] Frame done
            config_mode == 2'b10,   // [2] Decoder ready
            config_mode == 2'b01,   // [1] Encoder ready
            proc_idle               // [0] Idle
        };
    end
    
    //==========================================================================
    // Interrupt Generation
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_frame_done  <= 1'b0;
            irq_encode_done <= 1'b0;
            irq_decode_done <= 1'b0;
            irq_error       <= 1'b0;
        end else begin
            // Frame done interrupt
            if (proc_done) begin
                irq_frame_done <= 1'b1;
                if (config_mode == 2'b01) irq_encode_done <= 1'b1;
                if (config_mode == 2'b10) irq_decode_done <= 1'b1;
            end
            
            // Error interrupt
            if (proc_error) begin
                irq_error <= 1'b1;
            end
            
            // Clear interrupts when read (handled in register bank)
        end
    end
    
    // Main interrupt output
    assign irq = config_irq_enable & (|status_irq);
    
    //==========================================================================
    // Debug and Performance Monitoring
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debug_status  <= 32'h0;
            debug_counter <= 32'h0;
        end else begin
            debug_status <= {
                16'h0,
                BUS_TYPE == "AXI4" ? 8'hA4 : 8'hAB,  // [15:8] Bus type indicator
                proc_error,         // [7]
                proc_done,          // [6] 
                config_start,       // [5]
                config_mode,        // [4:3]
                config_codec_type   // [2:0]
            };
            
            if (config_start) begin
                debug_counter <= debug_counter + 1;
            end
        end
    end

endmodule 