# RTL设计规则与约束

## 1. 语法和编码规范

### 1.1 语言标准
- **强制要求**: 使用Verilog 2001语法标准
- **禁止使用**: SystemVerilog特性、Verilog 2005以上特性
- **编码风格**: 统一的命名规范和代码格式

### 1.2 禁用操作符
- **禁用左移操作符**: `<<` (左移)
- **禁用右移操作符**: `>>` (逻辑右移), `>>>` (算术右移)
- **替代方案**: 使用乘法、除法或位拼接操作

#### 示例
```verilog
// 禁止使用
data_out = data_in << 2;        // ❌ 禁用左移
data_out = data_in >> 1;        // ❌ 禁用右移

// 推荐方案
data_out = data_in * 4;         // ✅ 用乘法替代左移2位
data_out = {1'b0, data_in[31:1]}; // ✅ 用位拼接替代右移1位
```

### 1.3 循环语句约束
- **禁止**: 非常数循环次数的for语句
- **允许**: 编译时常数循环的for语句
- **用途**: 仅用于参数生成和初始化

#### 示例
```verilog
// 禁止使用
for (i = 0; i < variable_count; i = i + 1) begin  // ❌ 变量循环次数
    // ...
end

// 允许使用
parameter ARRAY_SIZE = 16;
for (i = 0; i < ARRAY_SIZE; i = i + 1) begin     // ✅ 常数循环次数
    // ...
end
```

## 2. 存储器设计约束

### 2.1 SRAM端口限制
- **强制要求**: 所有SRAM只能使用单端口
- **禁止使用**: 双端口SRAM、多端口存储器
- **访问管理**: 通过仲裁器实现多模块访问

#### 存储器模块标准模板
```verilog
module single_port_ram (
    input               clk,
    input   [ADDR_W-1:0] addr,      // 单一地址端口
    input   [DATA_W-1:0] wdata,     // 写数据
    input               wen,        // 写使能
    input               ren,        // 读使能
    output  [DATA_W-1:0] rdata      // 读数据
);
```

### 2.2 存储器访问仲裁
- **仲裁器**: 实现多模块对单端口SRAM的时分访问
- **优先级**: 配置优先级策略
- **带宽**: 合理规划访问带宽分配

## 3. 顶层硬化配置

### 3.1 配置机制
- **编译时配置**: 使用`define`和`generate`语句
- **优化目标**: 通过缩减配置优化面积和功耗
- **兼容性**: 保持接口兼容性

### 3.2 采样率配置
```verilog
// 顶层硬化配置 - 采样率
`define MAX_SAMPLE_RATE_48K     // 支持最高48kHz
// `define MAX_SAMPLE_RATE_96K  // 支持最高96kHz (可选)

generate
    `ifdef MAX_SAMPLE_RATE_96K
        parameter MAX_SAMPLE_RATE = 96000;
        parameter MDCT_MAX_LENGTH = 1920;  // 96kHz@20ms
    `else
        parameter MAX_SAMPLE_RATE = 48000;
        parameter MDCT_MAX_LENGTH = 960;   // 48kHz@20ms
    `endif
endgenerate
```

### 3.3 音频精度配置
```verilog
// 顶层硬化配置 - 音频精度
`define SUPPORT_16BIT           // 支持16bit采样
`define SUPPORT_24BIT           // 支持24bit采样

generate
    `ifdef SUPPORT_24BIT
        parameter MAX_SAMPLE_WIDTH = 24;
        parameter INTERNAL_WIDTH = 32;     // 内部处理位宽
    `elsif SUPPORT_16BIT
        parameter MAX_SAMPLE_WIDTH = 16;
        parameter INTERNAL_WIDTH = 24;     // 内部处理位宽
    `endif
endgenerate
```

## 4. LC3plus规范细化

### 4.1 帧时长配置
- **支持帧长**: 2.5ms, 5ms, 10ms
- **配置方式**: 寄存器运行时配置
- **默认值**: 10ms

```verilog
// 帧时长寄存器定义
// REG_FRAME_DURATION [1:0]
// 00: 2.5ms
// 01: 5ms  
// 10: 10ms
// 11: 保留

