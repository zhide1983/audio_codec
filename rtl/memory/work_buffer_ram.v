//============================================================================
// Module Name  : work_buffer_ram.v
// Description  : 单端口工作缓冲存储器 - 用于临时计算结果存储
//                符合RTL设计规则：仅使用单端口SRAM
// Author       : Audio Codec Design Team
// Date         : 2024-06-11
// Version      : v2.0 - 单端口版本
//============================================================================

`timescale 1ns / 1ps

module work_buffer_ram (
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
// 工作区域定义 - 用于不同处理阶段
//============================================================================
// 地址空间分配:
// 0x000-0x3FF: MDCT变换工作区 (1024 words = 4KB)
// 0x400-0x7FF: 频谱分析工作区 (1024 words = 4KB)  
// 0x800-0xBFF: 量化控制工作区 (1024 words = 4KB)
// 0xC00-0xFFF: 熵编码工作区   (1024 words = 4KB)

parameter MDCT_BASE_ADDR      = 12'h000;  // MDCT变换基地址
parameter SPECTRAL_BASE_ADDR  = 12'h400;  // 频谱分析基地址
parameter QUANT_BASE_ADDR     = 12'h800;  // 量化控制基地址
parameter ENTROPY_BASE_ADDR   = 12'hC00;  // 熵编码基地址

parameter WORK_AREA_SIZE      = 1024;     // 每个工作区大小

//============================================================================
// 仿真支持
//============================================================================
`ifdef SIMULATION
    // 工作区内存转储功能
    task dump_work_area;
        input [1:0] area_select;  // 0:MDCT, 1:Spectral, 2:Quant, 3:Entropy
        input [8*32-1:0] filename;
        
        reg [11:0] start_addr;
        reg [11:0] end_addr;
        integer file_handle;
        integer addr_idx;
        
        begin
            case (area_select)
                2'b00: begin
                    start_addr = MDCT_BASE_ADDR;
                    end_addr = MDCT_BASE_ADDR + WORK_AREA_SIZE - 1;
                    $display("Dumping MDCT work area to %s", filename);
                end
                2'b01: begin
                    start_addr = SPECTRAL_BASE_ADDR;
                    end_addr = SPECTRAL_BASE_ADDR + WORK_AREA_SIZE - 1;
                    $display("Dumping Spectral work area to %s", filename);
                end
                2'b10: begin
                    start_addr = QUANT_BASE_ADDR;
                    end_addr = QUANT_BASE_ADDR + WORK_AREA_SIZE - 1;
                    $display("Dumping Quantization work area to %s", filename);
                end
                2'b11: begin
                    start_addr = ENTROPY_BASE_ADDR;
                    end_addr = ENTROPY_BASE_ADDR + WORK_AREA_SIZE - 1;
                    $display("Dumping Entropy work area to %s", filename);
                end
            endcase
            
            file_handle = $fopen(filename, "w");
            if (file_handle != 0) begin
                for (addr_idx = start_addr; addr_idx <= end_addr; addr_idx = addr_idx + 1) begin
                    $fwrite(file_handle, "@%04X %08X\n", addr_idx, memory_array[addr_idx]);
                end
                $fclose(file_handle);
                $display("Work area dump completed");
            end else begin
                $display("Error: Cannot open file %s for writing", filename);
            end
        end
    endtask
    
    // 工作区清零功能
    task clear_work_area;
        input [1:0] area_select;
        
        reg [11:0] start_addr;
        integer addr_idx;
        
        begin
            case (area_select)
                2'b00: start_addr = MDCT_BASE_ADDR;
                2'b01: start_addr = SPECTRAL_BASE_ADDR;
                2'b10: start_addr = QUANT_BASE_ADDR;
                2'b11: start_addr = ENTROPY_BASE_ADDR;
            endcase
            
            for (addr_idx = 0; addr_idx < WORK_AREA_SIZE; addr_idx = addr_idx + 1) begin
                memory_array[start_addr + addr_idx] = 32'h0;
            end
            
            $display("Work area %0d cleared", area_select);
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
    
    // 工作区越界检查
    function [1:0] get_work_area;
        input [11:0] address;
        begin
            if (address < SPECTRAL_BASE_ADDR)
                get_work_area = 2'b00;  // MDCT区域
            else if (address < QUANT_BASE_ADDR)
                get_work_area = 2'b01;  // 频谱分析区域
            else if (address < ENTROPY_BASE_ADDR)
                get_work_area = 2'b10;  // 量化控制区域
            else
                get_work_area = 2'b11;  // 熵编码区域
        end
    endfunction
    
    // 性能监控
    reg [31:0] area_access_count[0:3];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            area_access_count[0] <= 32'h0;
            area_access_count[1] <= 32'h0;
            area_access_count[2] <= 32'h0;
            area_access_count[3] <= 32'h0;
        end else if (wen || ren) begin
            area_access_count[get_work_area(addr)] <= 
                area_access_count[get_work_area(addr)] + 1;
        end
    end
