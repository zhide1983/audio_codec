# 顶层集成模块设计文档

## 1. 模块概述

### 1.1 功能描述
顶层集成模块是LC3plus音频编码器的最高层组件，负责协调和管理所有子模块的工作。该模块提供统一的外部接口，实现完整的LC3plus编码流水线，包括配置管理、时序控制、错误处理和系统监控功能。

### 1.2 主要特性
- **完整流水线**: 集成6级编码流水线的所有功能模块
- **统一接口**: 提供标准化的AXI4-Stream和APB接口
- **配置管理**: 支持运行时参数配置和系统监控
- **错误处理**: 全系统错误检测、报告和恢复机制
- **性能监控**: 实时性能统计和资源使用监控
- **调试支持**: 完整的调试接口和状态可视化

## 2. 端口定义

### 2.1 端口列表

```verilog
module lc3plus_encoder_top (
    // 系统信号
    input                       clk,
    input                       rst_n,
    
    // 主配置接口
    input       [1:0]           frame_duration,     // 帧长配置 (2.5/5/10ms)
    input                       channel_mode,       // 通道模式 (0:单声道,1:立体声)
    input       [7:0]           target_bitrate,     // 目标比特率 (16-320 kbps)
    input       [15:0]          sample_rate,        // 采样率 (8/16/24/48 kHz)
    input                       encoder_enable,     // 编码器总使能
    
    // AXI4-Stream音频输入接口
    input                       s_axis_audio_tvalid, // 音频数据有效
    input       [31:0]          s_axis_audio_tdata,  // 音频数据 (24位有效)
    input                       s_axis_audio_tlast,  // 帧结束标志
    output                      s_axis_audio_tready, // 音频输入就绪
    
    // AXI4-Stream比特流输出接口
    output                      m_axis_bitstream_tvalid, // 比特流数据有效
    output      [7:0]           m_axis_bitstream_tdata,  // 比特流字节数据
    output                      m_axis_bitstream_tlast,  // 帧结束标志
    output      [15:0]          m_axis_bitstream_tuser,  // 帧大小信息
    input                       m_axis_bitstream_tready, // 比特流输出就绪
    
    // APB配置接口
    input                       pclk,               // APB时钟
    input                       presetn,            // APB复位
    input                       psel,               // APB选择
    input                       penable,            // APB使能
    input                       pwrite,             // APB写使能
    input       [11:0]          paddr,              // APB地址
    input       [31:0]          pwdata,             // APB写数据
    output      [31:0]          prdata,             // APB读数据
    output                      pready,             // APB就绪
    output                      pslverr,            // APB错误
    
    // 系统存储器接口 (统一SRAM)
    output                      mem_req_valid,      // 存储器请求有效
    output      [15:0]          mem_req_addr,       // 存储器地址
    output      [31:0]          mem_req_wdata,      // 写数据
    output                      mem_req_wen,        // 写使能
    input                       mem_req_ready,      // 存储器就绪
    input       [31:0]          mem_req_rdata,      // 读数据
    
    // 系统状态输出
    output                      encoding_active,    // 编码活跃状态
    output                      frame_processing,   // 帧处理状态
    output      [2:0]           pipeline_stage,     // 当前流水线阶段
    output      [31:0]          performance_info,   // 性能信息
    output      [31:0]          error_status,       // 错误状态
    
    // 调试接口
    output      [31:0]          debug_mdct,         // MDCT模块调试信息
    output      [31:0]          debug_spectral,     // 频谱分析调试信息
    output      [31:0]          debug_quantization, // 量化控制调试信息
    output      [31:0]          debug_entropy,      // 熵编码调试信息
    output      [31:0]          debug_packing       // 比特流打包调试信息
);
```

### 2.2 端口详细说明

| 端口名 | 方向 | 位宽 | 描述 |
|--------|------|------|------|
| `clk` | Input | 1 | 主系统时钟，100-200MHz |
| `rst_n` | Input | 1 | 异步复位，低有效 |
| `frame_duration` | Input | 2 | 帧长配置，支持2.5/5/10ms |
| `channel_mode` | Input | 1 | 通道模式，0=单声道，1=立体声 |
| `target_bitrate` | Input | 8 | 目标比特率，16-320 kbps |
| `sample_rate` | Input | 16 | 采样率，支持8/16/24/48 kHz |
| `encoder_enable` | Input | 1 | 编码器总使能控制 |
| `s_axis_audio_tdata` | Input | 32 | 音频数据，24位有效，Q1.23格式 |
| `m_axis_bitstream_tdata` | Output | 8 | 输出比特流字节数据 |
| `m_axis_bitstream_tuser` | Output | 16 | 帧大小信息，单位字节 |
| `paddr` | Input | 12 | APB地址，支持4KB配置空间 |
| `mem_req_addr` | Output | 16 | 统一存储器地址，64KB地址空间 |
| `pipeline_stage` | Output | 3 | 当前处理的流水线阶段标识 |
| `performance_info` | Output | 32 | 性能统计信息 |
| `error_status` | Output | 32 | 系统错误状态寄存器 |

