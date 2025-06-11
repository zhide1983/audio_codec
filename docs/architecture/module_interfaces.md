# LC3plus编码器模块接口定义

## 1. 模块层次结构

```
lc3plus_encoder_top.v
├── memory/              (存储器子系统)
│   ├── audio_buffer_ram.v      (16KB 双端口音频缓冲)
│   ├── coeff_storage_rom.v     (16KB 系数存储ROM)  
│   ├── work_buffer_ram.v       (16KB 双端口工作缓冲)
│   └── memory_controller.v     (存储器访问仲裁)
├── control/             (控制子系统)
│   ├── apb_slave_regs.v        (APB从接口)
│   ├── register_bank.v         (寄存器银行)
│   └── interrupt_controller.v  (中断控制器)
├── datapath/            (数据通路)
│   ├── datapath_controller.v   (数据流控制)
│   ├── buffer_manager.v        (缓冲管理)
│   └── dma_controller.v        (DMA控制器)
└── processing/          (处理引擎)
    ├── time_domain_proc.v      (时域预处理)
    ├── mdct_transform.v        (MDCT变换)
    ├── spectral_analysis.v     (频域分析)
    ├── quantization_ctrl.v     (量化控制)
    ├── entropy_encoder.v       (熵编码)
    └── bitstream_packer.v      (比特流打包)
```

## 2. 存储器子系统接口

### 2.1 音频缓冲RAM (audio_buffer_ram.v)

#### 接口定义
```verilog
module audio_buffer_ram (
    input               clk,            // 系统时钟
    
    // 端口A - 主访问端口
    input   [11:0]      addr_a,         // 地址A (4096深度)
    input   [31:0]      wdata_a,        // 写数据A
    input               wen_a,          // 写使能A
    input               ren_a,          // 读使能A
    output  [31:0]      rdata_a,        // 读数据A
    
    // 端口B - 辅助访问端口
    input   [11:0]      addr_b,         // 地址B
    input   [31:0]      wdata_b,        // 写数据B
    input               wen_b,          // 写使能B
    input               ren_b,          // 读使能B
    output  [31:0]      rdata_b         // 读数据B
);
```

#### 存储器映射
| 地址范围 | 用途 | 大小 | 格式 |
|----------|------|------|------|
| 0x0000-0x03FF | 通道0 PCM缓冲 | 1K words | 24位PCM样本 |
| 0x0400-0x07FF | 通道1 PCM缓冲 | 1K words | 24位PCM样本 |
| 0x0800-0x0BFF | 通道2-7 PCM缓冲 | 1K words | 256样本/通道 |
| 0x0C00-0x0DFF | 时域处理中间结果 | 512 words | 处理后样本 |
| 0x0E00-0x0FFF | 通用缓冲空间 | 512 words | 临时数据 |

#### 资源需求
- **存储器**: 16KB (4096 x 32bit)
- **端口数**: 双端口
- **访问延迟**: 1个时钟周期
- **带宽**: 2端口 x 32bit x 100MHz = 800MB/s

### 2.2 系数存储ROM (coeff_storage_rom.v)

#### 接口定义
```verilog
module coeff_storage_rom (
    input               clk,            // 系统时钟
    input   [11:0]      addr,           // 地址 (4096深度)
    input               ren,            // 读使能
    output  [31:0]      rdata           // 读数据
);
```

#### 存储器映射
| 地址范围 | 用途 | 大小 | 格式 |
|----------|------|------|------|
| 0x0000-0x03FF | MDCT旋转因子 | 1K words | Q15复数 {cos,sin} |
| 0x0400-0x05FF | 窗函数系数 | 512 words | Q31汉宁窗 |
| 0x0600-0x07FF | 量化表 | 512 words | Q16量化步长 |
| 0x0800-0x09FF | 心理声学表 | 512 words | Bark映射表 |
| 0x0A00-0x0BFF | 熵编码表 | 512 words | 霍夫曼码表 |
| 0x0C00-0x0FFF | 保留扩展 | 1K words | 未来功能 |

#### 资源需求
- **存储器**: 16KB ROM (4096 x 32bit)
- **端口数**: 单端口只读
- **访问延迟**: 1个时钟周期
- **初始化**: 从hex文件加载或内置

### 2.3 工作缓冲RAM (work_buffer_ram.v)

