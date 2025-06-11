# 比特流打包模块设计文档

## 1. 模块概述

### 1.1 功能描述
比特流打包模块是LC3plus编码器的最后一级处理单元，负责将熵编码输出的压缩比特流组织成符合LC3plus标准的比特流格式。该模块处理帧头信息、辅助数据、CRC校验、比特填充，并提供完整的LC3plus兼容输出。

### 1.2 主要特性
- **标准化格式**: 完全符合LC3plus比特流规范
- **帧结构组织**: 自动生成帧头、有效载荷和帧尾结构
- **CRC保护**: 计算并添加循环冗余校验码
- **比特填充**: 自动填充到字节边界对齐
- **元数据嵌入**: 支持编码参数和辅助信息
- **多通道支持**: 处理单声道和立体声比特流格式

## 2. 端口定义

### 2.1 端口列表

```verilog
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
```

### 2.2 端口详细说明

| 端口名 | 方向 | 位宽 | 描述 |
|--------|------|------|------|
| `clk` | Input | 1 | 系统时钟，100-200MHz |
| `rst_n` | Input | 1 | 异步复位，低有效 |
| `frame_duration` | Input | 2 | 帧长配置 (2.5/5/10ms) |
| `channel_mode` | Input | 1 | 通道模式配置 |
| `target_bitrate` | Input | 8 | 目标比特率，单位kbps |
| `sample_rate` | Input | 16 | 采样率，单位Hz |
| `enable` | Input | 1 | 模块使能控制 |
| `entropy_valid` | Input | 1 | 熵编码数据有效标志 |
| `entropy_bits` | Input | 32 | 编码后的比特流数据 |
| `entropy_bit_count` | Input | 6 | 当前输入的有效比特数 |
| `entropy_frame_end` | Input | 1 | 熵编码帧结束标志 |
| `output_byte` | Output | 8 | 输出字节数据 |
| `frame_start` | Output | 1 | 帧开始标志 |
| `frame_complete` | Output | 1 | 帧完成标志 |
| `frame_size_bytes` | Output | 16 | 当前帧大小，字节数 |
| `bytes_packed` | Output | 16 | 已打包的字节数 |
| `crc_value` | Output | 8 | CRC-8校验值 |

## 3. LC3plus比特流格式

### 3.1 帧结构组织

```
LC3plus帧格式:
+------------------+
| 帧头 (Frame Header)|  2-4字节
+------------------+
| 有效载荷 (Payload)|  N字节
+------------------+
| CRC校验 (CRC)     |  1字节
+------------------+
| 填充 (Padding)    |  0-7比特
+------------------+
```

### 3.2 帧头格式

```verilog
// LC3plus帧头结构 (16-32比特)
typedef struct packed {
    logic [1:0]  sync_word;      // 同步字 (10b)
    logic [2:0]  frame_type;     // 帧类型 (000=音频帧)
    logic [1:0]  sample_rate_idx; // 采样率索引
    logic [1:0]  frame_len_idx;  // 帧长索引  
    logic [3:0]  bitrate_idx;    // 比特率索引
    logic        channel_config; // 通道配置
    logic [2:0]  reserved;       // 保留位
    logic        crc_present;    // CRC存在标志
} lc3plus_frame_header_t;
```

### 3.3 元数据字段

| 字段名 | 位宽 | 描述 |
|--------|------|------|
| 比特率控制 | 8 | 动态比特率调整信息 |
| 频带限制 | 4 | 有效频带范围 |
| 噪声填充 | 1 | 噪声填充使能标志 |
| 全局增益 | 8 | 全局增益调整值 |
| 预留扩展 | N | 未来扩展字段 |

## 4. 算法实现

### 4.1 比特流缓冲管理

```
1. 比特流收集:
   for each entropy_block:
       bit_buffer[write_pos:write_pos+bit_count] = entropy_bits
       write_pos += bit_count
       
2. 字节对齐:
   while (write_pos % 8 != 0):
       bit_buffer[write_pos] = 0  // 填充零比特
       write_pos += 1
       
3. 字节输出:
   for byte_idx = 0 to (write_pos / 8 - 1):
       output_byte = bit_buffer[byte_idx*8 +: 8]
```

### 4.2 CRC-8计算

基于LC3plus标准的CRC-8多项式：`x^8 + x^2 + x^1 + 1`

```verilog
// CRC-8计算函数
function [7:0] crc8_update;
    input [7:0] crc_current;
    input [7:0] data_byte;
    
    reg [7:0] crc_temp;
    integer i;
    begin
        crc_temp = crc_current ^ data_byte;
        for (i = 0; i < 8; i = i + 1) begin
            if (crc_temp[7]) begin
                crc_temp = (crc_temp << 1) ^ 8'h07;  // 多项式0x07
            end else begin
                crc_temp = crc_temp << 1;
            end
        end
        crc8_update = crc_temp;
    end
endfunction
```

### 4.3 帧头生成算法

