# 熵编码模块设计文档

## 1. 模块概述

### 1.1 功能描述
熵编码模块是LC3plus编码器的第五级处理单元，负责对量化后的MDCT系数进行无损压缩编码。该模块实现算术编码器，结合自适应概率模型和上下文建模，最大化压缩效率，确保比特流的最优紧凑性。

### 1.2 主要特性
- **算术编码**: 高效的概率编码算法，接近理论压缩极限
- **自适应概率**: 基于历史统计的动态概率模型更新
- **上下文建模**: 利用频谱相关性的多级上下文预测
- **符号分组**: 对量化系数进行游程编码和符号分组优化
- **比特精确控制**: 严格的比特预算管理和溢出保护
- **实时处理**: 低延时的流水线编码实现

## 2. 端口定义

### 2.1 端口列表

```verilog
module entropy_coding (
    // 系统信号
    input                       clk,
    input                       rst_n,
    
    // 配置接口
    input       [1:0]           frame_duration,     // 帧长配置
    input                       channel_mode,       // 通道模式
    input       [7:0]           target_bitrate,     // 目标比特率
    input                       enable,             // 模块使能
    
    // 输入数据接口 (来自量化控制)
    input                       quant_valid,        // 量化数据有效
    input       [15:0]          quantized_coeff,    // 量化后系数
    input       [7:0]           quantization_step,  // 量化步长
    input       [3:0]           scale_factor,       // 缩放因子
    input       [9:0]           coeff_index,        // 系数索引
    output                      quant_ready,        // 可接收量化数据
    
    // 输出数据接口 (到比特流打包)
    output                      output_valid,       // 输出数据有效
    output      [31:0]          encoded_bits,       // 编码后比特流
    output      [5:0]           bit_count,          // 有效比特数 (1-32)
    output                      frame_end,          // 帧结束标志
    input                       output_ready,       // 下游就绪信号
    
    // 存储器接口 (工作缓冲器)
    output                      mem_req_valid,      // 存储器请求有效
    output      [11:0]          mem_req_addr,       // 存储器地址
    output      [31:0]          mem_req_wdata,      // 写数据
    output                      mem_req_wen,        // 写使能
    input                       mem_req_ready,      // 存储器就绪
    input       [31:0]          mem_req_rdata,      // 读数据
    
    // 概率表ROM接口
    output                      prob_req_valid,     // 概率表请求有效
    output      [9:0]           prob_req_addr,      // 概率表地址
    input       [31:0]          prob_req_data,      // 概率表数据
    input                       prob_req_ready,     // 概率表就绪
    
    // 状态输出
    output                      coding_busy,        // 编码忙碌状态
    output                      frame_done,         // 帧编码完成
    output      [15:0]          bits_generated,     // 生成的比特数
    output      [15:0]          compression_ratio,  // 压缩比
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
| `enable` | Input | 1 | 模块使能控制 |
| `quant_valid` | Input | 1 | 量化系数有效标志 |
| `quantized_coeff` | Input | 16 | 量化后系数，有符号整数 |
| `quantization_step` | Input | 8 | 量化步长，Q4.4格式 |
| `scale_factor` | Input | 4 | 缩放因子指数 |
| `coeff_index` | Input | 10 | 系数索引 |
| `encoded_bits` | Output | 32 | 编码后的比特流数据 |
| `bit_count` | Output | 6 | 当前输出的有效比特数 |
| `frame_end` | Output | 1 | 帧编码结束标志 |
| `bits_generated` | Output | 16 | 当前帧生成的总比特数 |
| `compression_ratio` | Output | 16 | 压缩比，Q8.8格式 |

## 3. 算法实现

### 3.1 算术编码原理

算术编码将整个符号序列映射到[0,1)区间内的一个子区间：

```
1. 区间初始化:
   low = 0.0
   high = 1.0
   