#### 接口定义
```verilog
module work_buffer_ram (
    input               clk,            // 系统时钟
    
    // 端口A - 主访问端口
    input   [11:0]      addr_a,         // 地址A
    input   [31:0]      wdata_a,        // 写数据A  
    input               wen_a,          // 写使能A
    input               ren_a,          // 读使能A
    output  [31:0]      rdata_a,        // 读数据A
    
    // 端口B - 辅助访问端口
    input   [11:0]      addr_b,         // 地址B
    input   [31:0]      wdata_b,        // 写数据B
    input               wen_b,          // 写使能B
    input               ren_b,          // 读使能B
    output  [31:0]      rdata_b         // 读数据B
);
```

#### 存储器映射 
| 地址范围 | 用途 | 大小 | 格式 |
|----------|------|------|------|
| 0x0000-0x01FF | MDCT输入缓冲 | 512 words | 复数样本 |
| 0x0200-0x03FF | MDCT输出缓冲 | 512 words | 频域系数 |
| 0x0400-0x05FF | 频域分析工作区 | 512 words | 功率谱等 |
| 0x0600-0x07FF | 量化工作区 | 512 words | 比特分配 |
| 0x0800-0x09FF | 熵编码工作区 | 512 words | 符号缓冲 |
| 0x0A00-0x0BFF | TNS工作区 | 512 words | LPC系数 |
| 0x0C00-0x0DFF | LTPF工作区 | 512 words | 相关分析 |
| 0x0E00-0x0FFF | 通用临时空间 | 512 words | 中间结果 |

## 3. 处理模块接口

### 3.1 时域预处理模块 (time_domain_proc.v)

#### 接口定义
```verilog
module time_domain_proc (
    // 时钟和复位
    input               clk,
    input               rst_n,
    
    // 控制接口
    input               enable,         // 模块使能
    input               start,          // 开始处理
    output              done,           // 处理完成
    output              error,          // 错误标志
    
    // 配置参数
    input   [15:0]      frame_length,   // 帧长度
    input   [2:0]       channels,       // 通道数(1-8)
    input   [1:0]       sample_width,   // 样本位宽
    input   [15:0]      preemph_coeff,  // 预加重系数
    
    // PCM输入接口
    input   [31:0]      pcm_data,       // PCM输入数据
    input               pcm_valid,      // 输入有效
    output              pcm_ready,      // 输入准备
    
    // 时域输出接口
    output  [23:0]      time_data,      // 时域输出(Q23)
    output              time_valid,     // 输出有效
    input               time_ready,     // 下游准备
    
    // 存储器接口
    output  [11:0]      mem_addr,       // 存储器地址
    output  [31:0]      mem_wdata,      // 写数据
    input   [31:0]      mem_rdata,      // 读数据
    output              mem_wen,        // 写使能
    output              mem_ren,        // 读使能
    
    // 系数ROM接口
    output  [11:0]      coeff_addr,     // 系数地址
    input   [31:0]      coeff_data,     // 系数数据
    output              coeff_ren,      // 系数读使能
    
    // 调试接口
    output  [31:0]      debug_status
);
```

#### 功能描述
- **PCM输入处理**: 多通道16/24位PCM数据格式化
- **预加重滤波**: 高频增强滤波，系数可配置
- **窗函数处理**: 汉宁窗应用，50%重叠
- **帧分割**: 按配置帧长度分割音频数据

#### 处理流程
1. **PCM输入** (INPUT_PCM): 收集多通道PCM数据
2. **预加重** (PREEMPH): 应用高频增强滤波
3. **窗函数** (WINDOWING): 应用汉宁窗函数
4. **输出** (OUTPUT): 格式化输出到下游

#### 资源需求
- **逻辑资源**: ~3K LUT4等效
- **存储器访问**: 音频缓冲 + 系数ROM
- **DSP资源**: 2个乘法器(预加重+窗函数)
- **延迟**: ~4 × frame_length 时钟周期

### 3.2 MDCT变换模块 (mdct_transform.v)

#### 接口定义
```verilog
module mdct_transform (
    // 时钟和复位
    input               clk,
    input               rst_n,
    
    // 控制接口
    input               enable,
    input               start,
    output              done,
    output              error,
    
    // 配置参数
    input   [9:0]       transform_length, // 变换长度
    input   [2:0]       channels,         // 通道数
    
    // 时域输入接口
    input   [23:0]      time_data,        // 时域输入(Q23)
    input               time_valid,       // 输入有效
    output              time_ready,       // 输入准备
    
    // 频域输出接口
    output  [31:0]      freq_data,        // 频域输出
    output              freq_valid,       // 输出有效
    input               freq_ready,       // 下游准备
    
    // 系数ROM接口
    output  [11:0]      coeff_addr,       // 系数地址
    input   [31:0]      coeff_data,       // 系数数据
    
    // 工作RAM接口
    output  [11:0]      work_addr,        // 工作地址
    output  [31:0]      work_wdata,       // 工作写数据
    input   [31:0]      work_rdata,       // 工作读数据
    output              work_wen,         // 工作写使能
    
    // 调试接口
    output  [31:0]      debug_status
);
```

