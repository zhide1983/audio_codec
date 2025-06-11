# 频谱分析模块设计文档

## 1. 模块概述

### 1.1 功能描述
频谱分析模块是LC3plus编码器的第三级处理单元，负责对MDCT变换后的频域系数进行分析处理。该模块实现频谱包络估计、声学模型分析、掩蔽阈值计算等关键功能，为后续量化控制提供决策依据。

### 1.2 主要特性
- **频谱包络估计**: 基于Bark尺度的频谱包络计算
- **掩蔽阈值计算**: 同时掩蔽和时间掩蔽分析
- **噪声整形**: 基于感知模型的噪声分布优化
- **带宽检测**: 自适应带宽配置 (4kHz~24kHz)
- **峰值检测**: 频域峰值和谷值分析
- **能量分布**: 各频带能量统计和归一化

## 2. 端口定义

### 2.1 端口列表

```verilog
module spectral_analysis (
    // 系统信号
    input                       clk,
    input                       rst_n,
    
    // 配置接口
    input       [1:0]           frame_duration,     // 帧长配置
    input                       channel_mode,       // 通道模式
    input       [4:0]           bandwidth_config,   // 带宽配置 (4-24kHz)
    input                       enable,             // 模块使能
    
    // 输入数据接口 (来自MDCT变换)
    input                       input_valid,        // 输入数据有效
    input       [15:0]          input_real,         // MDCT系数实部
    input       [15:0]          input_imag,         // MDCT系数虚部
    input       [9:0]           input_index,        // 系数索引
    output                      input_ready,        // 输入就绪信号
    
    // 输出数据接口 (到量化控制)
    output                      output_valid,       // 输出数据有效
    output      [15:0]          spectral_envelope,  // 频谱包络
    output      [15:0]          masking_threshold,  // 掩蔽阈值
    output      [15:0]          noise_shaping,      // 噪声整形参数
    output      [9:0]           band_index,         // 频带索引
    input                       output_ready,       // 下游就绪信号
    
    // 存储器接口 (工作缓冲器)
    output                      mem_req_valid,      // 存储器请求有效
    output      [11:0]          mem_req_addr,       // 存储器地址 
    output      [31:0]          mem_req_wdata,      // 写数据
    output                      mem_req_wen,        // 写使能
    input                       mem_req_ready,      // 存储器就绪
    input       [31:0]          mem_req_rdata,      // 读数据
    
    // Bark尺度系数ROM接口
    output                      bark_req_valid,     // Bark系数请求有效
    output      [7:0]           bark_req_addr,      // Bark系数地址
    input       [31:0]          bark_req_data,      // Bark系数数据
    input                       bark_req_ready,     // Bark系数就绪
    
    // 状态输出
    output                      analysis_busy,      // 分析忙碌状态
    output                      frame_done,         // 帧分析完成
    output      [31:0]          spectral_stats,     // 频谱统计信息
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
| `bandwidth_config` | Input | 5 | 带宽配置 (4-24kHz，1kHz步进) |
| `enable` | Input | 1 | 模块使能控制 |
| `input_valid` | Input | 1 | MDCT系数有效标志 |
| `input_real/imag` | Input | 16 | MDCT系数，Q1.15格式 |
| `input_index` | Input | 10 | MDCT系数索引 |
| `input_ready` | Output | 1 | 可接收输入数据 |
| `spectral_envelope` | Output | 16 | 频谱包络，Q8.8格式 |
| `masking_threshold` | Output | 16 | 掩蔽阈值，Q8.8格式 |
| `noise_shaping` | Output | 16 | 噪声整形参数，Q1.15格式 |
| `band_index` | Output | 10 | 频带索引 |

## 3. 算法实现

### 3.1 频谱包络估计

基于Bark尺度的频谱包络计算：

```
1. MDCT系数功率谱计算:
   P[k] = real[k]² + imag[k]²
   
2. Bark频带映射:
   bark_band = bark_scale_map[k]
   
3. 频带能量累积:
   E[b] = Σ P[k] for k in bark_band[b]
   
4. 包络平滑:
   envelope[b] = α * E[b] + (1-α) * envelope_prev[b]
```

### 3.2 掩蔽阈值计算

结合同时掩蔽和时间掩蔽：

```
1. 同时掩蔽计算:
   SM[b] = envelope[b] * masking_function[b]
   
2. 时间掩蔽计算:
   TM[b] = max(envelope_prev[b] * decay_factor, 
               envelope[b] * forward_factor)
   
3. 全局掩蔽阈值:
   threshold[b] = max(SM[b], TM[b], quiet_threshold[b])
