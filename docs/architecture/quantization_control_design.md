# 量化控制模块设计文档

## 1. 模块概述

### 1.1 功能描述
量化控制模块是LC3plus编码器的第四级处理单元，负责根据频谱分析结果对MDCT系数进行智能量化。该模块实现自适应量化步长控制、比特分配算法、感知质量优化等功能，确保在目标比特率约束下达到最优的感知质量。

### 1.2 主要特性
- **自适应量化**: 基于掩蔽阈值的动态量化步长调整
- **比特分配**: 全局比特率控制和频带间比特分配优化
- **噪声整形**: 量化噪声的感知优化分布
- **率失真优化**: 在比特率和失真度间寻找最优平衡点
- **预测控制**: 基于历史帧的量化参数预测和平滑
- **防溢出保护**: 比特流大小的动态监控和调整

## 2. 端口定义

### 2.1 端口列表

```verilog
module quantization_control (
    // 系统信号
    input                       clk,
    input                       rst_n,
    
    // 配置接口
    input       [1:0]           frame_duration,     // 帧长配置
    input                       channel_mode,       // 通道模式
    input       [7:0]           target_bitrate,     // 目标比特率 (16-320 kbps)
    input       [4:0]           quality_mode,       // 质量模式 (0-31)
    input                       enable,             // 模块使能
    
    // 输入数据接口 (来自频谱分析)
    input                       spectral_valid,     // 频谱分析数据有效
    input       [15:0]          spectral_envelope,  // 频谱包络
    input       [15:0]          masking_threshold,  // 掩蔽阈值
    input       [15:0]          noise_shaping,      // 噪声整形参数
    input       [9:0]           band_index,         // 频带索引
    output                      spectral_ready,     // 可接收频谱数据
    
    // MDCT系数输入接口
    input                       mdct_valid,         // MDCT系数有效
    input       [15:0]          mdct_real,          // MDCT系数实部
    input       [15:0]          mdct_imag,          // MDCT系数虚部
    input       [9:0]           mdct_index,         // 系数索引
    output                      mdct_ready,         // 可接收MDCT系数
    
    // 输出数据接口 (到熵编码)
    output                      output_valid,       // 输出数据有效
    output      [15:0]          quantized_coeff,    // 量化后系数
    output      [7:0]           quantization_step,  // 量化步长
    output      [3:0]           scale_factor,       // 缩放因子
    output      [9:0]           coeff_index,        // 系数索引
    input                       output_ready,       // 下游就绪信号
    
    // 存储器接口 (工作缓冲器)
    output                      mem_req_valid,      // 存储器请求有效
    output      [11:0]          mem_req_addr,       // 存储器地址
    output      [31:0]          mem_req_wdata,      // 写数据
    output                      mem_req_wen,        // 写使能
    input                       mem_req_ready,      // 存储器就绪
    input       [31:0]          mem_req_rdata,      // 读数据
    
    // 量化表ROM接口
    output                      qtable_req_valid,   // 量化表请求有效
    output      [9:0]           qtable_req_addr,    // 量化表地址
    input       [31:0]          qtable_req_data,    // 量化表数据
    input                       qtable_req_ready,   // 量化表就绪
    
    // 状态输出
    output                      quant_busy,         // 量化忙碌状态
    output                      frame_done,         // 帧量化完成
    output      [15:0]          bits_used,          // 已使用比特数
    output      [15:0]          distortion_metric,  // 失真度量
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
| `quality_mode` | Input | 5 | 质量模式 (0=最低质量, 31=最高质量) |
| `enable` | Input | 1 | 模块使能控制 |
| `spectral_valid` | Input | 1 | 频谱分析结果有效 |
| `spectral_envelope` | Input | 16 | 频谱包络，Q8.8格式 |
| `masking_threshold` | Input | 16 | 掩蔽阈值，Q8.8格式 |
| `noise_shaping` | Input | 16 | 噪声整形参数，Q1.15格式 |
| `quantized_coeff` | Output | 16 | 量化后系数，整数 |
| `quantization_step` | Output | 8 | 量化步长，Q4.4格式 |
| `scale_factor` | Output | 4 | 缩放因子指数 |
| `bits_used` | Output | 16 | 当前帧使用的比特数 |
| `distortion_metric` | Output | 16 | 量化失真度量 |

## 3. 算法实现

### 3.1 比特分配算法

基于Lagrange乘数法的最优比特分配：

```
1. 全局比特预算计算:
   frame_bits = target_bitrate * frame_duration / 1000
   
2. 频带重要性评估:
   importance[b] = spectral_envelope[b] / masking_threshold[b]
   
3. 初始比特分配:
   bits[b] = floor(frame_bits * importance[b] / sum(importance))
   