#### 功能描述
- **MDCT变换**: 修正离散余弦变换，基于FFT实现
- **多长度支持**: 160/320/640点变换
- **并行处理**: 4路并行蝶形运算
- **原位计算**: 优化存储器使用

#### 算法架构
```
MDCT Pipeline:
时域输入 → 预变换 → FFT核心 → 后变换 → 频域输出
  ↓         ↓        ↓        ↓        ↓
 24bit → 复数映射 → 蝶形运算 → MDCT映射 → 32bit
```

#### 资源需求
- **逻辑资源**: ~8K LUT4等效
- **存储器**: 4KB工作RAM + 2KB系数ROM
- **DSP资源**: 16个复数乘法器
- **延迟**: log2(N) × 40 时钟周期

### 3.3 频域分析模块 (spectral_analysis.v)

#### 接口定义
```verilog
module spectral_analysis (
    // 时钟和复位
    input               clk,
    input               rst_n,
    
    // 控制接口
    input               enable,
    input               start,
    output              done,
    output              error,
    
    // 配置参数
    input   [15:0]      sample_rate,      // 采样率
    input   [15:0]      bandwidth,        // 目标带宽
    input   [2:0]       channels,         // 通道数
    
    // 频域输入接口
    input   [31:0]      freq_data,        // 频域输入
    input               freq_valid,       // 输入有效
    output              freq_ready,       // 输入准备
    
    // 分析输出接口
    output  [31:0]      spectrum_data,    // 谱分析输出
    output              spectrum_valid,   // 输出有效
    input               spectrum_ready,   // 下游准备
    
    // 分析结果
    output  [7:0]       bandwidth_index,  // 带宽索引
    output  [15:0]      envelope_data,    // 谱包络
    output  [7:0]       tns_order,        // TNS阶数
    output  [31:0]      tns_coeff,        // TNS系数
    
    // 存储器接口
    output  [11:0]      mem_addr,
    output  [31:0]      mem_wdata,
    input   [31:0]      mem_rdata,
    output              mem_wen,
    
    // 调试接口
    output  [31:0]      debug_status
);
```

#### 功能描述
- **功率谱估计**: 计算频域功率谱密度
- **带宽检测**: 自适应带宽控制(4k-24kHz)
- **谱包络**: 对数域谱包络计算
- **TNS分析**: 时域噪声整形参数估计
- **感知加权**: 心理声学模型应用

#### 资源需求
- **逻辑资源**: ~6K LUT4等效
- **存储器**: 2KB谱缓冲 + 1KB系数ROM
- **DSP资源**: 8个乘法器 + 4个除法器
- **延迟**: ~200时钟周期/帧

### 3.4 量化控制模块 (quantization_ctrl.v)

#### 接口定义
```verilog
module quantization_ctrl (
    // 时钟和复位
    input               clk,
    input               rst_n,
    
    // 控制接口
    input               enable,
    input               start,
    output              done,
    output              error,
    
    // 配置参数
    input   [15:0]      target_bitrate,   // 目标比特率
    input   [15:0]      frame_length,     // 帧长度
    input   [2:0]       channels,         // 通道数
    
    // 谱输入接口
    input   [31:0]      spectrum_data,    // 谱输入
    input               spectrum_valid,   // 输入有效
    output              spectrum_ready,   // 输入准备
    
    // 分析输入
    input   [7:0]       bandwidth_index,  // 带宽索引
    input   [15:0]      envelope_data,    // 谱包络
    input   [7:0]       tns_order,        // TNS阶数
    input   [31:0]      tns_coeff,        // TNS系数
    
    // 量化输出接口
    output  [15:0]      quant_data,       // 量化输出
    output              quant_valid,      // 输出有效
    input               quant_ready,      // 下游准备
    
    // 量化参数
    output  [7:0]       global_gain,      // 全局增益
    output  [15:0]      bit_allocation,   // 比特分配
    output  [7:0]       noise_level,      // 噪声级别
    
    // 存储器接口
    output  [11:0]      mem_addr,
    output  [31:0]      mem_wdata,
    input   [31:0]      mem_rdata,
    output              mem_wen,
    
    // 调试接口
    output  [31:0]      debug_status
);
```