```

### 3.3 噪声整形

基于感知模型的噪声分布：

```
1. 信噪比计算:
   SNR[b] = 10 * log10(envelope[b] / threshold[b])
   
2. 噪声整形权重:
   if SNR[b] > 6dB:
       weight[b] = 1.0              // 强信号，无整形
   else if SNR[b] > 0dB:
       weight[b] = 0.5 + SNR[b]/12  // 中等信号，轻度整形
   else:
       weight[b] = 0.1              // 弱信号，强整形
```

### 3.4 带宽自适应

根据高频能量自动调整带宽：

```
1. 高频能量检测:
   high_freq_energy = Σ envelope[b] for b > 16kHz_band
   
2. 带宽决策:
   if high_freq_energy > threshold_24k:
       bandwidth = 24kHz
   else if high_freq_energy > threshold_16k:
       bandwidth = 16kHz
   else:
       bandwidth = 8kHz
```

## 4. 量化规则

### 4.1 数据格式定义

| 信号 | 格式 | 范围 | 描述 |
|------|------|------|------|
| MDCT系数 | Q1.15 | [-1, 1) | 输入频域系数 |
| 功率谱 | Q16.16 | [0, 65536) | 系数平方和 |
| 频谱包络 | Q8.8 | [0, 256) | 频带能量 |
| 掩蔽阈值 | Q8.8 | [0, 256) | 感知阈值 |
| 噪声整形 | Q1.15 | [0, 1) | 整形权重 |
| 统计信息 | Q16.16 | [0, 65536) | 能量统计 |

### 4.2 数值精度处理

```verilog
// 功率谱计算 - 避免溢出
function [31:0] power_spectrum;
    input [15:0] real_part, imag_part;
    reg [31:0] real_sq, imag_sq;
    begin
        real_sq = real_part * real_part;
        imag_sq = imag_part * imag_part;
        power_spectrum = real_sq + imag_sq;
    end
endfunction

// 对数计算 - 查表实现
function [15:0] log_approx;
    input [31:0] value;
    reg [7:0] lut_index;
    begin
        // 简化的对数逼近
        if (value == 0) begin
            log_approx = 16'h8000;  // -∞ 
        end else begin
            lut_index = value[31:24];  // 取高8位作为索引
            log_approx = log_lut[lut_index];
        end
    end
endfunction
```

## 5. 存储器映射

### 5.1 工作缓冲器分配

**基地址**: 0x400 (频谱分析工作区，512 words)

| 地址范围 | 大小 | 用途 |
|----------|------|------|
| 0x400-0x47F | 128 words | MDCT系数缓冲 |
| 0x480-0x4BF | 64 words | 功率谱缓冲 |
| 0x4C0-0x4DF | 32 words | 频谱包络 |
| 0x4E0-0x4FF | 32 words | 掩蔽阈值 |
| 0x500-0x51F | 32 words | 噪声整形参数 |
| 0x520-0x53F | 32 words | 历史包络 (时间掩蔽) |
| 0x540-0x55F | 32 words | 频带能量统计 |
| 0x560-0x5FF | 160 words | 中间计算缓冲 |

### 5.2 Bark尺度系数ROM

**基地址**: 0x00 (Bark ROM)

| 地址范围 | 大小 | 用途 |
|----------|------|------|
| 0x00-0x3F | 64 words | Bark频带映射表 |
| 0x40-0x7F | 64 words | 掩蔽函数系数 |
| 0x80-0xBF | 64 words | 时间掩蔽衰减系数 |
| 0xC0-0xFF | 64 words | 对数查表LUT |

## 6. 状态机设计

### 6.1 主状态机

```verilog
typedef enum logic [2:0] {
    IDLE           = 3'b000,    // 空闲状态
    INPUT_COLLECT  = 3'b001,    // 收集MDCT系数
    POWER_CALC     = 3'b010,    // 功率谱计算
    BARK_MAPPING   = 3'b011,    // Bark频带映射
    ENVELOPE_EST   = 3'b100,    // 包络估计
    MASKING_CALC   = 3'b101,    // 掩蔽计算
    OUTPUT_GEN     = 3'b110,    // 输出生成
    ERROR          = 3'b111     // 错误状态
} spectral_state_t;
```

### 6.2 状态转换条件

```
IDLE → INPUT_COLLECT:     enable && input_valid
INPUT_COLLECT → POWER_CALC: 系数收集完成
POWER_CALC → BARK_MAPPING: 功率谱计算完成
BARK_MAPPING → ENVELOPE_EST: 频带映射完成
ENVELOPE_EST → MASKING_CALC: 包络估计完成
MASKING_CALC → OUTPUT_GEN: 掩蔽计算完成
OUTPUT_GEN → IDLE:        输出完成
任意状态 → ERROR:          错误条件
ERROR → IDLE:             复位或错误清除
```

## 7. 性能规格

### 7.1 时序要求

| 参数 | 数值 | 单位 | 说明 |
|------|------|------|------|
| 最大频率 | 200 | MHz | 满足实时处理需求 |
| 处理延时 | 320 | 周期 | 最大处理周期数 |
| 输入带宽 | 1 | 系数/周期 | MDCT系数输入速率 |
| 输出带宽 | 1 | 参数/周期 | 分析参数输出速率 |

### 7.2 资源估算

| 资源类型 | 数量 | 说明 |
|----------|------|------|
| LUT4等效 | 8,000 | 包含算术和控制逻辑 |
| 触发器 | 5,000 | 流水线寄存器 |
| 乘法器 | 8 | 功率谱和掩蔽计算 |
| SRAM | 2KB | 工作缓冲器分配 |
| ROM | 1KB | Bark系数存储 |

### 7.3 功耗分析

| 工作模式 | 功耗 | 说明 |
|----------|------|------|
| 活跃处理 | 15mW | 100MHz时钟频率 |
| 待机模式 | 3mW | 时钟门控 |
| 关闭模式 | <0.5mW | 电源门控 |

## 8. 接口协议

### 8.1 输入握手协议

```verilog
// MDCT系数接收
always @(posedge clk) begin
    if (input_valid && input_ready) begin
        mdct_buffer[input_index] <= {input_real, input_imag};
        coefficient_count <= coefficient_count + 1;
    end