`endif

endmodule

//============================================================================
// 工作缓冲器仲裁器 - 用于多模块访问单端口工作存储器
//============================================================================
module work_buffer_arbiter (
    input                       clk,
    input                       rst_n,
    
    // MDCT模块访问接口
    input                       mdct_req_valid,
    input       [11:0]          mdct_req_addr,
    input       [31:0]          mdct_req_wdata,
    input                       mdct_req_wen,
    output                      mdct_req_ready,
    output      [31:0]          mdct_req_rdata,
    
    // 频谱分析模块访问接口
    input                       spec_req_valid,
    input       [11:0]          spec_req_addr,
    input       [31:0]          spec_req_wdata,
    input                       spec_req_wen,
    output                      spec_req_ready,
    output      [31:0]          spec_req_rdata,
    
    // 量化模块访问接口
    input                       quant_req_valid,
    input       [11:0]          quant_req_addr,
    input       [31:0]          quant_req_wdata,
    input                       quant_req_wen,
    output                      quant_req_ready,
    output      [31:0]          quant_req_rdata,
    
    // 熵编码模块访问接口
    input                       entropy_req_valid,
    input       [11:0]          entropy_req_addr,
    input       [31:0]          entropy_req_wdata,
    input                       entropy_req_wen,
    output                      entropy_req_ready,
    output      [31:0]          entropy_req_rdata,
    
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
localparam IDLE    = 3'b000;
localparam MDCT    = 3'b001;
localparam SPEC    = 3'b010;
localparam QUANT   = 3'b011;
localparam ENTROPY = 3'b100;

reg [2:0] arb_state, arb_next;
reg [31:0] rdata_reg;

//============================================================================
// 优先级仲裁 - 按处理顺序优先
//============================================================================
always @(*) begin
    arb_next = arb_state;
    
    case (arb_state)
        IDLE: begin
            // 按处理流水线顺序优先
            if (mdct_req_valid) begin
                arb_next = MDCT;
            end else if (spec_req_valid) begin
                arb_next = SPEC;
            end else if (quant_req_valid) begin
                arb_next = QUANT;
            end else if (entropy_req_valid) begin
                arb_next = ENTROPY;
            end
        end
        
        MDCT: begin
            if (!mdct_req_valid) arb_next = IDLE;
        end
        
        SPEC: begin
            if (!spec_req_valid) arb_next = IDLE;
        end
        
        QUANT: begin
            if (!quant_req_valid) arb_next = IDLE;
        end
        
        ENTROPY: begin
            if (!entropy_req_valid) arb_next = IDLE;
        end
        
        default: arb_next = IDLE;
    endcase
end

//============================================================================
// 状态机时序逻辑
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
// 输出多路选择
//============================================================================
assign mem_addr  = (arb_state == MDCT)    ? mdct_req_addr    :
                   (arb_state == SPEC)    ? spec_req_addr    :
                   (arb_state == QUANT)   ? quant_req_addr   :
                   (arb_state == ENTROPY) ? entropy_req_addr : 12'h0;

assign mem_wdata = (arb_state == MDCT)    ? mdct_req_wdata    :
                   (arb_state == SPEC)    ? spec_req_wdata    :
                   (arb_state == QUANT)   ? quant_req_wdata   :
                   (arb_state == ENTROPY) ? entropy_req_wdata : 32'h0;

assign mem_wen   = (arb_state == MDCT)    ? mdct_req_wen      :
                   (arb_state == SPEC)    ? spec_req_wen      :
                   (arb_state == QUANT)   ? quant_req_wen     :
                   (arb_state == ENTROPY) ? entropy_req_wen   : 1'b0;

assign mem_ren   = (arb_state == MDCT)    ? !mdct_req_wen     :
                   (arb_state == SPEC)    ? !spec_req_wen     :
                   (arb_state == QUANT)   ? !quant_req_wen    :
                   (arb_state == ENTROPY) ? !entropy_req_wen  : 1'b0;

// 就绪信号
assign mdct_req_ready    = (arb_state == MDCT);
assign spec_req_ready    = (arb_state == SPEC);
assign quant_req_ready   = (arb_state == QUANT);
assign entropy_req_ready = (arb_state == ENTROPY);

// 读数据输出
assign mdct_req_rdata    = (arb_state == MDCT)    ? rdata_reg : 32'h0;
assign spec_req_rdata    = (arb_state == SPEC)    ? rdata_reg : 32'h0;
assign quant_req_rdata   = (arb_state == QUANT)   ? rdata_reg : 32'h0;
assign entropy_req_rdata = (arb_state == ENTROPY) ? rdata_reg : 32'h0;

endmodule 