4. 迭代优化:
   for iter = 1 to max_iterations:
       compute distortion for each band
       reallocate bits from low-distortion to high-distortion bands
       if (total_bits <= frame_bits) break
```

### 3.2 量化步长计算

结合感知模型的自适应量化：

```
1. 基础量化步长:
   base_step = masking_threshold[b] / spectral_envelope[b]
   
2. 比特率调整:
   bitrate_factor = sqrt(target_bits / allocated_bits[b])
   
3. 质量模式调整:
   quality_factor = 2^(quality_mode / 6.0)
   
4. 最终量化步长:
   quant_step[b] = base_step * bitrate_factor / quality_factor
```

### 3.3 系数量化

均匀量化器实现：

```
1. 归一化:
   normalized_coeff = mdct_coeff / scale_factor
   
2. 量化:
   quantized_index = round(normalized_coeff / quant_step)
   
3. 量化范围限制:
   if (quantized_index > MAX_QUANT_INDEX)
       quantized_index = MAX_QUANT_INDEX
   if (quantized_index < -MAX_QUANT_INDEX)
       quantized_index = -MAX_QUANT_INDEX
   
4. 重构:
   reconstructed_coeff = quantized_index * quant_step * scale_factor
```

### 3.4 噪声整形

基于频域噪声整形的量化优化：

```
1. 噪声功率谱密度计算:
   noise_psd[k] = |quantized_coeff[k] - original_coeff[k]|²
   
2. 整形滤波器设计:
   shaping_filter[k] = noise_shaping[bark_band[k]]
   
3. 加权量化误差:
   weighted_error[k] = noise_psd[k] * shaping_filter[k]
   
4. 量化步长调整:
   if (weighted_error[k] > threshold)
       reduce quantization_step for band[k]
   else
       increase quantization_step for band[k]