2. 符号编码循环:
   for each symbol s:
       range = high - low
       high = low + range * cum_prob[s+1]
       low = low + range * cum_prob[s]
       
3. 归一化处理:
   while (high - low < threshold):
       output most significant bit
       scale intervals
```

### 3.2 自适应概率模型

基于频率统计的动态概率更新：

```
1. 符号频率统计:
   freq[symbol] = freq[symbol] + 1
   total_count = total_count + 1
   
2. 概率计算:
   prob[symbol] = freq[symbol] / total_count
   
3. 累积概率:
   cum_prob[0] = 0
   for i = 1 to num_symbols:
       cum_prob[i] = cum_prob[i-1] + prob[i-1]
       
4. 概率模型自适应:
   if (total_count > MAX_COUNT):
       freq[i] = freq[i] / 2  // 老化处理
       total_count = total_count / 2
```

### 3.3 上下文建模

利用邻近系数的相关性进行预测：

```
1. 上下文提取:
   context = hash(coeff[i-2], coeff[i-1], band_index)
   
2. 多级上下文:
   context_0 = 0                           // 无上下文
   context_1 = coeff[i-1]                  // 一阶上下文
   context_2 = hash(coeff[i-2], coeff[i-1]) // 二阶上下文
   
3. 上下文选择:
   if (context_2_valid && freq[context_2] > threshold):
       use context_2
   else if (context_1_valid && freq[context_1] > threshold):
       use context_1
   else:
       use context_0
```

### 3.4 符号预处理

对量化系数进行符号重组和游程编码：

```
1. 零游程编码:
   run_length = count_consecutive_zeros(coeffs, start_index)
   if (run_length > 0):
       encode_symbol(ZERO_RUN, run_length)
       
2. 非零系数编码:
   for each non-zero coeff:
       sign = (coeff < 0) ? 1 : 0
       magnitude = abs(coeff)
       encode_symbol(SIGN, sign)
       encode_symbol(MAGNITUDE, magnitude)
       
3. 频带结束标记:
   encode_symbol(EOB, band_index)
```

## 4. 量化规则

### 4.1 数据格式定义

| 信号 | 格式 | 范围 | 描述 |
|------|------|------|------|
| 量化系数 | 整数 | [-2048, 2047] | 输入量化值 |
| 概率值 | Q0.16 | [0, 1) | 符号概率 |
| 累积概率 | Q0.16 | [0, 1] | 累积概率分布 |
| 区间边界 | Q0.32 | [0, 1) | 算术编码区间 |
| 频率统计 | 整数 | [0, 65535] | 符号频率计数 |
| 比特流 | 二进制 | - | 输出编码比特 |

### 4.2 定点算术编码实现

```verilog
// 算术编码核心函数
function [63:0] arithmetic_encode;
    input [31:0] low, high;           // 当前区间 (Q0.32)
    input [15:0] cum_prob_low, cum_prob_high; // 累积概率 (Q0.16)
    
    reg [63:0] range;
    reg [63:0] new_low, new_high;
    begin
        // 计算区间范围
        range = high - low;
        
        // 更新区间边界
        new_low = low + ((range * cum_prob_low) >> 16);
        new_high = low + ((range * cum_prob_high) >> 16);
        
        arithmetic_encode = {new_high[31:0], new_low[31:0]};
    end
endfunction

// 归一化处理
function [31:0] normalize_interval;
    input [31:0] low, high;
    input [5:0] scale_count;
    
    reg [31:0] normalized_low, normalized_high;
    begin
        // 左移去除确定的高位比特
        normalized_low = low << scale_count;
        normalized_high = high << scale_count;
        
        normalize_interval = {normalized_high[15:0], normalized_low[15:0]};
    end
