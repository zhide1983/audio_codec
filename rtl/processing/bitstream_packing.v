//=============================================================================
// 比特流打包模块 (Bitstream Packing Module)
// 
// 功能：将熵编码输出组织成符合LC3plus标准的比特流格式
// 作者：Audio Codec Design Team
// 版本：v1.0
// 日期：2024-06-11
//=============================================================================

module bitstream_packing (
    // 系统信号
    input                       clk,
    input                       rst_n,
    
    // 配置接口
    input       [1:0]           frame_duration,     // 帧长配置
    input                       channel_mode,       // 通道模式
    input       [7:0]           target_bitrate,     // 目标比特率
    input       [15:0]          sample_rate,        // 采样率
    input                       enable,             // 模块使能
    
    // 输入数据接口 (来自熵编码)
    input                       entropy_valid,      // 熵编码数据有效
    input       [31:0]          entropy_bits,       // 编码比特流
    input       [5:0]           entropy_bit_count,  // 有效比特数
    input                       entropy_frame_end,  // 帧结束标志
    output                      entropy_ready,      // 可接收熵编码数据
    
    // 输出数据接口 (最终比特流)
    output                      output_valid,       // 输出数据有效
    output      [7:0]           output_byte,        // 输出字节数据
    output                      frame_start,        // 帧开始标志
    output                      frame_complete,     // 帧完成标志
    output      [15:0]          frame_size_bytes,   // 帧大小(字节)
    input                       output_ready,       // 下游就绪信号
    
    // 存储器接口 (比特流缓冲)
    output                      mem_req_valid,      // 存储器请求有效
    output      [11:0]          mem_req_addr,       // 存储器地址
    output      [31:0]          mem_req_wdata,      // 写数据
    output                      mem_req_wen,        // 写使能
    input                       mem_req_ready,      // 存储器就绪
    input       [31:0]          mem_req_rdata,      // 读数据
    
    // 状态输出
    output                      packing_busy,       // 打包忙碌状态
    output                      frame_done,         // 帧处理完成
    output      [15:0]          bytes_packed,       // 已打包字节数
    output      [7:0]           crc_value,          // CRC校验值
    output      [31:0]          debug_info          // 调试信息
);

//=============================================================================
// 参数定义
//=============================================================================

// 帧长度配置
localparam FRAME_160_SAMPLES  = 2'b00;   // 2.5ms @ 64kHz
localparam FRAME_320_SAMPLES  = 2'b01;   // 5ms @ 64kHz  
localparam FRAME_640_SAMPLES  = 2'b10;   // 10ms @ 64kHz

// 状态机状态
localparam IDLE               = 3'b000;    // 空闲状态
localparam HEADER_GENERATE    = 3'b001;    // 生成帧头
localparam PAYLOAD_COLLECT    = 3'b010;    // 收集有效载荷
localparam CRC_CALCULATE      = 3'b011;    // 计算CRC
localparam BYTE_OUTPUT        = 3'b100;    // 字节输出
localparam FRAME_COMPLETE     = 3'b101;    // 帧完成
localparam ERROR              = 3'b110;    // 错误状态

// 存储器地址映射
localparam BIT_BUFFER_BASE    = 12'hA00;  // 输入比特流缓冲
localparam HEADER_BUFFER_BASE = 12'hA80;  // 帧头缓冲
localparam OUTPUT_BUFFER_BASE = 12'hB00;  // 输出字节缓冲
localparam TEMP_BUFFER_BASE   = 12'hBE0;  // 临时工作缓冲

// CRC多项式
localparam CRC8_POLY = 8'h07;             // x^8 + x^2 + x^1 + 1

// LC3plus帧格式常数
localparam SYNC_WORD = 2'b10;
localparam FRAME_TYPE_AUDIO = 3'b000;

// 错误代码
localparam NO_ERROR           = 4'h0;
localparam ERROR_FRAME_TOO_LARGE    = 4'h1;
localparam ERROR_ALIGNMENT          = 4'h2;
localparam ERROR_CRC_MISMATCH       = 4'h3;
localparam ERROR_INVALID_CONFIG     = 4'h4;

//=============================================================================
// 信号声明
//=============================================================================

// 状态机信号
reg     [2:0]           current_state, next_state;
reg                     state_changed;

// 配置信号
reg     [15:0]          max_frame_bytes;       // 最大帧字节数
reg     [1:0]           sample_rate_idx;       // 采样率索引
reg     [3:0]           bitrate_idx;           // 比特率索引

// 比特流缓冲
reg     [255:0]         bit_buffer;            // 比特流缓冲器
reg     [8:0]           bit_write_pos;         // 写入位置 (比特)
reg     [8:0]           bit_read_pos;          // 读取位置 (比特)
reg     [8:0]           total_bits;            // 总比特数