```verilog
// 帧头编码函数
function [31:0] encode_frame_header;
    input [1:0] frame_duration;
    input [7:0] bitrate;
    input [15:0] sample_rate;
    input channel_mode;
    
    reg [1:0] sync_word;
    reg [2:0] frame_type;
    reg [1:0] sr_idx, fl_idx;
    reg [3:0] br_idx;
    begin
        // 同步字
        sync_word = 2'b10;
        
        // 帧类型
        frame_type = 3'b000;  // 音频帧
        
        // 采样率索引
        case (sample_rate)
            16'd8000:  sr_idx = 2'b00;
            16'd16000: sr_idx = 2'b01;
            16'd24000: sr_idx = 2'b10;
            16'd48000: sr_idx = 2'b11;
            default:   sr_idx = 2'b11;
        endcase
        
        // 帧长索引
        fl_idx = frame_duration;
        
        // 比特率索引映射
        br_idx = bitrate[3:0];
        
        // 组装帧头
        encode_frame_header = {
            sync_word, frame_type, sr_idx, 
            fl_idx, br_idx, channel_mode, 
            3'b000, 1'b1  // 保留位和CRC标志
        };
    end
endfunction
```

## 5. 量化规则

### 5.1 数据格式定义

| 信号 | 格式 | 范围 | 描述 |
|------|------|------|------|
| 比特流数据 | 二进制 | - | 输入压缩比特 |
| 字节数据 | 8位整数 | [0, 255] | 输出字节 |
| CRC值 | 8位整数 | [0, 255] | 校验和 |
| 帧大小 | 16位整数 | [1, 65535] | 字节计数 |
| 比特位置 | 16位整数 | [0, 65535] | 比特级索引 |

### 5.2 比特操作函数

```verilog
// 比特提取函数
function [7:0] extract_byte;
    input [255:0] bit_buffer;
    input [7:0] byte_offset;
    
    reg [7:0] start_bit;
    begin
        start_bit = byte_offset * 8;
        extract_byte = bit_buffer[start_bit +: 8];
    end
endfunction

// 比特插入函数
function [255:0] insert_bits;
    input [255:0] buffer;
    input [31:0] data;
    input [7:0] start_pos;
    input [5:0] bit_count;
    
    reg [255:0] temp_buffer;
    integer i;
    begin
        temp_buffer = buffer;
        for (i = 0; i < bit_count; i = i + 1) begin
            temp_buffer[start_pos + i] = data[i];
        end
        insert_bits = temp_buffer;
    end
endfunction
```

## 6. 存储器映射

### 6.1 比特流缓冲器分配

**基地址**: 0xA00 (比特流打包工作区，512 words)

| 地址范围 | 大小 | 用途 |
|----------|------|------|
| 0xA00-0xA7F | 128 words | 输入比特流缓冲 |
| 0xA80-0xABF | 64 words | 帧头缓冲 |
| 0xAC0-0xADF | 32 words | 元数据缓冲 |
| 0xAE0-0xAFF | 32 words | CRC计算缓冲 |
| 0xB00-0xB7F | 128 words | 输出字节缓冲 |
| 0xB80-0xBBF | 64 words | 比特位置表 |
| 0xBC0-0xBDF | 32 words | 配置参数缓冲 |
| 0xBE0-0xBFF | 32 words | 临时工作缓冲 |

### 6.2 配置ROM映射

**基地址**: 0x400 (配置表ROM)

| 地址范围 | 大小 | 用途 |
|----------|------|------|
| 0x400-0x42F | 48 words | 采样率配置表 |
| 0x430-0x45F | 48 words | 比特率映射表 |
| 0x460-0x47F | 32 words | 帧长配置表 |
| 0x480-0x49F | 32 words | CRC查找表 |

## 7. 状态机设计

### 7.1 主状态机

```verilog
typedef enum logic [2:0] {
    IDLE               = 3'b000,    // 空闲状态
    HEADER_GENERATE    = 3'b001,    // 生成帧头
    PAYLOAD_COLLECT    = 3'b010,    // 收集有效载荷
    CRC_CALCULATE      = 3'b011,    // 计算CRC
    BYTE_OUTPUT        = 3'b100,    // 字节输出
    FRAME_COMPLETE     = 3'b101,    // 帧完成
    ERROR              = 3'b110     // 错误状态
} packing_state_t;
```

### 7.2 状态转换条件

```
IDLE → HEADER_GENERATE:       enable && entropy_valid
HEADER_GENERATE → PAYLOAD_COLLECT: 帧头生成完成
PAYLOAD_COLLECT → CRC_CALCULATE: entropy_frame_end
CRC_CALCULATE → BYTE_OUTPUT:     CRC计算完成
BYTE_OUTPUT → FRAME_COMPLETE:    所有字节输出完成
FRAME_COMPLETE → IDLE:           帧处理完成确认
任意状态 → ERROR:                错误条件
ERROR → IDLE:                    复位或错误清除
```

