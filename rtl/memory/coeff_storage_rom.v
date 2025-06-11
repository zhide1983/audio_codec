//******************************************************************************
// Coefficient Storage ROM Module
// 
// This module implements the read-only memory for storing constant coefficients
// including MDCT twiddle factors, window functions, quantization tables, and
// other lookup tables required by the LC3plus encoder.
//
// Memory Size: 16KB (4096 x 32-bit words)
// Technology: Single-port ROM
// 
// Author: Audio Codec Design Team
// Date: 2024-06-11
// Version: 1.0
//******************************************************************************

module coeff_storage_rom (
    // Clock - all operations are synchronous to this clock
    input               clk,
    
    // ROM access interface
    input   [11:0]      addr,           // Address (4096 deep)
    input               ren,            // Read enable
    output  reg [31:0]  rdata           // Read data
);

    // ROM array declaration
    // 4096 words x 32 bits = 16KB total
    reg [31:0] rom_memory [0:4095];
    
    // Initialize ROM with coefficient data
    initial begin
        // Initialize ROM from external file or hardcoded values
        $readmemh("coeff_data.hex", rom_memory);
        
        // If file not found, initialize with default values for simulation
        if (rom_memory[0] === 32'hxxxxxxxx) begin
            $display("INFO: Coefficient file not found, using default values");
            init_default_coefficients();
        end
    end
    
    // ROM read operation
    always @(posedge clk) begin
        if (ren) begin
            rdata <= rom_memory[addr];
        end else begin
            rdata <= 32'h00000000;
        end
    end
    
    // Default coefficient initialization for simulation
    task init_default_coefficients;
        integer i;
        begin
            // Initialize all to zero first
            for (i = 0; i < 4096; i = i + 1) begin
                rom_memory[i] = 32'h00000000;
            end
            
            // MDCT twiddle factors (0x0000 - 0x03FF)
            init_mdct_coefficients();
            
            // Window functions (0x0400 - 0x05FF)
            init_window_functions();
            
            // Quantization tables (0x0600 - 0x07FF)
            init_quantization_tables();
            
            // Psychoacoustic model tables (0x0800 - 0x09FF)
            init_psychoacoustic_tables();
            
            // Entropy coding tables (0x0A00 - 0x0BFF)
            init_entropy_tables();
            
            // Reserved space for future use (0x0C00 - 0x0FFF)
        end
    endtask
    
    // Initialize MDCT coefficients
    task init_mdct_coefficients;
        integer n;
        real angle, cos_val, sin_val;
        reg [15:0] cos_fixed, sin_fixed;
        begin
            // Generate twiddle factors for MDCT
            // W_N^k = cos(2*pi*k/N) - j*sin(2*pi*k/N)
            for (n = 0; n < 1024; n = n + 1) begin
                angle = 2.0 * 3.14159265359 * n / 1024.0;
                cos_val = $cos(angle);
                sin_val = $sin(angle);
                
                // Convert to Q15 fixed point
                cos_fixed = $rtoi(cos_val * 32767.0);
                sin_fixed = $rtoi(sin_val * 32767.0);
                
                // Store as 32-bit word (cos in upper 16, sin in lower 16)
                rom_memory[n] = {cos_fixed, sin_fixed};
            end
        end
    endtask
    
    // Initialize window functions
    task init_window_functions;
        integer n;
        real window_val;
        reg [31:0] window_fixed;
        begin
            // Generate Hanning window coefficients
            // w(n) = 0.5 * (1 - cos(2*pi*n/(N-1)))
            for (n = 0; n < 512; n = n + 1) begin
                window_val = 0.5 * (1.0 - $cos(2.0 * 3.14159265359 * n / 511.0));
                
                // Convert to Q31 fixed point
                window_fixed = $rtoi(window_val * 2147483647.0);
                
                // Store window coefficient
                rom_memory[1024 + n] = window_fixed;
            end
        end
    endtask
    
    // Initialize quantization tables
    task init_quantization_tables;
        integer i;
        begin
            // Example quantization step sizes (logarithmic scale)
            for (i = 0; i < 512; i = i + 1) begin
                // Quantization step = 2^(i/4 - 16)
                // Stored as Q16 fixed point
                rom_memory[1536 + i] = (1 << 16) >> (16 - (i >> 2));
            end
        end
    endtask
    
    // Initialize psychoacoustic model tables
    task init_psychoacoustic_tables;
        integer i;
        begin
            // Bark scale frequency mapping
            for (i = 0; i < 512; i = i + 1) begin
                // Simple linear mapping for simulation
                rom_memory[2048 + i] = i * 65536;
            end
        end
    endtask
    
    // Initialize entropy coding tables
    task init_entropy_tables;
        integer i;
        begin
            // Huffman code tables
            for (i = 0; i < 512; i = i + 1) begin
                // Simple placeholder values
                rom_memory[2560 + i] = i;
            end
        end
    endtask
    
    // Synthesis directives for ROM inference
    // synthesis translate_off
    // Simulation checks
    always @(posedge clk) begin
        // Address range check
        if (ren && (addr >= 4096)) begin
            $display("ERROR: ROM address out of range: %h at time %t", addr, $time);
        end
    end
    // synthesis translate_on

endmodule

//******************************************************************************
// Coefficient ROM Memory Map
//
// Address Range: 0x0000 - 0x0FFF (4096 words)
//
// 0x0000-0x03FF: MDCT twiddle factors (1024 complex coefficients)
//                Format: {cos[15:0], sin[15:0]} in Q15
//
// 0x0400-0x05FF: Window functions (512 coefficients)
//                Hanning window coefficients in Q31
//
// 0x0600-0x07FF: Quantization tables (512 entries)
//                Quantization step sizes in Q16
//
// 0x0800-0x09FF: Psychoacoustic model tables (512 entries)
//                Bark scale mapping and masking thresholds
//
// 0x0A00-0x0BFF: Entropy coding tables (512 entries)
//                Huffman codes and probability tables
//
// 0x0C00-0x0FFF: Reserved for future use (1024 entries)
//
//****************************************************************************** 