parameter FRAME_2P5MS = 2'b00;
parameter FRAME_5MS   = 2'b01; 
parameter FRAME_10MS  = 2'b10;
```

### 4.2 通道数配置
- **支持通道**: 单通道(单声道), 双通道(立体声)
- **配置方式**: 寄存器运行时配置
- **默认值**: 单通道

```verilog
// 通道数寄存器定义
// REG_CHANNEL_CONFIG [0]
// 0: 单通道 (单声道)
// 1: 双通道 (立体声)

parameter MONO_MODE   = 1'b0;
parameter STEREO_MODE = 1'b1;
```

### 4.3 其他可配置特性

#### 4.3.1 比特率配置
- **范围**: 16kbps - 320kbps (per channel)
- **步长**: 2kbps
- **配置**: 寄存器运行时配置

#### 4.3.2 带宽控制
- **支持带宽**: 4kHz, 8kHz, 12kHz, 16kHz, 20kHz, 24kHz
- **自适应**: 支持自适应带宽控制
- **配置**: 寄存器配置或自动检测

#### 4.3.3 错误保护模式
- **模式**: OFF, ZERO, LOW, MEDIUM, HIGH
- **功能**: Reed-Solomon错误保护编码
- **配置**: 寄存器运行时配置

## 5. 设计约束示例

### 5.1 合规的移位实现
```verilog
// 用于2的幂次倍数的乘除法
function [31:0] multiply_by_4;
    input [29:0] data_in;
    begin
        multiply_by_4 = {data_in, 2'b00};  // 等效于左移2位
    end
endfunction

function [30:0] divide_by_2;
    input [31:0] data_in;
    begin
        divide_by_2 = data_in[31:1];       // 等效于右移1位
    end
endfunction
```

### 5.2 单端口存储器仲裁器
```verilog
module memory_arbiter (
    input               clk,
    input               rst_n,
    
    // 请求端口A
    input               req_a_valid,
    input   [11:0]      req_a_addr,
    input   [31:0]      req_a_wdata,
    input               req_a_wen,
    output  [31:0]      req_a_rdata,
    output              req_a_ready,
    
    // 请求端口B  
    input               req_b_valid,
    input   [11:0]      req_b_addr,
    input   [31:0]      req_b_wdata,
    input               req_b_wen,
    output  [31:0]      req_b_rdata,
    output              req_b_ready,
    
    // 单端口SRAM接口
    output  [11:0]      mem_addr,
    output  [31:0]      mem_wdata,
    output              mem_wen,
    output              mem_ren,
    input   [31:0]      mem_rdata
);
```

### 5.3 参数化配置生成
```verilog
// 基于硬化配置的参数生成
generate
    if (MAX_SAMPLE_RATE == 96000) begin : gen_high_fs
        localparam FRAME_SAMPLES_MAX = 2400;  // 96k@25ms
        localparam MDCT_STAGES = 11;          // log2(2048)
    end else begin : gen_normal_fs
        localparam FRAME_SAMPLES_MAX = 1200;  // 48k@25ms  
        localparam MDCT_STAGES = 10;          // log2(1024)
    end
endgenerate
```

## 6. 验证要求

### 6.1 设计规则检查
- **语法检查**: 确保符合Verilog 2001标准
- **操作符检查**: 禁用移位操作符的静态检查
- **循环检查**: 验证for循环的常数性

### 6.2 功能验证
- **单端口访问**: 验证存储器访问的正确性
- **仲裁逻辑**: 验证多端口仲裁的公平性和性能
- **配置验证**: 验证各种硬化配置的功能

### 6.3 综合验证
- **面积评估**: 不同配置下的面积对比
- **时序分析**: 关键路径和时序约束
- **功耗分析**: 各配置的功耗评估

## 7. 工具和流程

### 7.1 静态检查工具
- **语法检查**: iverilog -Wall
- **规则检查**: 自定义脚本检查移位操作符
- **代码审查**: 人工审查关键设计

### 7.2 仿真验证
- **单元测试**: 每个模块的独立验证
- **集成测试**: 系统级功能验证
- **回归测试**: 自动化回归测试框架

### 7.3 综合流程
- **配置管理**: 不同硬化配置的构建脚本
- **约束文件**: SDC约束和时序要求
- **报告生成**: 自动化的分析报告

---

**文档版本**: v1.0  
**生效日期**: 2024-06-11  
**适用范围**: 音频编解码器项目全部RTL设计 