end

// 就绪信号控制
assign input_ready = (current_state == INPUT_COLLECT) && 
                     (coefficient_count < max_coefficients) &&
                     mem_req_ready;
```

### 8.2 输出握手协议

```verilog
// 分析结果输出
always @(posedge clk) begin
    if (output_valid && output_ready) begin
        band_index <= band_index + 1;
        if (band_index == max_bands - 1) begin
            frame_done <= 1'b1;
        end
    end
end
```

## 9. 算法流水线

### 9.1 五级流水线架构

```
级1: MDCT系数输入和缓冲
├─ 系数收集
├─ 格式转换
└─ 缓冲管理

级2: 功率谱计算
├─ 复数模长计算
├─ 平方运算
└─ 功率累积

级3: Bark频带映射  
├─ 频率到Bark转换
├─ 频带分组
└─ 能量累积

级4: 包络和掩蔽分析
├─ 频谱包络估计
├─ 掩蔽阈值计算
└─ 时间掩蔽处理

级5: 噪声整形和输出
├─ 噪声整形权重
├─ 参数归一化
└─ 结果输出
```

### 9.2 流水线控制

```verilog
// 流水线使能信号
reg [4:0] pipeline_enable;
reg [4:0] stage_valid;
reg [4:0] stage_ready;

// 级间握手
assign stage_ready[0] = input_ready;
assign stage_ready[1] = stage_valid[0] && mem_req_ready;
assign stage_ready[2] = stage_valid[1] && bark_req_ready;
assign stage_ready[3] = stage_valid[2];
assign stage_ready[4] = stage_valid[3] && output_ready;
```

## 10. 验证策略

### 10.1 算法验证

- **频谱包络测试**: 与Matlab参考模型对比
- **掩蔽模型验证**: 标准测试音频验证
- **噪声整形测试**: 量化噪声分布检查
- **边界条件测试**: 极值输入响应验证

### 10.2 性能验证

- **实时性测试**: 最坏情况延时验证
- **精度测试**: 定点运算精度分析
- **功耗测试**: 各工作模式功耗测量
- **稳定性测试**: 长时间连续运行

### 10.3 测试用例

```verilog
// 测试用例1: 正弦波频谱分析
initial begin
    // 1kHz正弦波MDCT系数
    for (int i = 0; i < 320; i++) begin
        input_real = $rtoi(16384 * $cos(2*3.14159*1000*i/48000));
        input_imag = $rtoi(16384 * $sin(2*3.14159*1000*i/48000));
        input_index = i;
        @(posedge clk);
    end
end

// 测试用例2: 白噪声频谱分析
initial begin
    for (int i = 0; i < 320; i++) begin
        input_real = $random % 32768;
        input_imag = $random % 32768;
        input_index = i;
        @(posedge clk);
    end
end
```

---

**文档版本**: v1.0  
**创建日期**: 2024-06-11  
**作者**: Audio Codec Design Team  
**审核状态**: 待审核 