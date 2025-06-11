# MDCT变换模块设计文档

## 1. 模块概述

### 1.1 功能描述
MDCT (Modified Discrete Cosine Transform) 变换模块是LC3plus编码器的核心组件，负责将时域音频信号转换为频域表示。该模块实现标准的MDCT算法，支持可配置的变换长度。

### 1.2 主要特性
- **变换长度**: 支持160/320/640点MDCT (对应2.5ms/5ms/10ms帧长@48kHz)
- **算法实现**: 基于FFT的高效MDCT实现
- **精度**: 内部24bit定点运算，输出16bit系数
- **延时**: 流水线处理，2个时钟周期输出延时
- **资源优化**: 复用FFT核心，减少乘法器使用

## 2. 端口定义

### 2.1 端口列表

```verilog
module mdct_transform (
    // 系统信号
    input                       clk,
    input                       rst_n,
    
    // 配置接口
    input       [1:0]           frame_duration,     // 帧长配置: 00=2.5ms, 01=5ms, 10=10ms
    input                       channel_mode,       // 通道模式: 0=单声道, 1=立体声
    input                       enable,             // 模块使能
    
    // 输入数据接口 (来自时域预处理)
    input                       input_valid,        // 输入数据有效
    input       [23:0]          input_data,         // 输入时域样本 (24bit)
    input       [9:0]           input_index,        // 样本索引 (0~639)
    output                      input_ready,        // 输入就绪信号
    
    // 输出数据接口 (到频谱分析)
    output                      output_valid,       // 输出数据有效
    output      [15:0]          output_real,        // MDCT系数实部 (16bit)
    output      [15:0]          output_imag,        // MDCT系数虚部 (16bit) 
    output      [9:0]           output_index,       // 系数索引
    input                       output_ready,       // 下游就绪信号
    
    // 存储器接口 (工作缓冲器)
    output                      mem_req_valid,      // 存储器请求有效
    output      [11:0]          mem_req_addr,       // 存储器地址
    output      [31:0]          mem_req_wdata,      // 写数据
    output                      mem_req_wen,        // 写使能
    input                       mem_req_ready,      // 存储器就绪
    input       [31:0]          mem_req_rdata,      // 读数据
    
    // 系数ROM接口
    output                      coeff_req_valid,    // 系数请求有效
    output      [13:0]          coeff_req_addr,     // 系数地址
    input       [31:0]          coeff_req_data,     // 系数数据
    input                       coeff_req_ready,    // 系数就绪
    
    // 状态输出
    output                      transform_busy,     // 变换忙碌状态
    output                      frame_done,         // 帧处理完成
    output      [31:0]          debug_info          // 调试信息
);
```

### 2.2 端口详细说明

| 端口名 | 方向 | 位宽 | 描述 |
|--------|------|------|------|
| `clk` | Input | 1 | 系统时钟，100-200MHz |
| `rst_n` | Input | 1 | 异步复位，低有效 |
| `frame_duration` | Input | 2 | 帧长配置，决定MDCT点数 |
| `channel_mode` | Input | 1 | 通道模式配置 |
| `enable` | Input | 1 | 模块使能控制 |
| `input_valid` | Input | 1 | 输入数据有效标志 |
| `input_data` | Input | 24 | 时域输入样本，Q1.23格式 |
| `input_index` | Input | 10 | 输入样本索引 |
| `input_ready` | Output | 1 | 可接收输入数据 |
| `output_valid` | Output | 1 | 输出数据有效标志 |
| `output_real` | Output | 16 | MDCT系数实部，Q1.15格式 |
| `output_imag` | Output | 16 | MDCT系数虚部，Q1.15格式 |
| `output_index` | Output | 10 | 输出系数索引 |
| `output_ready` | Input | 1 | 下游模块就绪 |

## 3. 算法实现

### 3.1 MDCT算法原理

MDCT变换公式：
```
X[k] = Σ(n=0 to N-1) x[n] * cos(π/N * (n + 0.5 + N/2) * (k + 0.5))
```

