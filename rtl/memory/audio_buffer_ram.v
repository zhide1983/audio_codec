//============================================================================
// Module Name  : audio_buffer_ram.v
// Description  : 单端口音频缓冲存储器 - 用于PCM数据缓冲
//                符合RTL设计规则：仅使用单端口SRAM
// Author       : Audio Codec Design Team
// Date         : 2024-06-11
// Version      : v2.0 - 单端口版本
//============================================================================

`timescale 1ns / 1ps

module audio_buffer_ram (
    // 时钟和复位
    input                       clk,
    input                       rst_n,
    
    // 单端口存储器接口
    input       [11:0]          addr,           // 地址: 12位 = 4096地址 x 32bit = 16KB
    input       [31:0]          wdata,          // 写数据
    input                       wen,            // 写使能
    input                       ren,            // 读使能  
    output reg  [31:0]          rdata           // 读数据
);

//============================================================================
// 参数定义
//============================================================================
parameter ADDR_WIDTH = 12;      // 地址宽度: 4K addresses
parameter DATA_WIDTH = 32;      // 数据宽度: 32-bit
parameter DEPTH      = 4096;    // 存储深度: 4K words = 16KB

//============================================================================
// 内部信号定义
//============================================================================
// 存储器阵列
reg [DATA_WIDTH-1:0] memory_array [0:DEPTH-1];

// 地址寄存器 (用于改善时序)
reg [ADDR_WIDTH-1:0] addr_reg;

//============================================================================
// 地址寄存器
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        addr_reg <= {ADDR_WIDTH{1'b0}};
    end else if (wen || ren) begin
        addr_reg <= addr;
    end
end

//============================================================================
// 写操作
//============================================================================
always @(posedge clk) begin
    if (wen && !ren) begin  // 写优先，避免读写冲突
        memory_array[addr] <= wdata;
    end
end

//============================================================================
// 读操作
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rdata <= {DATA_WIDTH{1'b0}};
    end else if (ren && !wen) begin  // 读操作，写优先时不读
        rdata <= memory_array[addr];
    end
end

//============================================================================
// 存储器初始化
//============================================================================
integer i;
initial begin
    // 将存储器初始化为0
    for (i = 0; i < DEPTH; i = i + 1) begin
        memory_array[i] = {DATA_WIDTH{1'b0}};
    end
    
    // 输出初始化
    rdata = {DATA_WIDTH{1'b0}};
end

//============================================================================
// 仿真支持
//============================================================================
`ifdef SIMULATION
    // 内存转储功能 (仅用于仿真)
    task dump_memory;
        input [ADDR_WIDTH-1:0] start_addr;
        input [ADDR_WIDTH-1:0] end_addr;
        input [8*32-1:0] filename;
        
        integer file_handle;
        integer addr_idx;
        
        begin
            file_handle = $fopen(filename, "w");
            if (file_handle != 0) begin
                $display("Dumping audio buffer memory [%0d:%0d] to %s", 
                        start_addr, end_addr, filename);
                
                for (addr_idx = start_addr; addr_idx <= end_addr; addr_idx = addr_idx + 1) begin
                    $fwrite(file_handle, "@%04X %08X\n", addr_idx, memory_array[addr_idx]);
                end
                
                $fclose(file_handle);
                $display("Memory dump completed");
            end else begin
                $display("Error: Cannot open file %s for writing", filename);
            end
        end
    endtask
    
    // 内存加载功能 (仅用于仿真)  
    task load_memory;
        input [8*32-1:0] filename;
        
        begin
            $display("Loading audio buffer memory from %s", filename);
            $readmemh(filename, memory_array);
            $display("Memory load completed");
        end
    endtask
`endif

//============================================================================
// 断言和检查 (仅在仿真中有效)
//============================================================================
`ifdef SIMULATION
    // 地址范围检查
    always @(posedge clk) begin
        if ((wen || ren) && (addr >= DEPTH)) begin
            $error("ERROR: Address 0x%X out of range [0:0x%X]", addr, DEPTH-1);
        end
    end
    
    // 读写冲突检查
    always @(posedge clk) begin
        if (wen && ren) begin
            $warning("WARNING: Simultaneous read and write operation at address 0x%X", addr);
        end
    end
    
    // 性能监控
    reg [31:0] read_count, write_count;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_count  <= 32'h0;
            write_count <= 32'h0;
        end else begin
            if (ren && !wen) read_count <= read_count + 1;
            if (wen && !ren) write_count <= write_count + 1;
        end
    end