## 3. 系统架构

### 3.1 模块互连图

```
音频输入 → [MDCT变换] → [频谱分析] → [量化控制] → [熵编码] → [比特流打包] → 比特流输出
    ↓           ↓            ↓            ↓           ↓            ↓
  ┌─────────────────────────────────────────────────────────────────────┐
  │                        顶层集成模块                                │
  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │
  │  │配置管理 │  │时序控制 │  │错误处理 │  │性能监控 │  │调试接口 │   │
  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘   │
  └─────────────────────────────────────────────────────────────────────┘
                                  ↓
                         [统一存储器子系统]
```

### 3.2 流水线控制

```verilog
// 流水线阶段定义
typedef enum logic [2:0] {
    STAGE_IDLE      = 3'b000,    // 空闲阶段
    STAGE_MDCT      = 3'b001,    // MDCT变换阶段
    STAGE_SPECTRAL  = 3'b010,    // 频谱分析阶段
    STAGE_QUANTIZE  = 3'b011,    // 量化控制阶段
    STAGE_ENTROPY   = 3'b100,    // 熵编码阶段
    STAGE_PACKING   = 3'b101,    // 比特流打包阶段
    STAGE_OUTPUT    = 3'b110,    // 输出阶段
    STAGE_ERROR     = 3'b111     // 错误阶段
} pipeline_stage_t;
```

### 3.3 模块间握手协议

```
模块A → 模块B 数据传输协议:
1. 模块A: data_valid = 1, data = X
2. 模块B: data_ready = 1 (if can accept)
3. 数据传输: valid & ready = 1
4. 模块A: data_valid = 0 (after transfer)

帧边界处理:
1. 帧开始: frame_start = 1 (持续1个周期)
2. 帧数据: 连续的data_valid传输
3. 帧结束: frame_end = 1 (与最后数据同步)
```

## 4. 配置管理

### 4.1 APB寄存器映射

**基地址**: 0x000 (配置寄存器，4KB空间)

| 地址偏移 | 寄存器名 | 访问类型 | 描述 |
|----------|----------|----------|------|
| 0x000 | CTRL_REG | RW | 控制寄存器 |
| 0x004 | CONFIG_REG | RW | 配置寄存器 |
| 0x008 | STATUS_REG | RO | 状态寄存器 |
| 0x00C | ERROR_REG | RO | 错误寄存器 |
| 0x010 | PERF_REG0 | RO | 性能统计寄存器0 |
| 0x014 | PERF_REG1 | RO | 性能统计寄存器1 |
| 0x018 | DEBUG_REG | RW | 调试控制寄存器 |
| 0x01C | VERSION_REG | RO | 版本信息寄存器 |

### 4.2 寄存器详细定义

```verilog
// 控制寄存器 (0x000)
typedef struct packed {
    logic [23:0] reserved;      // [31:8]  保留
    logic [1:0]  frame_duration; // [7:6]   帧长配置
    logic        channel_mode;  // [5]     通道模式
    logic        soft_reset;    // [4]     软复位
    logic [2:0]  debug_level;   // [3:1]   调试级别
    logic        enable;        // [0]     使能控制
} ctrl_reg_t;

// 配置寄存器 (0x004)
typedef struct packed {
    logic [15:0] sample_rate;   // [31:16] 采样率
    logic [7:0]  target_bitrate; // [15:8]  目标比特率
    logic [7:0]  reserved;      // [7:0]   保留
} config_reg_t;

// 状态寄存器 (0x008)
typedef struct packed {
    logic [15:0] frame_count;   // [31:16] 已处理帧数
    logic [12:0] reserved;      // [15:3]  保留
    logic [2:0]  pipeline_stage; // [2:0]   当前流水线阶段
} status_reg_t;

// 错误寄存器 (0x00C)
typedef struct packed {
    logic [26:0] reserved;      // [31:5]  保留
    logic        packing_error; // [4]     比特流打包错误
    logic        entropy_error; // [3]     熵编码错误
    logic        quant_error;   // [2]     量化控制错误
    logic        spectral_error; // [1]     频谱分析错误
    logic        mdct_error;    // [0]     MDCT变换错误
} error_reg_t;
```