其中：
- N = MDCT点数 (160/320/640)
- x[n] = 输入时域样本
- X[k] = 输出频域系数

### 3.2 基于FFT的高效实现

采用FFT算法加速MDCT计算：

```
1. 预处理: 重排输入数据并应用窗函数
   y[n] = x[n] * w[n] + x[N+n] * w[N+n]   (n = 0...N/2-1)
   
2. FFT变换: N/2点复数FFT
   Y[k] = FFT(y[n])
   
3. 后处理: 提取MDCT系数
   X[k] = Re(Y[k] * e^(-jπk/N)) + Im(Y[k] * e^(-jπk/N))
```

### 3.3 流水线架构

```
阶段1: 输入缓冲与预处理
  ├─ 数据重排
  ├─ 窗函数应用  
  └─ 复数组合

阶段2: FFT核心运算
  ├─ Radix-2 FFT
  ├─ 蝶形运算
  └─ 复数乘法

阶段3: 后处理与输出
  ├─ 相位旋转
  ├─ 实部提取
  └─ 量化输出
```

## 4. 量化规则

### 4.1 数据格式定义

| 信号 | 格式 | 范围 | 描述 |
|------|------|------|------|
| 输入样本 | Q1.23 | [-1, 1) | 时域音频样本 |
| 内部运算 | Q1.23 | [-1, 1) | FFT中间结果 |
| 窗函数系数 | Q1.15 | [-1, 1) | 存储在ROM中 |
| 旋转因子 | Q1.15 | [-1, 1) | 复数指数项 |
| 输出系数 | Q1.15 | [-1, 1) | MDCT频域系数 |

### 4.2 量化策略

```verilog
// 输入样本量化 (已在时域预处理完成)
input_data[23:0] = signed Q1.23 format

// FFT内部运算保持精度
fft_data[23:0] = signed Q1.23 format

// 输出量化到16bit
output_coeff[15:0] = input_data[23:8] with saturation
```

### 4.3 饱和处理

```verilog
function [15:0] saturate_q15;
    input [23:0] data_in;
    begin
        if (data_in > 24'h7FFFFF)
            saturate_q15 = 16'h7FFF;    // 正饱和
        else if (data_in < 24'h800000)
            saturate_q15 = 16'h8000;    // 负饱和  
        else
            saturate_q15 = data_in[22:7]; // 正常截取
    end
endfunction
```

## 5. 存储器映射

### 5.1 工作缓冲器分配

**基地址**: 0x000 (MDCT工作区，1024 words)

| 地址范围 | 大小 | 用途 |
|----------|------|------|
| 0x000-0x13F | 320 words | 输入样本缓冲 (最大640样本) |
| 0x140-0x27F | 320 words | FFT中间结果 |
| 0x280-0x2FF | 128 words | 窗函数缓冲 |
| 0x300-0x3FF | 256 words | 输出系数缓冲 |

### 5.2 系数ROM映射

**基地址**: 0x0000 (系数ROM)

| 地址范围 | 大小 | 用途 |
|----------|------|------|
| 0x0000-0x027F | 640 words | 窗函数系数 |
| 0x0280-0x04FF | 640 words | 旋转因子 (实部) |
| 0x0500-0x077F | 640 words | 旋转因子 (虚部) |
| 0x0780-0x07FF | 128 words | 预计算常数 |

## 6. 状态机设计

### 6.1 主状态机

```verilog
typedef enum logic [2:0] {
    IDLE        = 3'b000,    // 空闲状态
    INPUT_BUF   = 3'b001,    // 输入数据缓冲
    PREPROCESS  = 3'b010,    // 预处理阶段
    FFT_COMPUTE = 3'b011,    // FFT计算
    POSTPROCESS = 3'b100,    // 后处理
    OUTPUT      = 3'b101,    // 输出结果
    ERROR       = 3'b110     // 错误状态
} mdct_state_t;
```

### 6.2 状态转换