endfunction
```

## 5. 存储器映射

### 5.1 工作缓冲器分配

**基地址**: 0x800 (熵编码工作区，512 words)

| 地址范围 | 大小 | 用途 |
|----------|------|------|
| 0x800-0x87F | 128 words | 量化系数缓冲 |
| 0x880-0x8BF | 64 words | 上下文历史缓冲 |
| 0x8C0-0x8FF | 64 words | 符号频率统计表 |
| 0x900-0x93F | 64 words | 累积概率表 |
| 0x940-0x95F | 32 words | 算术编码状态 |
| 0x960-0x97F | 32 words | 输出比特缓冲 |
| 0x980-0x99F | 32 words | 游程编码缓冲 |
| 0x9A0-0x9FF | 96 words | 临时计算缓冲 |

### 5.2 概率表ROM映射

**基地址**: 0x000 (概率表ROM)

| 地址范围 | 大小 | 用途 |
|----------|------|------|
| 0x000-0x0FF | 256 words | 初始概率表 |
| 0x100-0x1FF | 256 words | 上下文概率表 |
| 0x200-0x2FF | 256 words | 游程长度概率表 |
| 0x300-0x3FF | 256 words | 幅度概率表 |

## 6. 状态机设计

### 6.1 主状态机

```verilog
typedef enum logic [2:0] {
    IDLE            = 3'b000,    // 空闲状态
    COEFF_COLLECT   = 3'b001,    // 收集量化系数
    SYMBOL_ANALYSIS = 3'b010,    // 符号分析和预处理
    CONTEXT_MODEL   = 3'b011,    // 上下文建模
    ARITHMETIC_CODE = 3'b100,    // 算术编码
    BIT_OUTPUT      = 3'b101,    // 比特输出
    FRAME_FINISH    = 3'b110,    // 帧结束处理
    ERROR           = 3'b111     // 错误状态
} entropy_state_t;
```

### 6.2 状态转换条件

```
IDLE → COEFF_COLLECT:         enable && quant_valid
COEFF_COLLECT → SYMBOL_ANALYSIS: 系数收集完成
SYMBOL_ANALYSIS → CONTEXT_MODEL: 符号预处理完成
CONTEXT_MODEL → ARITHMETIC_CODE: 上下文建模完成
ARITHMETIC_CODE → BIT_OUTPUT:   编码完成
BIT_OUTPUT → FRAME_FINISH:      比特输出完成
FRAME_FINISH → IDLE:            帧处理完成
任意状态 → ERROR:                错误条件
ERROR → IDLE:                   复位或错误清除
```

## 7. 性能规格

### 7.1 时序要求

| 参数 | 数值 | 单位 | 说明 |
|------|------|------|------|
| 最大频率 | 200 | MHz | 满足实时处理需求 |
| 处理延时 | 320 | 周期 | 最大编码处理周期 |
| 输入带宽 | 1 | 系数/周期 | 量化系数输入速率 |
| 输出带宽 | 32 | 比特/周期 | 编码比特输出速率 |

### 7.2 资源估算

| 资源类型 | 数量 | 说明 |
|----------|------|------|
| LUT4等效 | 5,000 | 包含算术和控制逻辑 |
| 触发器 | 3,000 | 流水线寄存器 |
| 乘法器 | 2 | 概率计算 |
| SRAM | 2KB | 工作缓冲器分配 |
| ROM | 4KB | 概率表存储 |

### 7.3 功耗分析

| 工作模式 | 功耗 | 说明 |
|----------|------|------|
| 活跃处理 | 10mW | 100MHz时钟频率 |
| 待机模式 | 2mW | 时钟门控 |
| 关闭模式 | <0.5mW | 电源门控 |

## 8. 压缩性能

### 8.1 压缩比目标

| 信号类型 | 目标压缩比 | 说明 |
|----------|------------|------|
| 语音信号 | 3.5:1 | 典型语音内容 |
| 音乐信号 | 2.8:1 | 复杂音乐内容 |
| 混合信号 | 3.0:1 | 语音+音乐混合 |
| 静音段 | >10:1 | 背景噪声 |

### 8.2 比特率控制

```verilog
// 动态比特预算管理
always @(posedge clk) begin
    if (current_state == ARITHMETIC_CODE) begin
        // 统计当前使用的比特数
        bits_used <= bits_used + bit_count;
        
        // 检查是否超出预算
        if (bits_used > target_frame_bits) begin
            // 触发比特率控制
            trigger_rate_control <= 1'b1;
        end
        
        // 动态调整编码参数
        if (trigger_rate_control) begin
            // 增加量化步长，减少比特数
            adjust_quantization_step(1);
        end
    end