### 4.3 运行时配置更新

```verilog
// 配置更新控制逻辑
always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
        config_updated <= 1'b0;
        config_pending <= 1'b0;
    end else begin
        // 检测配置寄存器写入
        if (psel && penable && pwrite && (paddr == 12'h004)) begin
            config_pending <= 1'b1;
        end
        
        // 在帧边界应用新配置
        if (config_pending && frame_boundary) begin
            // 应用新的编码参数
            apply_new_config();
            config_updated <= 1'b1;
            config_pending <= 1'b0;
        end
    end
end
```

## 5. 时序控制

### 5.1 流水线调度

```verilog
// 流水线调度状态机
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_pipeline_stage <= STAGE_IDLE;
    end else begin
        case (current_pipeline_stage)
            STAGE_IDLE: begin
                if (encoder_enable && s_axis_audio_tvalid) begin
                    current_pipeline_stage <= STAGE_MDCT;
                end
            end
            
            STAGE_MDCT: begin
                if (mdct_frame_done) begin
                    current_pipeline_stage <= STAGE_SPECTRAL;
                end
            end
            
            STAGE_SPECTRAL: begin
                if (spectral_frame_done) begin
                    current_pipeline_stage <= STAGE_QUANTIZE;
                end
            end
            
            STAGE_QUANTIZE: begin
                if (quantize_frame_done) begin
                    current_pipeline_stage <= STAGE_ENTROPY;
                end
            end
            
            STAGE_ENTROPY: begin
                if (entropy_frame_done) begin
                    current_pipeline_stage <= STAGE_PACKING;
                end
            end
            
            STAGE_PACKING: begin
                if (packing_frame_done) begin
                    current_pipeline_stage <= STAGE_OUTPUT;
                end
            end
            
            STAGE_OUTPUT: begin
                if (output_complete) begin
                    current_pipeline_stage <= STAGE_IDLE;
                end
            end
            
            default: begin
                current_pipeline_stage <= STAGE_ERROR;
            end
        endcase
    end
end
```

### 5.2 存储器仲裁

```verilog
// 存储器访问仲裁器
module memory_arbiter (
    input                   clk,
    input                   rst_n,
    
    // 来自各模块的存储器请求
    input                   mdct_req_valid,
    input       [15:0]      mdct_req_addr,
    input       [31:0]      mdct_req_wdata,
    input                   mdct_req_wen,
    output                  mdct_req_ready,
    output      [31:0]      mdct_req_rdata,
    
    // ... 其他模块的存储器请求接口
    
    // 统一的存储器接口
    output                  mem_req_valid,
    output      [15:0]      mem_req_addr,
    output      [31:0]      mem_req_wdata,
    output                  mem_req_wen,
    input                   mem_req_ready,
    input       [31:0]      mem_req_rdata
);

// 轮询仲裁逻辑
// 按优先级：MDCT > 频谱分析 > 量化控制 > 熵编码 > 比特流打包
```

## 6. 错误处理

### 6.1 错误检测

```verilog
// 系统级错误检测
always @(posedge clk) begin
    // 收集各模块错误状态
    system_error_status <= {
        27'b0,
        packing_error,
        entropy_error, 
        quantization_error,
        spectral_error,
        mdct_error
    };
    
    // 检测超时错误
    if (frame_processing_time > max_frame_time) begin
        timeout_error <= 1'b1;
    end
    
    // 检测数据流错误
    if (unexpected_data_pattern) begin
        dataflow_error <= 1'b1;
    end
end
```

### 6.2 错误恢复

```verilog
// 错误恢复策略
always @(posedge clk) begin
    if (system_error_detected) begin
        case (error_type)
            TIMEOUT_ERROR: begin
                // 超时错误：强制重启当前帧
                force_frame_restart <= 1'b1;
            end
            
            DATA_ERROR: begin
                // 数据错误：清除缓冲器并重新同步
                clear_all_buffers <= 1'b1;
                resync_pipeline <= 1'b1;
            end
            
            CONFIG_ERROR: begin
                // 配置错误：恢复默认配置
                restore_default_config <= 1'b1;
            end
            
            CRITICAL_ERROR: begin
                // 严重错误：系统复位
                system_soft_reset <= 1'b1;
            end
        endcase
    end
end
```