// 帧头处理
reg     [31:0]          frame_header;          // 帧头数据
reg     [7:0]           header_bytes;          // 帧头字节数
reg                     header_generated;      // 帧头生成标志

// 输出控制
reg     [15:0]          byte_output_count;     // 输出字节计数
reg     [7:0]           current_output_byte;   // 当前输出字节
reg                     output_valid_reg;      // 输出有效寄存器
reg     [7:0]           output_byte_buffer[0:255]; // 输出字节缓冲

// CRC计算
reg     [7:0]           crc_accumulator;       // CRC累加器
reg                     crc_done;              // CRC计算完成
reg     [15:0]          crc_byte_count;        // CRC字节计数

// 存储器访问
reg                     mem_req_valid_reg;
reg     [11:0]          mem_req_addr_reg;
reg     [31:0]          mem_req_wdata_reg;
reg                     mem_req_wen_reg;
wire                    mem_access_done;

// 错误处理
reg     [3:0]           error_flag;
reg                     error_recovery;

// 性能统计
reg     [15:0]          bytes_packed_reg;      // 已打包字节数
reg     [31:0]          packing_cycles;        // 打包周期数
reg                     frame_start_reg;       // 帧开始寄存器

//=============================================================================
// 组合逻辑
//=============================================================================

// 配置解码
always @(*) begin
    // 采样率索引映射
    case (sample_rate)
        16'd8000:  sample_rate_idx = 2'b00;
        16'd16000: sample_rate_idx = 2'b01;
        16'd24000: sample_rate_idx = 2'b10;
        16'd48000: sample_rate_idx = 2'b11;
        default:   sample_rate_idx = 2'b11;
    endcase
    
    // 比特率索引映射
    if (target_bitrate <= 8'd32) begin
        bitrate_idx = 4'h2;
    end else if (target_bitrate <= 8'd64) begin
        bitrate_idx = 4'h4;
    end else if (target_bitrate <= 8'd128) begin
        bitrate_idx = 4'h8;
    end else begin
        bitrate_idx = 4'hC;
    end
    
    // 最大帧字节数计算
    case (frame_duration)
        FRAME_160_SAMPLES: max_frame_bytes = (target_bitrate * 16'd10) / 16'd320; // 2.5ms
        FRAME_320_SAMPLES: max_frame_bytes = (target_bitrate * 16'd20) / 16'd320; // 5ms
        FRAME_640_SAMPLES: max_frame_bytes = (target_bitrate * 16'd40) / 16'd320; // 10ms
        default:           max_frame_bytes = (target_bitrate * 16'd20) / 16'd320;
    endcase
end

// 存储器接口
assign mem_req_valid = mem_req_valid_reg;
assign mem_req_addr  = mem_req_addr_reg;
assign mem_req_wdata = mem_req_wdata_reg;
assign mem_req_wen   = mem_req_wen_reg;
assign mem_access_done = mem_req_valid_reg & mem_req_ready;

// 输入握手
assign entropy_ready = (current_state == PAYLOAD_COLLECT) && (bit_write_pos < 9'd240);

// 输出接口
assign output_valid     = output_valid_reg;
assign output_byte      = current_output_byte;
assign frame_start      = frame_start_reg;
assign frame_complete   = (current_state == FRAME_COMPLETE);
assign frame_size_bytes = bytes_packed_reg;

// 状态输出
assign packing_busy = (current_state != IDLE);
assign frame_done   = (current_state == FRAME_COMPLETE);
assign bytes_packed = bytes_packed_reg;
assign crc_value    = crc_accumulator;

// 调试信息
assign debug_info = {
    error_flag[3:0],           // [31:28] 错误代码
    current_state[2:0],        // [27:25] 当前状态
    bit_write_pos[8:0],        // [24:16] 比特写位置
    byte_output_count[15:0]    // [15:0]  输出字节计数
};

//=============================================================================
// 主状态机
//=============================================================================

// 状态寄存器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;
        state_changed <= 1'b0;
    end else begin
        current_state <= next_state;
        state_changed <= (current_state != next_state);
    end
end

// 状态转换逻辑
always @(*) begin
    next_state = current_state;
    
    case (current_state)
        IDLE: begin
            if (enable && entropy_valid) begin
                next_state = HEADER_GENERATE;
            end
        end
        
        HEADER_GENERATE: begin
            if (header_generated) begin
                next_state = PAYLOAD_COLLECT;
            end
        end
        
        PAYLOAD_COLLECT: begin
            if (entropy_frame_end) begin
                next_state = CRC_CALCULATE;
            end
        end
        
        CRC_CALCULATE: begin
            if (crc_done) begin
                next_state = BYTE_OUTPUT;
            end
        end
        
        BYTE_OUTPUT: begin
            if (byte_output_count >= bytes_packed_reg && output_ready) begin
                next_state = FRAME_COMPLETE;
            end
        end
        
        FRAME_COMPLETE: begin
            next_state = IDLE;
        end
        
        ERROR: begin
            if (error_recovery) begin
                next_state = IDLE;
            end
        end
        
        default: begin
            next_state = ERROR;
        end
    endcase
    
    // 错误条件检查
    if (error_flag != NO_ERROR) begin
        next_state = ERROR;
    end
end

//=============================================================================
// 帧头生成
//=============================================================================

// 帧头编码函数
function [31:0] encode_frame_header;
    input [1:0] frame_dur;
    input [7:0] bitrate;
    input [15:0] samp_rate;
    input ch_mode;
    
    reg [1:0] sync_word;
    reg [2:0] frame_type;
    reg [1:0] sr_idx, fl_idx;
    reg [3:0] br_idx;
    begin
        // 同步字
        sync_word = SYNC_WORD;
        
        // 帧类型
        frame_type = FRAME_TYPE_AUDIO;
        
        // 采样率索引
        case (samp_rate)
            16'd8000:  sr_idx = 2'b00;
            16'd16000: sr_idx = 2'b01;
            16'd24000: sr_idx = 2'b10;
            16'd48000: sr_idx = 2'b11;
            default:   sr_idx = 2'b11;
        endcase
        
        // 帧长索引
        fl_idx = frame_dur;
        
        // 比特率索引
        if (bitrate <= 8'd32) begin
            br_idx = 4'h2;
        end else if (bitrate <= 8'd64) begin
            br_idx = 4'h4;
        end else if (bitrate <= 8'd128) begin
            br_idx = 4'h8;
        end else begin
            br_idx = 4'hC;
        end
        
        // 组装帧头 (16比特)
        encode_frame_header = {
            16'h0000,          // 高16位保留
            sync_word,         // [15:14] 同步字
            frame_type,        // [13:11] 帧类型
            sr_idx,            // [10:9]  采样率索引
            fl_idx,            // [8:7]   帧长索引
            br_idx,            // [6:3]   比特率索引
            ch_mode,           // [2]     通道配置
            2'b01              // [1:0]   CRC标志和保留
        };
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_header <= 32'h0000;
        header_bytes <= 8'd0;
        header_generated <= 1'b0;
        frame_start_reg <= 1'b0;
    end else begin
        case (current_state)
            IDLE: begin
                header_generated <= 1'b0;
                frame_start_reg <= 1'b0;
            end
            
            HEADER_GENERATE: begin
                if (!header_generated) begin
                    // 生成帧头
                    frame_header <= encode_frame_header(
                        frame_duration, 
                        target_bitrate, 
                        sample_rate, 
                        channel_mode
                    );
                    header_bytes <= 8'd2;  // LC3plus标准帧头为2字节
                    header_generated <= 1'b1;
                    frame_start_reg <= 1'b1;
                end
            end
            
            default: begin
                frame_start_reg <= 1'b0;
            end
        endcase
    end
end

//=============================================================================
// 有效载荷收集
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bit_buffer <= 256'h0;
        bit_write_pos <= 9'd0;
        total_bits <= 9'd0;
    end else begin
        case (current_state)
            HEADER_GENERATE: begin
                // 初始化比特缓冲器，写入帧头
                bit_buffer[15:0] <= frame_header[15:0];
                bit_write_pos <= 9'd16;  // 帧头占16比特
                total_bits <= 9'd16;
            end
            
            PAYLOAD_COLLECT: begin
                if (entropy_valid && entropy_ready) begin
                    // 写入熵编码比特
                    if (bit_write_pos + entropy_bit_count <= 9'd256) begin
                        // 比特插入
                        for (integer i = 0; i < 32; i = i + 1) begin
                            if (i < entropy_bit_count) begin
                                bit_buffer[bit_write_pos + i] <= entropy_bits[i];
                            end
                        end
                        bit_write_pos <= bit_write_pos + entropy_bit_count;
                        total_bits <= total_bits + entropy_bit_count;
                    end
                end
            end
            
            CRC_CALCULATE: begin
                // 字节对齐填充
                while (total_bits[2:0] != 3'b000) begin
                    bit_buffer[total_bits] <= 1'b0;
                    total_bits <= total_bits + 9'd1;
                end
            end
            
            default: begin
                if (state_changed && current_state == PAYLOAD_COLLECT) begin
                    // 重置比特缓冲器
                    bit_write_pos <= 9'd0;
                    total_bits <= 9'd0;
                end
            end
        endcase
    end
end

//=============================================================================
// CRC计算
//=============================================================================

// CRC-8更新函数
function [7:0] crc8_update;
    input [7:0] crc_current;
    input [7:0] data_byte;
    
    reg [7:0] crc_temp;
    integer i;
    begin
        crc_temp = crc_current ^ data_byte;
        for (i = 0; i < 8; i = i + 1) begin
            if (crc_temp[7]) begin
                crc_temp = (crc_temp << 1) ^ CRC8_POLY;
            end else begin
                crc_temp = crc_temp << 1;
            end
        end
        crc8_update = crc_temp;
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        crc_accumulator <= 8'hFF;  // CRC初始值
        crc_done <= 1'b0;
        crc_byte_count <= 16'd0;
    end else begin
        case (current_state)
            HEADER_GENERATE: begin
                crc_accumulator <= 8'hFF;
                crc_done <= 1'b0;
                crc_byte_count <= 16'd0;
            end
            
            CRC_CALCULATE: begin
                if (!crc_done) begin
                    // 计算所有字节的CRC
                    if (crc_byte_count * 16'd8 < total_bits) begin
                        // 提取当前字节
                        reg [7:0] current_byte;
                        current_byte = bit_buffer[(crc_byte_count * 16'd8) +: 8];
                        
                        // 更新CRC
                        crc_accumulator <= crc8_update(crc_accumulator, current_byte);
                        crc_byte_count <= crc_byte_count + 16'd1;
                    end else begin
                        // CRC计算完成，添加到比特流
                        bit_buffer[(total_bits) +: 8] <= crc_accumulator;
                        total_bits <= total_bits + 9'd8;
                        crc_done <= 1'b1;
                    end
                end
            end
        endcase
    end
end

//=============================================================================
// 字节输出
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        byte_output_count <= 16'd0;
        current_output_byte <= 8'h00;
        output_valid_reg <= 1'b0;
        bytes_packed_reg <= 16'd0;
    end else begin
        case (current_state)
            CRC_CALCULATE: begin
                if (crc_done) begin
                    // 计算总字节数
                    bytes_packed_reg <= (total_bits + 9'd7) >> 3;  // 向上取整
                    byte_output_count <= 16'd0;
                end
            end
            
            BYTE_OUTPUT: begin
                if (output_ready && byte_output_count < bytes_packed_reg) begin
                    // 提取当前字节
                    current_output_byte <= bit_buffer[(byte_output_count * 16'd8) +: 8];
                    output_valid_reg <= 1'b1;
                    byte_output_count <= byte_output_count + 16'd1;
                end else begin
                    output_valid_reg <= 1'b0;
                end
            end
            
            default: begin
                if (current_state != BYTE_OUTPUT) begin
                    output_valid_reg <= 1'b0;
                end
                
                if (state_changed && current_state == BYTE_OUTPUT) begin
                    byte_output_count <= 16'd0;
                end
            end
        endcase
    end
end

//=============================================================================
// 性能统计和错误处理
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        packing_cycles <= 32'd0;
        error_flag <= NO_ERROR;
        error_recovery <= 1'b0;
    end else begin
        // 性能统计
        if (packing_busy) begin
            packing_cycles <= packing_cycles + 32'd1;
        end else begin
            packing_cycles <= 32'd0;
        end
        
        // 错误检测
        if (current_state == PAYLOAD_COLLECT) begin
            if (bytes_packed_reg > max_frame_bytes) begin
                error_flag <= ERROR_FRAME_TOO_LARGE;
            end
        end
        
        if (current_state == CRC_CALCULATE) begin
            if (total_bits[2:0] != 3'b000) begin
                error_flag <= ERROR_ALIGNMENT;
            end
        end
        
        // 错误恢复
        if (current_state == ERROR) begin
            error_recovery <= 1'b1;
        end else begin
            error_recovery <= 1'b0;
            if (current_state == IDLE) begin
                error_flag <= NO_ERROR;
            end
        end
    end
end

//=============================================================================
// 存储器访问控制
//=============================================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_req_valid_reg <= 1'b0;
        mem_req_addr_reg <= 12'd0;
        mem_req_wdata_reg <= 32'd0;
        mem_req_wen_reg <= 1'b0;
    end else begin
        // 默认情况下关闭请求
        mem_req_valid_reg <= 1'b0;
        
        case (current_state)
            BYTE_OUTPUT: begin
                // 存储输出字节缓冲
                if (byte_output_count < bytes_packed_reg) begin
                    mem_req_valid_reg <= 1'b1;
                    mem_req_addr_reg <= OUTPUT_BUFFER_BASE + {4'd0, byte_output_count[7:0]};
                    mem_req_wdata_reg <= {24'd0, current_output_byte};
                    mem_req_wen_reg <= 1'b1;
                end
            end
        endcase
    end
end

endmodule 