```
IDLE → INPUT_BUF:     enable && input_valid
INPUT_BUF → PREPROCESS: 样本收集完成
PREPROCESS → FFT_COMPUTE: 预处理完成
FFT_COMPUTE → POSTPROCESS: FFT计算完成  
POSTPROCESS → OUTPUT: 后处理完成
OUTPUT → IDLE:        输出完成
任意状态 → ERROR:      错误条件
ERROR → IDLE:         复位或错误清除
```

## 7. 性能规格

### 7.1 时序要求

| 参数 | 数值 | 单位 | 说明 |
|------|------|------|------|
| 最大频率 | 200 | MHz | 满足实时处理需求 |
| 输入带宽 | 1 | 样本/周期 | 连续数据流 |
| 处理延时 | 1280 | 周期 | 640点MDCT最大延时 |
| 输出带宽 | 1 | 系数/周期 | 流水线输出 |

### 7.2 资源估算

| 资源类型 | 数量 | 说明 |
|----------|------|------|
| LUT4等效 | 12,000 | 包含FFT和控制逻辑 |
| 触发器 | 8,000 | 流水线寄存器 |
| 乘法器 | 12 | 复数乘法器 |
| SRAM | 4KB | 工作缓冲器分配 |
| ROM | 8KB | 系数存储 |

### 7.3 功耗分析

| 工作模式 | 功耗 | 说明 |
|----------|------|------|
| 活跃处理 | 25mW | 100MHz时钟频率 |
| 待机模式 | 5mW | 时钟门控 |
| 关闭模式 | <1mW | 电源门控 |

## 8. 接口协议

### 8.1 输入数据协议

```verilog
// 输入握手协议
always @(posedge clk) begin
    if (input_valid && input_ready) begin
        // 数据传输成功
        input_buffer[input_index] <= input_data;
        input_count <= input_count + 1;
    end
end

// 就绪信号生成
assign input_ready = (state == INPUT_BUF) && 
                     (input_count < max_samples);
```

### 8.2 输出数据协议

```verilog
// 输出握手协议
always @(posedge clk) begin
    if (output_valid && output_ready) begin
        // 输出下一个系数
        output_index <= output_index + 1;
        if (output_index == max_coeffs - 1) begin
            frame_done <= 1'b1;
        end
    end
end
```

## 9. 错误处理

### 9.1 错误检测

- **溢出检测**: 监控FFT运算中的数据溢出
- **配置错误**: 检查不合法的帧长配置
- **存储器错误**: 检测存储器访问异常
- **时序违例**: 检测输入数据时序错误

### 9.2 错误恢复

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        error_state <= NO_ERROR;
    end else begin
        case (error_state)
            NO_ERROR: begin
                if (overflow_detected)
                    error_state <= OVERFLOW_ERROR;
                else if (config_error)
                    error_state <= CONFIG_ERROR;
            end
            
            OVERFLOW_ERROR: begin
                // 清零并重启
                if (error_clear)
                    error_state <= NO_ERROR;
            end
        endcase
    end
end
```

## 10. 验证策略

### 10.1 单元测试

- **算法验证**: 与Matlab/C参考模型对比
- **边界测试**: 最大/最小输入值测试
- **配置测试**: 不同帧长配置验证
- **性能测试**: 时序和资源使用验证

### 10.2 集成测试

- **数据流测试**: 与上下游模块接口测试
- **背压测试**: 下游模块非就绪情况
- **连续帧测试**: 多帧连续处理验证
- **错误注入**: 人工错误条件测试

### 10.3 测试用例

```verilog
// 测试用例1: 正弦波输入
initial begin
    for (int i = 0; i < 640; i++) begin
        input_data = $rtoi(32767 * $sin(2*3.14159*1000*i/48000));
        @(posedge clk);
    end
end

// 测试用例2: 脉冲响应
initial begin
    input_data = 24'h7FFFFF;  // 单位脉冲
    @(posedge clk);
    input_data = 24'h000000;  // 其余为零
    repeat(639) @(posedge clk);
end
```

---

**文档版本**: v1.0  
**创建日期**: 2024-06-11  
**作者**: Audio Codec Design Team  
**审核状态**: 待审核 