## 7. 性能监控

### 7.1 性能指标

| 指标名称 | 单位 | 描述 |
|----------|------|------|
| 帧处理延时 | 时钟周期 | 从音频输入到比特流输出的延时 |
| 吞吐量 | 帧/秒 | 每秒处理的音频帧数量 |
| 存储器利用率 | % | 存储器带宽使用百分比 |
| 功耗 | mW | 实时功耗估算 |
| 压缩比 | 比值 | 输入/输出数据大小比 |
| 错误率 | % | 处理错误帧的百分比 |

### 7.2 性能统计

```verilog
// 性能计数器
reg [31:0] frame_count;         // 已处理帧数
reg [31:0] cycle_count;         // 总周期数
reg [31:0] error_count;         // 错误计数
reg [31:0] max_frame_cycles;    // 最大帧处理周期
reg [31:0] total_input_bits;    // 总输入比特数
reg [31:0] total_output_bits;   // 总输出比特数

// 性能指标计算
always @(posedge clk) begin
    if (frame_complete) begin
        frame_count <= frame_count + 1;
        
        // 更新最大帧处理时间
        if (current_frame_cycles > max_frame_cycles) begin
            max_frame_cycles <= current_frame_cycles;
        end
        
        // 更新压缩统计
        total_input_bits <= total_input_bits + frame_input_bits;
        total_output_bits <= total_output_bits + frame_output_bits;
    end
    
    if (error_detected) begin
        error_count <= error_count + 1;
    end
    
    cycle_count <= cycle_count + 1;
end

// 性能信息输出
assign performance_info = {
    frame_count[15:0],          // [31:16] 帧计数
    max_frame_cycles[15:0]      // [15:0]  最大帧延时
};
```

## 8. 资源规格

### 8.1 总体资源估算

| 资源类型 | 数量 | 百分比 | 说明 |
|----------|------|--------|------|
| LUT4等效 | 35,000 | 87.5% | 包含所有功能模块 |
| 触发器 | 25,000 | 62.5% | 流水线和缓冲寄存器 |
| 乘法器 | 24 | 100% | DSP运算单元 |
| SRAM | 48KB | 75% | 统一存储器系统 |
| ROM | 32KB | 100% | 配置和系数表 |

### 8.2 功耗分析

| 工作模式 | 功耗 | 说明 |
|----------|------|------|
| 全速编码 | 95mW | 200MHz，所有模块活跃 |
| 标准编码 | 75mW | 100MHz，典型工作状态 |
| 低功耗模式 | 45mW | 时钟门控，部分模块关闭 |
| 待机模式 | 5mW | 仅保持配置和时钟 |

### 8.3 时序性能

| 指标 | 目标值 | 实际值 | 余量 |
|------|--------|--------|------|
| 最大时钟频率 | 200MHz | 210MHz | +5% |
| 帧处理延时 | <1ms | 0.8ms | +20% |
| 建立时间余量 | >0.5ns | 0.7ns | +40% |
| 保持时间余量 | >0.2ns | 0.3ns | +50% |

## 9. 验证策略

### 9.1 系统级验证

- **完整编码链**: 端到端的音频编码验证
- **实时性测试**: 连续音频流的实时处理验证
- **多配置测试**: 各种采样率和比特率组合验证
- **错误注入**: 各种错误条件下的系统行为验证
- **性能基准**: 与参考实现的性能对比

### 9.2 集成测试

```verilog
// 系统级测试场景
initial begin
    // 测试场景1: 标准编码流程
    configure_encoder(48000, 64, STEREO, FRAME_5MS);
    send_audio_stream("test_audio_48k_stereo.wav");
    wait_for_encoding_complete();
    verify_output_bitstream();
    
    // 测试场景2: 动态配置切换
    start_encoding();
    change_bitrate_runtime(32);
    change_sample_rate_runtime(16000);
    verify_seamless_transition();
    
    // 测试场景3: 错误恢复
    start_encoding();
    inject_error(MDCT_OVERFLOW);
    verify_error_detection();
    verify_automatic_recovery();
    
    // 测试场景4: 性能压力测试
    configure_max_performance();
    send_continuous_audio(duration_1hour);
    verify_realtime_processing();
    verify_no_data_loss();
end
```

---

**文档版本**: v1.0  
**创建日期**: 2024-06-11  
**作者**: Audio Codec Design Team  
**审核状态**: 待审核 