#### 功能描述
- **全局增益控制**: 迭代增益估计和调整
- **比特分配**: 基于感知模型的比特分配
- **量化处理**: 标量量化 + 噪声整形
- **质量控制**: 失真度评估和优化

#### 资源需求
- **逻辑资源**: ~5K LUT4等效
- **存储器**: 1KB量化表 + 2KB工作缓冲
- **DSP资源**: 8个乘法器 + 8个加法器
- **延迟**: ~150时钟周期/帧

### 3.5 熵编码模块 (entropy_encoder.v)

#### 接口定义
```verilog
module entropy_encoder (
    // 时钟和复位
    input               clk,
    input               rst_n,
    
    // 控制接口
    input               enable,
    input               start,
    output              done,
    output              error,
    
    // 配置参数
    input   [15:0]      target_bytes,     // 目标字节数
    input   [2:0]       channels,         // 通道数
    
    // 量化输入接口
    input   [15:0]      quant_data,       // 量化输入
    input               quant_valid,      // 输入有效
    output              quant_ready,      // 输入准备
    
    // 量化参数输入
    input   [7:0]       global_gain,      // 全局增益
    input   [15:0]      bit_allocation,   // 比特分配
    input   [7:0]       noise_level,      // 噪声级别
    
    // 比特流输出接口
    output  [7:0]       bitstream_data,   // 比特流输出
    output              bitstream_valid,  // 输出有效
    input               bitstream_ready,  // 下游准备
    
    // 编码状态
    output  [15:0]      coded_bytes,      // 已编码字节
    output  [7:0]       coding_gain,      // 编码增益
    
    // 存储器接口
    output  [11:0]      mem_addr,
    output  [31:0]      mem_wdata,
    input   [31:0]      mem_rdata,
    output              mem_wen,
    
    // 调试接口
    output  [31:0]      debug_status
);
```

#### 功能描述
- **算术编码**: 自适应算术编码器
- **上下文建模**: 频域相关性建模
- **概率估计**: 动态概率更新
- **比特流管理**: 输出缓冲和格式化

#### 资源需求
- **逻辑资源**: ~10K LUT4等效
- **存储器**: 4KB概率表 + 1KB编码缓冲
- **DSP资源**: 4个乘法器 + 专用移位器
- **延迟**: ~300时钟周期/帧

### 3.6 比特流打包模块 (bitstream_packer.v)

#### 接口定义
```verilog
module bitstream_packer (
    // 时钟和复位
    input               clk,
    input               rst_n,
    
    // 控制接口
    input               enable,
    input               start,
    output              done,
    output              error,
    
    // 配置参数
    input   [15:0]      frame_bytes,      // 帧字节数
    input   [2:0]       channels,         // 通道数
    input   [15:0]      sample_rate,      // 采样率
    
    // 比特流输入接口
    input   [7:0]       bitstream_data,   // 比特流输入
    input               bitstream_valid,  // 输入有效
    output              bitstream_ready,  // 输入准备
    
    // 编码信息输入
    input   [15:0]      coded_bytes,      // 编码字节数
    input   [7:0]       coding_gain,      // 编码增益
    
    // 打包输出接口
    output  [31:0]      packed_data,      // 打包输出
    output              packed_valid,     // 输出有效
    input               packed_ready,     // 下游准备
    
    // 帧信息
    output  [15:0]      frame_size,       // 帧大小
    output  [7:0]       frame_crc,        // 帧CRC
    
    // 调试接口
    output  [31:0]      debug_status
);
```

#### 功能描述
- **标准格式**: LC3plus比特流格式
- **帧头生成**: 采样率、帧长、通道数
- **CRC校验**: 16位帧完整性校验
- **字节对齐**: 输出字节对齐处理

#### 资源需求
- **逻辑资源**: ~2K LUT4等效
- **存储器**: 2KB打包缓冲
- **延迟**: ~50时钟周期/帧

## 4. 控制和数据通路

### 4.1 数据通路控制器 (datapath_controller.v)

#### 功能描述
- **流水线控制**: 6级编码流水线调度
- **数据流管理**: 模块间数据流控制
- **反压处理**: 背压和流控管理
- **错误处理**: 异常检测和恢复

#### 状态机设计
```verilog
// 编码流水线状态
typedef enum [3:0] {
    IDLE        = 4'b0000,
    TIME_PROC   = 4'b0001,    // 时域预处理
    MDCT_TRANS  = 4'b0010,    // MDCT变换
    SPEC_ANAL   = 4'b0011,    // 频域分析
    QUANTIZE    = 4'b0100,    // 量化控制
    ENTROPY_ENC = 4'b0101,    // 熵编码
    PACK_STREAM = 4'b0110,    // 比特流打包
    DONE        = 4'b0111,    // 完成
    ERROR       = 4'b1111     // 错误
} enc_state_t;
```