## 8. 性能规格

### 8.1 时序要求

| 参数 | 数值 | 单位 | 说明 |
|------|------|------|------|
| 最大频率 | 200 | MHz | 满足实时处理需求 |
| 处理延时 | 64 | 周期 | 最大打包处理周期 |
| 输入带宽 | 32 | 比特/周期 | 熵编码输入速率 |
| 输出带宽 | 8 | 比特/周期 | 字节输出速率 |

### 8.2 资源估算

| 资源类型 | 数量 | 说明 |
|----------|------|------|
| LUT4等效 | 2,000 | 比特操作和控制逻辑 |
| 触发器 | 1,500 | 状态寄存器和缓冲 |
| 乘法器 | 0 | 无需硬件乘法器 |
| SRAM | 2KB | 比特流和输出缓冲 |
| ROM | 1KB | 配置和查找表 |

### 8.3 功耗分析

| 工作模式 | 功耗 | 说明 |
|----------|------|------|
| 活跃处理 | 5mW | 100MHz时钟频率 |
| 待机模式 | 1mW | 时钟门控 |
| 关闭模式 | <0.2mW | 电源门控 |

## 9. 比特流格式兼容性

### 9.1 LC3plus标准兼容

- **版本支持**: LC3plus v1.0规范
- **比特率范围**: 16-320 kbps
- **采样率**: 8/16/24/48 kHz
- **帧长**: 2.5/5/10 ms
- **通道模式**: 单声道/立体声

### 9.2 错误处理

```verilog
// 比特流完整性检查
always @(posedge clk) begin
    if (current_state == CRC_CALCULATE) begin
        // 检查帧大小是否合理
        if (bytes_packed > max_frame_size) begin
            error_flag <= ERROR_FRAME_TOO_LARGE;
        end
        
        // 检查比特流对齐
        if (bit_count % 8 != 0) begin
            error_flag <= ERROR_ALIGNMENT;
        end
        
        // 验证CRC
        if (calculated_crc != expected_crc) begin
            error_flag <= ERROR_CRC_MISMATCH;
        end
    end
end

// 错误恢复机制
always @(posedge clk) begin
    if (error_flag != NO_ERROR) begin
        case (error_flag)
            ERROR_FRAME_TOO_LARGE: begin
                // 截断帧到最大允许大小
                bytes_packed <= max_frame_size;
            end
            
            ERROR_ALIGNMENT: begin
                // 强制字节对齐
                force_byte_alignment <= 1'b1;
            end
            
            ERROR_CRC_MISMATCH: begin
                // 重新计算CRC
                recalculate_crc <= 1'b1;
            end
        endcase
    end
end
```

## 10. 验证策略

### 10.1 功能验证

- **比特流格式**: 与LC3plus参考编码器输出对比
- **CRC校验**: 验证错误检测能力
- **字节对齐**: 确保输出字节边界正确
- **帧大小**: 验证帧大小计算准确性

### 10.2 性能验证

- **实时性测试**: 验证处理延时满足要求
- **吞吐量测试**: 验证最大数据处理能力
- **功耗测试**: 各工作模式功耗测量
- **兼容性测试**: 多种配置下的格式兼容性

### 10.3 测试用例

```verilog
// 测试用例1: 标准音频帧
initial begin
    frame_duration = 2'b01;     // 5ms
    target_bitrate = 8'd64;     // 64 kbps
    sample_rate = 16'd48000;    // 48 kHz
    channel_mode = 1'b0;        // 单声道
    
    // 发送测试熵编码数据
    repeat(20) begin
        entropy_valid = 1'b1;
        entropy_bits = $random;
        entropy_bit_count = 6'd32;
        @(posedge clk);
    end
    
    entropy_frame_end = 1'b1;
    @(posedge clk);
    entropy_frame_end = 1'b0;
    
    // 等待处理完成
    wait(frame_complete);
    
    // 验证输出
    assert(bytes_packed > 0) else $error("No bytes packed");
    assert(crc_value != 8'h00) else $error("Invalid CRC");
end

// 测试用例2: CRC错误检测
initial begin
    // 故意引入错误
    force internal_crc_error = 1'b1;
    
    // 发送数据并检查错误标志
    send_test_frame();
    wait(error_flag == ERROR_CRC_MISMATCH);
    
    // 验证错误恢复
    release internal_crc_error;
    wait(error_flag == NO_ERROR);
end

// 测试用例3: 比特率适应性
initial begin
    for (int br = 16; br <= 320; br += 16) begin
        target_bitrate = br;
        send_test_frame();
        wait(frame_complete);
        
        // 验证输出帧大小符合比特率
        expected_size = (br * frame_duration_ms) / 8;
        assert(bytes_packed == expected_size)
        else $error("Frame size mismatch at %d kbps", br);
    end
end
```

---

**文档版本**: v1.0  
**创建日期**: 2024-06-11  
**作者**: Audio Codec Design Team  
**审核状态**: 待审核 