`endif

endmodule

//============================================================================
// 存储器仲裁器 - 用于多模块访问单端口SRAM
//============================================================================
module audio_buffer_arbiter (
    input                       clk,
    input                       rst_n,
    
    // 编码器访问接口
    input                       enc_req_valid,
    input       [11:0]          enc_req_addr,
    input       [31:0]          enc_req_wdata,
    input                       enc_req_wen,
    output                      enc_req_ready,
    output      [31:0]          enc_req_rdata,
    
    // 解码器访问接口
    input                       dec_req_valid,
    input       [11:0]          dec_req_addr,
    input       [31:0]          dec_req_wdata,
    input                       dec_req_wen,
    output                      dec_req_ready,
    output      [31:0]          dec_req_rdata,
    
    // 单端口存储器接口
    output      [11:0]          mem_addr,
    output      [31:0]          mem_wdata,
    output                      mem_wen,
    output                      mem_ren,
    input       [31:0]          mem_rdata
);

//============================================================================
// 仲裁状态机
//============================================================================
localparam IDLE = 2'b00;
localparam ENC  = 2'b01;  
localparam DEC  = 2'b10;

reg [1:0] arb_state, arb_next;
reg [31:0] rdata_reg;

//============================================================================
// 状态机 - 时序逻辑
//============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        arb_state <= IDLE;
        rdata_reg <= 32'h0;
    end else begin
        arb_state <= arb_next;
        if (mem_ren) begin
            rdata_reg <= mem_rdata;
        end
    end
end

//============================================================================
// 状态机 - 组合逻辑
//============================================================================
always @(*) begin
    arb_next = arb_state;
    
    case (arb_state)
        IDLE: begin
            if (enc_req_valid) begin
                arb_next = ENC;
            end else if (dec_req_valid) begin
                arb_next = DEC;
            end
        end
        
        ENC: begin
            if (!enc_req_valid) begin
                arb_next = IDLE;
            end
        end
        
        DEC: begin
            if (!dec_req_valid) begin
                arb_next = IDLE;
            end
        end
        
        default: arb_next = IDLE;
    endcase
end

//============================================================================
// 输出多路选择
//============================================================================
assign mem_addr  = (arb_state == ENC) ? enc_req_addr  : 
                   (arb_state == DEC) ? dec_req_addr  : 12'h0;
assign mem_wdata = (arb_state == ENC) ? enc_req_wdata : 
                   (arb_state == DEC) ? dec_req_wdata : 32'h0;
assign mem_wen   = (arb_state == ENC) ? enc_req_wen   : 
                   (arb_state == DEC) ? dec_req_wen   : 1'b0;
assign mem_ren   = (arb_state == ENC) ? !enc_req_wen  : 
                   (arb_state == DEC) ? !dec_req_wen  : 1'b0;

// 请求就绪信号
assign enc_req_ready = (arb_state == ENC);
assign dec_req_ready = (arb_state == DEC);

// 读数据输出
assign enc_req_rdata = (arb_state == ENC) ? rdata_reg : 32'h0;
assign dec_req_rdata = (arb_state == DEC) ? rdata_reg : 32'h0;

endmodule

//******************************************************************************
// Memory Map for Audio Buffer RAM
//
// Address Range: 0x0000 - 0x0FFF (4096 words)
//
// 0x0000-0x03FF: Channel 0 PCM buffer (1024 samples)
// 0x0400-0x07FF: Channel 1 PCM buffer (1024 samples)  
// 0x0800-0x0BFF: Channel 2-7 PCM buffers (256 samples each)
// 0x0C00-0x0DFF: Time domain processing intermediate results
// 0x0E00-0x0FFF: General purpose buffer space
//
//****************************************************************************** 