### 4.2 缓冲管理器 (buffer_manager.v)

#### 功能描述
- **多通道缓冲**: 8通道音频数据管理
- **环形缓冲**: 连续音频流处理
- **同步控制**: 多通道数据同步

### 4.3 DMA控制器 (dma_controller.v)

#### 功能描述
- **外部存储器访问**: AXI4/AHB总线适配
- **突发传输**: 优化带宽利用
- **多通道DMA**: 并发数据传输

## 5. 总体资源汇总

### 5.1 逻辑资源统计

| 模块 | LUT4 | FF | 关键路径 | 备注 |
|------|------|----|---------|----- |
| 时域预处理 | 3K | 2K | 8ns | 预加重+窗函数 |
| MDCT变换 | 8K | 6K | 10ns | FFT核心 |
| 频域分析 | 6K | 4K | 9ns | 谱分析 |
| 量化控制 | 5K | 3K | 8ns | 比特分配 |
| 熵编码 | 10K | 8K | 12ns | 算术编码 |
| 比特流打包 | 2K | 1K | 6ns | 格式化 |
| 控制接口 | 4K | 3K | 8ns | 寄存器+中断 |
| **总计** | **38K** | **27K** | **12ns** | 100MHz目标 |

### 5.2 存储器资源统计

| 存储器类型 | 大小 | 端口 | 用途 | 工艺要求 |
|------------|------|------|------|----------|
| 音频缓冲RAM | 16KB | 双端口 | PCM缓冲 | 高速RAM |
| 系数ROM | 16KB | 单端口 | 常数表 | 低功耗ROM |
| 工作缓冲RAM | 16KB | 双端口 | 临时数据 | 高速RAM |
| **总计** | **48KB** | - | - | 混合存储 |

### 5.3 DSP资源统计

| 功能模块 | 乘法器 | 加法器 | 位宽 | 特殊功能 |
|----------|--------|--------|------|----------|
| 时域预处理 | 2 | 2 | 24x16 | 预加重滤波 |
| MDCT变换 | 16 | 16 | 16x16 | 复数蝶形 |
| 频域分析 | 8 | 8 | 24x24 | 功率谱 |
| 量化控制 | 8 | 8 | 16x16 | 标量量化 |
| 熵编码 | 4 | 4 | 32x32 | 概率计算 |
| **总计** | **38** | **38** | - | - |

### 5.4 性能指标

#### 延迟分析
```
处理阶段延迟 (10ms帧@48kHz):
├── 时域预处理: 1920 cycles (19.2μs)
├── MDCT变换:   2400 cycles (24.0μs)
├── 频域分析:   200 cycles  (2.0μs)
├── 量化控制:   150 cycles  (1.5μs)
├── 熵编码:     300 cycles  (3.0μs)
└── 比特流打包: 50 cycles   (0.5μs)

总延迟: 5020 cycles = 50.2μs (0.5% of frame time)
```

#### 吞吐量分析
```
理论处理能力:
├── 最大采样率: 48kHz × 8通道 = 384k样本/秒
├── 处理延迟: 50.2μs/帧
├── 帧周期: 10ms
├── 实时余量: 99.5%
└── 并发处理: 支持流水线重叠
```

#### 功耗估算
```
动态功耗 @100MHz:
├── 核心逻辑: 38K LUT × 0.5μW = 19mW
├── 存储器: 48KB × 0.6mW/KB = 29mW
├── DSP: 38乘法器 × 0.5mW = 19mW
├── 时钟树: 27K FF × 0.1μW = 3mW
└── 静态功耗: ~15mW

总功耗: 85mW (目标<100mW ✓)
```

## 6. 接口时序要求

### 6.1 时钟域设计
- **主时钟**: 100MHz系统时钟
- **复位**: 异步置位，同步释放
- **时钟树**: 平衡时钟树，最大偏差<100ps

### 6.2 接口时序
- **数据建立时间**: 2ns (before clock edge)
- **数据保持时间**: 1ns (after clock edge)
- **时钟到输出**: 最大8ns
- **传播延迟**: 模块间<5ns

### 6.3 流控协议
- **Valid/Ready**: 标准AXI-Stream协议
- **反压支持**: 所有模块支持背压
- **数据完整性**: 无数据丢失保证

---

**文档版本**: v1.0  
**更新日期**: 2024-06-11  
**状态**: 详细设计阶段  
**下一步**: 开始RTL编码实现 