```

## 4. 量化规则

### 4.1 数据格式定义

| 信号 | 格式 | 范围 | 描述 |
|------|------|------|------|
| MDCT系数 | Q1.15 | [-1, 1) | 输入频域系数 |
| 量化步长 | Q4.4 | [0, 16) | 量化参数 |
| 量化索引 | 整数 | [-2048, 2047] | 量化后的整数值 |
| 缩放因子 | 整数 | [0, 15] | 2的幂次缩放 |
| 比特分配 | 整数 | [0, 255] | 每频带比特数 |
| 失真度量 | Q8.8 | [0, 256) | 量化失真 |

### 4.2 量化精度控制

```verilog
// 量化函数
function [15:0] quantize_coeff;
    input [15:0] mdct_coeff;
    input [7:0] quant_step;
    input [3:0] scale_factor;
    
    reg [31:0] scaled_coeff;
    reg [31:0] step_size;
    reg [15:0] quant_index;
    begin
        // 缩放系数: coeff / 2^scale_factor
        scaled_coeff = mdct_coeff;
        if (scale_factor > 0) begin
            scaled_coeff = scaled_coeff / (1 << scale_factor);
        end
        
        // 量化步长转换为线性值
        step_size = {quant_step[7:4], quant_step[3:0], 16'h0};
        
        // 量化: round(scaled_coeff / step_size)
        if (scaled_coeff >= 0) begin
            quant_index = (scaled_coeff + step_size/2) / step_size;
        end else begin
            quant_index = (scaled_coeff - step_size/2) / step_size;
        end
        
        // 范围限制
        if (quant_index > 2047) quant_index = 2047;
        if (quant_index < -2048) quant_index = -2048;
        
        quantize_coeff = quant_index;
    end
endfunction

// 反量化函数
function [15:0] dequantize_coeff;
    input [15:0] quant_index;
    input [7:0] quant_step;
    input [3:0] scale_factor;
    
    reg [31:0] step_size;
    reg [31:0] reconstructed;
    begin
        // 量化步长转换
        step_size = {quant_step[7:4], quant_step[3:0], 16'h0};
        
        // 重构: quant_index * step_size * 2^scale_factor
        reconstructed = quant_index * step_size;
        if (scale_factor > 0) begin
            reconstructed = reconstructed * (1 << scale_factor);
        end
        
        // 截取到16位
        dequantize_coeff = reconstructed[15:0];
    end
endfunction
```

## 5. 存储器映射

### 5.1 工作缓冲器分配

**基地址**: 0x600 (量化控制工作区，512 words)

| 地址范围 | 大小 | 用途 |
|----------|------|------|
| 0x600-0x67F | 128 words | 频谱分析结果缓冲 |
| 0x680-0x6FF | 128 words | MDCT系数缓冲 |
| 0x700-0x73F | 64 words | 量化步长表 |
| 0x740-0x75F | 32 words | 比特分配表 |
| 0x760-0x77F | 32 words | 缩放因子表 |
| 0x780-0x79F | 32 words | 失真度量缓冲 |
| 0x7A0-0x7BF | 32 words | 历史统计信息 |
| 0x7C0-0x7FF | 64 words | 临时计算缓冲 |

### 5.2 量化表ROM映射

**基地址**: 0x000 (量化表ROM)

| 地址范围 | 大小 | 用途 |
|----------|------|------|
| 0x000-0x0FF | 256 words | 标准量化表 |
| 0x100-0x1FF | 256 words | 高质量量化表 |
| 0x200-0x2FF | 256 words | 低比特率量化表 |
| 0x300-0x3FF | 256 words | 比特分配查找表 |

## 6. 状态机设计

### 6.1 主状态机

```verilog
typedef enum logic [2:0] {
    IDLE              = 3'b000,    // 空闲状态
    SPECTRAL_COLLECT  = 3'b001,    // 收集频谱分析结果
    MDCT_COLLECT      = 3'b010,    // 收集MDCT系数
    BIT_ALLOCATION    = 3'b011,    // 比特分配计算
    QUANTIZATION      = 3'b100,    // 系数量化
    RATE_CONTROL      = 3'b101,    // 码率控制
    OUTPUT_GEN        = 3'b110,    // 输出生成
    ERROR             = 3'b111     // 错误状态
} quant_state_t;
```

### 6.2 状态转换条件

```
IDLE → SPECTRAL_COLLECT:      enable && spectral_valid
SPECTRAL_COLLECT → MDCT_COLLECT: 频谱数据收集完成
MDCT_COLLECT → BIT_ALLOCATION: MDCT系数收集完成
BIT_ALLOCATION → QUANTIZATION: 比特分配完成
QUANTIZATION → RATE_CONTROL:   量化完成
RATE_CONTROL → OUTPUT_GEN:     码率控制完成
OUTPUT_GEN → IDLE:             输出完成
任意状态 → ERROR:               错误条件
ERROR → IDLE:                   复位或错误清除
```

## 7. 性能规格

### 7.1 时序要求

| 参数 | 数值 | 单位 | 说明 |
|------|------|------|------|
| 最大频率 | 200 | MHz | 满足实时处理需求 |
| 处理延时 | 640 | 周期 | 最大量化处理周期 |
| 输入带宽 | 1 | 系数/周期 | MDCT系数输入速率 |
| 输出带宽 | 1 | 系数/周期 | 量化系数输出速率 |

### 7.2 资源估算

| 资源类型 | 数量 | 说明 |
|----------|------|------|
| LUT4等效 | 10,000 | 包含算术和控制逻辑 |
| 触发器 | 6,000 | 流水线寄存器 |
| 乘法器 | 6 | 量化和比特分配计算 |
| 除法器 | 2 | 量化步长计算 |
| SRAM | 2KB | 工作缓冲器分配 |
| ROM | 4KB | 量化表存储 |

### 7.3 功耗分析

| 工作模式 | 功耗 | 说明 |
|----------|------|------|
| 活跃处理 | 20mW | 100MHz时钟频率 |
| 待机模式 | 4mW | 时钟门控 |
| 关闭模式 | <1mW | 电源门控 |

## 8. 比特率控制

### 8.1 动态比特分配

```verilog
// 比特预算计算
function [15:0] calculate_frame_bits;
    input [7:0] target_bitrate;  // kbps
    input [1:0] frame_duration;
    reg [31:0] frame_bits;
    begin
        case (frame_duration)
            2'b00: frame_bits = target_bitrate * 25 / 10;  // 2.5ms
            2'b01: frame_bits = target_bitrate * 5;        // 5ms  
            2'b10: frame_bits = target_bitrate * 10;       // 10ms
            default: frame_bits = target_bitrate * 10;
        endcase
        calculate_frame_bits = frame_bits[15:0];
    end
endfunction

// 比特分配更新
always @(posedge clk) begin
    if (current_state == BIT_ALLOCATION) begin
        for (int i = 0; i < num_bands; i++) begin
            // 计算频带重要性
            importance[i] = spectral_envelope[i] * 256 / 
                           (masking_threshold[i] + 1);
            
            // 初始比特分配
            bit_allocation[i] = frame_bits * importance[i] / 
                               total_importance;
        end
    end
end
```

### 8.2 码率控制循环

```verilog
// 码率控制状态机
always @(posedge clk) begin
    case (rate_control_state)
        RC_INIT: begin
            used_bits <= 16'h0;
            rate_control_state <= RC_QUANTIZE;
        end
        
        RC_QUANTIZE: begin
            // 执行量化
            if (quantization_done) begin
                rate_control_state <= RC_COUNT_BITS;
            end
        end
        
        RC_COUNT_BITS: begin
            // 统计使用的比特数
            used_bits <= used_bits + current_coeff_bits;
            if (all_coeffs_counted) begin
                rate_control_state <= RC_ADJUST;
            end
        end
        
        RC_ADJUST: begin
            // 调整量化参数
            if (used_bits > target_bits + tolerance) begin
                // 增加量化步长，减少比特数
                global_quant_step <= global_quant_step + 1;
                rate_control_state <= RC_QUANTIZE;
            end else if (used_bits < target_bits - tolerance) begin
                // 减少量化步长，增加比特数
                global_quant_step <= global_quant_step - 1;
                rate_control_state <= RC_QUANTIZE;
            end else begin
                rate_control_state <= RC_DONE;
            end
        end
        
        RC_DONE: begin
            rate_control_done <= 1'b1;
        end
    endcase
end
```

## 9. 质量控制

### 9.1 失真度量

```verilog
// SNR计算
function [15:0] calculate_snr;
    input [15:0] original_coeff;
    input [15:0] quantized_coeff;
    reg [31:0] signal_power;
    reg [31:0] noise_power;
    reg [31:0] snr_ratio;
    begin
        signal_power = original_coeff * original_coeff;
        noise_power = (original_coeff - quantized_coeff) * 
                     (original_coeff - quantized_coeff);
        
        if (noise_power == 0) begin
            calculate_snr = 16'hFFFF;  // 无限大SNR
        end else begin
            snr_ratio = signal_power * 256 / noise_power;
            calculate_snr = snr_ratio[15:0];
        end
    end
endfunction

// 感知加权失真
function [15:0] perceptual_distortion;
    input [15:0] quantization_error;
    input [15:0] masking_threshold;
    reg [31:0] weighted_error;
    begin
        weighted_error = quantization_error * quantization_error;
        weighted_error = weighted_error / (masking_threshold + 1);
        perceptual_distortion = weighted_error[15:0];
    end
endfunction
```

### 9.2 自适应量化

```verilog
// 量化步长自适应调整
always @(posedge clk) begin
    if (current_state == QUANTIZATION) begin
        for (int i = 0; i < num_coeffs; i++) begin
            // 计算当前量化误差
            quant_error = mdct_coeff[i] - dequantized_coeff[i];
            
            // 感知加权
            weighted_error = perceptual_distortion(quant_error, 
                                                  masking_threshold[bark_band[i]]);
            
            // 自适应调整
            if (weighted_error > error_threshold) begin
                // 减少量化步长，提高质量
                quant_step[bark_band[i]] <= quant_step[bark_band[i]] - 1;
            end else if (weighted_error < error_threshold / 4) begin
                // 增加量化步长，节省比特
                quant_step[bark_band[i]] <= quant_step[bark_band[i]] + 1;
            end
        end
    end
end
```

## 10. 验证策略

### 10.1 算法验证

- **比特率精度**: 验证输出比特率与目标比特率的偏差
- **质量评估**: 主观质量和客观失真度量验证
- **码率控制**: 不同比特率下的控制精度测试
- **边界条件**: 极值输入的量化行为验证

### 10.2 性能验证

- **实时性测试**: 最坏情况处理延时验证
- **收敛性测试**: 码率控制循环的收敛速度
- **稳定性测试**: 长时间运行的参数稳定性
- **资源使用**: 存储器和计算资源使用验证

### 10.3 测试用例

```verilog
// 测试用例1: 固定比特率测试
initial begin
    target_bitrate = 128;  // 128 kbps
    quality_mode = 16;     // 中等质量
    
    // 输入标准测试音频的MDCT系数
    for (int frame = 0; frame < 100; frame++) begin
        // 发送一帧数据
        send_mdct_frame(test_audio_frame[frame]);
        
        // 验证输出比特率
        wait(frame_done);
        assert(bits_used <= target_bits * 1.1 && 
               bits_used >= target_bits * 0.9)
        else $error("Bitrate out of tolerance");
    end
end

// 测试用例2: 质量模式测试
initial begin
    target_bitrate = 64;   // 64 kbps
    
    for (int quality = 0; quality < 32; quality++) begin
        quality_mode = quality;
        send_test_frame();
        wait(frame_done);
        
        // 验证质量递增
        if (quality > 0) begin
            assert(distortion_metric <= prev_distortion)
            else $warning("Quality not improving");
        end
        prev_distortion = distortion_metric;
    end
end
```

---

**文档版本**: v1.0  
**创建日期**: 2024-06-11  
**作者**: Audio Codec Design Team  
**审核状态**: 待审核 