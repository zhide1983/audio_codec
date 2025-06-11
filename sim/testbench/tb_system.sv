/*
 * System-level Testbench for Audio Codec Hardware Accelerator
 * 
 * This testbench provides comprehensive testing of the complete audio codec
 * system including AXI interfaces, processing cores, and end-to-end verification.
 */

`timescale 1ns/1ps

module tb_system;

    // Parameters
    parameter CLK_PERIOD     = 10;  // 100MHz
    parameter AXI_ADDR_WIDTH = 32;
    parameter AXI_DATA_WIDTH = 32;
    parameter AXI_ID_WIDTH   = 4;
    parameter CHANNELS       = 8;
    parameter SAMPLE_WIDTH   = 16;
    
    // Test configuration
    parameter TEST_VECTORS_PATH = "../vectors/";
    parameter TEST_RESULTS_PATH = "../results/";
    
    // Clock and Reset
    logic clk;
    logic rst_n;
    
    // AXI4 Slave Interface signals
    logic [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr;
    logic [2:0]                  s_axi_awprot;
    logic                        s_axi_awvalid;
    logic                        s_axi_awready;
    logic [AXI_DATA_WIDTH-1:0]  s_axi_wdata;
    logic [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb;
    logic                        s_axi_wvalid;
    logic                        s_axi_wready;
    logic [1:0]                  s_axi_bresp;
    logic                        s_axi_bvalid;
    logic                        s_axi_bready;
    logic [AXI_ADDR_WIDTH-1:0]  s_axi_araddr;
    logic [2:0]                  s_axi_arprot;
    logic                        s_axi_arvalid;
    logic                        s_axi_arready;
    logic [AXI_DATA_WIDTH-1:0]  s_axi_rdata;
    logic [1:0]                  s_axi_rresp;
    logic                        s_axi_rvalid;
    logic                        s_axi_rready;
    
    // AXI4 Master Interface signals
    logic [AXI_ID_WIDTH-1:0]    m_axi_awid;
    logic [AXI_ADDR_WIDTH-1:0]  m_axi_awaddr;
    logic [7:0]                  m_axi_awlen;
    logic [2:0]                  m_axi_awsize;
    logic [1:0]                  m_axi_awburst;
    logic                        m_axi_awlock;
    logic [3:0]                  m_axi_awcache;
    logic [2:0]                  m_axi_awprot;
    logic                        m_axi_awvalid;
    logic                        m_axi_awready;
    logic [AXI_DATA_WIDTH-1:0]  m_axi_wdata;
    logic [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb;
    logic                        m_axi_wlast;
    logic                        m_axi_wvalid;
    logic                        m_axi_wready;
    logic [AXI_ID_WIDTH-1:0]    m_axi_bid;
    logic [1:0]                  m_axi_bresp;
    logic                        m_axi_bvalid;
    logic                        m_axi_bready;
    logic [AXI_ID_WIDTH-1:0]    m_axi_arid;
    logic [AXI_ADDR_WIDTH-1:0]  m_axi_araddr;
    logic [7:0]                  m_axi_arlen;
    logic [2:0]                  m_axi_arsize;
    logic [1:0]                  m_axi_arburst;
    logic                        m_axi_arlock;
    logic [3:0]                  m_axi_arcache;
    logic [2:0]                  m_axi_arprot;
    logic                        m_axi_arvalid;
    logic                        m_axi_arready;
    logic [AXI_ID_WIDTH-1:0]    m_axi_rid;
    logic [AXI_DATA_WIDTH-1:0]  m_axi_rdata;
    logic [1:0]                  m_axi_rresp;
    logic                        m_axi_rlast;
    logic                        m_axi_rvalid;
    logic                        m_axi_rready;
    
    // Other signals
    logic irq;
    logic [31:0] debug_status;
    logic [31:0] debug_counter;
    
    // Test control
    logic test_pass;
    logic test_fail;
    int   test_count;
    int   pass_count;
    int   fail_count;
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    audio_codec_top #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .CHANNELS       (CHANNELS),
        .SAMPLE_WIDTH   (SAMPLE_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI4 Slave Interface
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
        
        // AXI4 Master Interface  
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
        .m_axi_rready   (m_axi_rready),
        
        .irq            (irq),
        .debug_status   (debug_status),
        .debug_counter  (debug_counter)
    );
    
    //==========================================================================
    // AXI Memory Model (Simple BRAM-based model)
    //==========================================================================
    axi_memory_model #(
        .ADDR_WIDTH     (AXI_ADDR_WIDTH),
        .DATA_WIDTH     (AXI_DATA_WIDTH),
        .ID_WIDTH       (AXI_ID_WIDTH),
        .MEMORY_SIZE    (1024*1024)  // 1MB memory
    ) u_memory_model (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI4 Slave Interface
        .s_axi_awid     (m_axi_awid),
        .s_axi_awaddr   (m_axi_awaddr),
        .s_axi_awlen    (m_axi_awlen),
        .s_axi_awsize   (m_axi_awsize),
        .s_axi_awburst  (m_axi_awburst),
        .s_axi_awlock   (m_axi_awlock),
        .s_axi_awcache  (m_axi_awcache),
        .s_axi_awprot   (m_axi_awprot),
        .s_axi_awvalid  (m_axi_awvalid),
        .s_axi_awready  (m_axi_awready),
        .s_axi_wdata    (m_axi_wdata),
        .s_axi_wstrb    (m_axi_wstrb),
        .s_axi_wlast    (m_axi_wlast),
        .s_axi_wvalid   (m_axi_wvalid),
        .s_axi_wready   (m_axi_wready),
        .s_axi_bid      (m_axi_bid),
        .s_axi_bresp    (m_axi_bresp),
        .s_axi_bvalid   (m_axi_bvalid),
        .s_axi_bready   (m_axi_bready),
        .s_axi_arid     (m_axi_arid),
        .s_axi_araddr   (m_axi_araddr),
        .s_axi_arlen    (m_axi_arlen),
        .s_axi_arsize   (m_axi_arsize),
        .s_axi_arburst  (m_axi_arburst),
        .s_axi_arlock   (m_axi_arlock),
        .s_axi_arcache  (m_axi_arcache),
        .s_axi_arprot   (m_axi_arprot),
        .s_axi_arvalid  (m_axi_arvalid),
        .s_axi_arready  (m_axi_arready),
        .s_axi_rid      (m_axi_rid),
        .s_axi_rdata    (m_axi_rdata),
        .s_axi_rresp    (m_axi_rresp),
        .s_axi_rlast    (m_axi_rlast),
        .s_axi_rvalid   (m_axi_rvalid),
        .s_axi_rready   (m_axi_rready)
    );
    
    //==========================================================================
    // Test Tasks
    //==========================================================================
    
    // AXI Write Task
    task axi_write(
        input [AXI_ADDR_WIDTH-1:0] addr,
        input [AXI_DATA_WIDTH-1:0] data
    );
        begin
            @(posedge clk);
            s_axi_awaddr  = addr;
            s_axi_awprot  = 3'b000;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = data;
            s_axi_wstrb   = 4'b1111;
            s_axi_wvalid  = 1'b1;
            s_axi_bready  = 1'b1;
            
            wait(s_axi_awready && s_axi_wready);
            @(posedge clk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
            
            wait(s_axi_bvalid);
            @(posedge clk);
            s_axi_bready = 1'b0;
        end
    endtask
    
    // AXI Read Task
    task axi_read(
        input  [AXI_ADDR_WIDTH-1:0] addr,
        output [AXI_DATA_WIDTH-1:0] data
    );
        begin
            @(posedge clk);
            s_axi_araddr  = addr;
            s_axi_arprot  = 3'b000;
            s_axi_arvalid = 1'b1;
            s_axi_rready  = 1'b1;
            
            wait(s_axi_arready);
            @(posedge clk);
            s_axi_arvalid = 1'b0;
            
            wait(s_axi_rvalid);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_rready = 1'b0;
        end
    endtask
    
    // Reset Task
    task system_reset();
        begin
            rst_n = 1'b0;
            
            // Initialize AXI signals
            s_axi_awaddr  = 0;
            s_axi_awprot  = 0;
            s_axi_awvalid = 0;
            s_axi_wdata   = 0;
            s_axi_wstrb   = 0;
            s_axi_wvalid  = 0;
            s_axi_bready  = 0;
            s_axi_araddr  = 0;
            s_axi_arprot  = 0;
            s_axi_arvalid = 0;
            s_axi_rready  = 0;
            
            repeat(10) @(posedge clk);
            rst_n = 1'b1;
            repeat(5) @(posedge clk);
        end
    endtask
    
    // Configure LC3plus encoding
    task configure_lc3plus_encoder(
        input [31:0] sample_rate,
        input [31:0] bitrate,
        input [31:0] frame_length,
        input [2:0]  channels
    );
        begin
            $display("Configuring LC3plus encoder: SR=%0d, BR=%0d, FL=%0d, CH=%0d", 
                     sample_rate, bitrate, frame_length, channels);
            
            // Register addresses (these should match the register bank implementation)
            axi_write(32'h0000, sample_rate);   // Sample rate register
            axi_write(32'h0004, bitrate);       // Bitrate register  
            axi_write(32'h0008, frame_length);  // Frame length register
            axi_write(32'h000C, {29'h0, channels}); // Channel config
            axi_write(32'h0010, 32'h00000001);  // Enable encoder
        end
    endtask
    
    // Start processing
    task start_processing();
        begin
            $display("Starting processing...");
            axi_write(32'h0020, 32'h00000001);  // Start command
        end
    endtask
    
    // Wait for completion
    task wait_for_completion();
        logic [31:0] status;
        int timeout_count;
        begin
            $display("Waiting for processing completion...");
            timeout_count = 0;
            
            do begin
                #1000;  // Wait 1us
                axi_read(32'h0200, status);  // Read status register
                timeout_count++;
                
                if (timeout_count > 10000) begin
                    $error("Timeout waiting for completion!");
                    test_fail = 1'b1;
                    return;
                end
            end while (!(status & 32'h00000001));  // Check done bit
            
            $display("Processing completed. Status: 0x%08x", status);
        end
    endtask
    
    // Run basic functionality test
    task test_basic_functionality();
        begin
            $display("=== Running Basic Functionality Test ===");
            test_count++;
            
            // Configure for basic test
            configure_lc3plus_encoder(48000, 64000, 480, 3'h1);  // 48kHz, 64kbps, mono
            
            // Load test data (simplified - in real test would load from file)
            // Set input buffer address
            axi_write(32'h0030, 32'h00010000);  // Input buffer at 0x10000
            axi_write(32'h0034, 32'h00020000);  // Output buffer at 0x20000
            axi_write(32'h0038, 16'h0200);     // Buffer size (512 samples)
            
            // Start processing
            start_processing();
            
            // Wait for completion
            wait_for_completion();
            
            if (!test_fail) begin
                $display("Basic functionality test PASSED");
                pass_count++;
                test_pass = 1'b1;
            end else begin
                $display("Basic functionality test FAILED");
                fail_count++;
            end
        end
    endtask
    
    // Test different sample rates
    task test_sample_rates();
        int rates[$] = '{16000, 24000, 32000, 48000};
        int i;
        begin
            $display("=== Running Sample Rate Test ===");
            
            for (i = 0; i < rates.size(); i++) begin
                $display("Testing sample rate: %0d Hz", rates[i]);
                test_count++;
                test_fail = 1'b0;
                
                configure_lc3plus_encoder(rates[i], 64000, rates[i]/100, 3'h1);
                
                axi_write(32'h0030, 32'h00010000);
                axi_write(32'h0034, 32'h00020000);
                axi_write(32'h0038, 16'h0200);
                
                start_processing();
                wait_for_completion();
                
                if (!test_fail) begin
                    $display("Sample rate %0d test PASSED", rates[i]);
                    pass_count++;
                end else begin
                    $display("Sample rate %0d test FAILED", rates[i]);
                    fail_count++;
                end
            end
        end
    endtask
    
    // Test interrupt functionality
    task test_interrupts();
        begin
            $display("=== Running Interrupt Test ===");
            test_count++;
            test_fail = 1'b0;
            
            configure_lc3plus_encoder(48000, 64000, 480, 3'h1);
            
            axi_write(32'h0030, 32'h00010000);
            axi_write(32'h0034, 32'h00020000);
            axi_write(32'h0038, 16'h0200);
            
            start_processing();
            
            // Wait for interrupt
            wait(irq);
            $display("Interrupt received");
            
            if (!test_fail) begin
                $display("Interrupt test PASSED");
                pass_count++;
            end else begin
                $display("Interrupt test FAILED");
                fail_count++;
            end
        end
    endtask
    
    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        $display("=== Audio Codec System Test Started ===");
        $display("Time: %0t", $time);
        
        // Initialize variables
        test_pass  = 1'b0;
        test_fail  = 1'b0;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        // System reset
        system_reset();
        $display("System reset completed");
        
        // Run test suite
        test_basic_functionality();
        test_sample_rates();
        test_interrupts();
        
        // Test summary
        $display("=== Test Summary ===");
        $display("Total tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        $display("Pass rate: %0.1f%%", real'(pass_count)/real'(test_count)*100.0);
        
        if (fail_count == 0) begin
            $display("ALL TESTS PASSED");
            $display("TEST_PASS");
        end else begin
            $display("SOME TESTS FAILED");
            $display("TEST_FAIL");
        end
        
        $display("=== Audio Codec System Test Completed ===");
        $finish;
    end
    
    //==========================================================================
    // Waveform Dumping
    //==========================================================================
    initial begin
        $dumpfile("system.vcd");
        $dumpvars(0, tb_system);
    end
    
    //==========================================================================
    // Timeout Protection
    //==========================================================================
    initial begin
        #10_000_000;  // 10ms timeout
        $error("Test timeout!");
        $finish;
    end

endmodule 