end

// 压缩比计算
assign compression_ratio = (original_bits * 256) / bits_generated;
```

## 9. 错误处理和容错

### 9.1 错误检测

- **区间溢出**: 监控算术编码区间的数值稳定性
- **概率异常**: 检测概率模型的收敛性
- **比特预算**: 监控输出比特数是否超出预算
- **存储器错误**: 检测存储器访问异常

### 9.2 容错机制

```verilog
// 算术编码稳定性检查
always @(posedge clk) begin
    if (current_state == ARITHMETIC_CODE) begin
        // 检查区间是否过小
        if (high - low < MIN_INTERVAL) begin
            error_flag <= ERROR_INTERVAL_TOO_SMALL;
        end
        
        // 检查概率是否有效
        if (cum_prob_high <= cum_prob_low) begin
            error_flag <= ERROR_INVALID_PROBABILITY;
        end
        
        // 检查比特预算
        if (bits_generated > max_frame_bits) begin
            error_flag <= ERROR_BIT_BUDGET_EXCEEDED;
        end
    end
end

// 错误恢复
always @(posedge clk) begin
    if (error_flag != NO_ERROR) begin
        case (error_flag)
            ERROR_INTERVAL_TOO_SMALL: begin
                // 重新初始化编码区间
                low <= 32'h00000000;
                high <= 32'hFFFFFFFF;
            end
            
            ERROR_INVALID_PROBABILITY: begin
                // 重置概率模型
                reset_probability_model <= 1'b1;
            end
            
            ERROR_BIT_BUDGET_EXCEEDED: begin
                // 截断当前帧
                force_frame_end <= 1'b1;
            end
        endcase
    end
end
```

## 10. 验证策略

### 10.1 算法验证

- **压缩效率**: 与LC3plus参考编码器的压缩比对比
- **比特精确性**: 解码后与原始系数的完全一致性验证
- **收敛性测试**: 概率模型的稳定性和收敛速度验证
- **边界条件**: 极值输入的编码行为验证

### 10.2 性能验证

- **实时性测试**: 最坏情况编码延时验证
- **比特率精度**: 目标比特率的控制精度验证
- **资源使用**: 存储器和计算资源使用验证
- **功耗测试**: 各工作模式功耗测量

### 10.3 测试用例

```verilog
// 测试用例1: 稀疏系数序列
initial begin
    // 大量零系数，测试游程编码效率
    for (int i = 0; i < 320; i++) begin
        if (i % 32 == 0) begin
            quantized_coeff = $random % 100;
        end else begin
            quantized_coeff = 0;
        end
        @(posedge clk);
    end
end

// 测试用例2: 随机系数序列
initial begin
    // 随机系数，测试概率模型适应性
    for (int i = 0; i < 320; i++) begin
        quantized_coeff = $random % 2048 - 1024;
        @(posedge clk);
    end
end

// 测试用例3: 比特率控制
initial begin
    target_bitrate = 64;  // 64 kbps
    // 验证输出比特率是否符合目标
    repeat(100) begin
        send_test_frame();
        wait(frame_done);
        assert(bits_generated <= target_frame_bits * 1.1)
        else $error("Bit rate exceeded");
    end
end
```

---

**文档版本**: v1.0  
**创建日期**: 2024-06-11  
**作者**: Audio Codec Design Team  
**审核状态**: 待审核 