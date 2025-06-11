# 音频编解码器接口需求更新总结

## 更新概述

根据项目需求，对音频编解码器硬件加速器的接口设计进行了重要更新，以提高设计的通用性和SoC集成便利性。

## 主要更新内容

### 1. 总线接口增强 🚌

#### 1.1 主存储器接口可配置化
- **新增功能**: 支持AXI4和AHB两种总线协议
- **配置方式**: 编译时参数选择 `BUS_TYPE = "AXI4"` 或 `"AHB"`
- **接口角色**: 音频codec作为Master，用于内存读写
- **统一规格**: 32位地址总线，32位数据总线

#### 1.2 专用寄存器配置接口
- **新增接口**: APB (Advanced Peripheral Bus) Slave接口
- **专用用途**: 寄存器配置、状态监控、中断管理
- **标准规格**: 32位地址总线，32位数据总线，字节寻址

### 2. 寄存器管理现代化 📋

#### 2.1 JSON配置驱动
- **配置文件**: `docs/specifications/register_map.json`
- **管理方式**: 统一的JSON格式定义所有寄存器
- **版本控制**: 包含版本信息，支持软件兼容性检查
- **自动生成**: RTL代码、C头文件、测试脚本自动生成

#### 2.2 规范化寄存器定义
- **地址对齐**: 所有寄存器32位对齐，字节寻址
- **访问权限**: RO, RW, WO, RW1C等标准权限
- **字段定义**: 支持位域定义和描述
- **复位值**: 明确的复位值定义

### 3. 架构设计优化 🏗️

#### 3.1 模块化总线适配器
```systemverilog
// 编译时总线选择
generate
  if (BUS_TYPE == "AXI4") begin : gen_axi_master
    axi4_master_adapter u_master_adapter (...);
  end else if (BUS_TYPE == "AHB") begin : gen_ahb_master  
    ahb_master_adapter u_master_adapter (...);
  end
endgenerate
```

#### 3.2 统一内部接口
- **抽象层**: 统一的内部存储器接口
- **协议无关**: 处理核心与外部总线解耦
- **易于扩展**: 支持未来新总线协议

## 详细技术规范

### 1. 接口信号定义

#### 1.1 APB Slave接口
```systemverilog
// APB Slave Interface
input  logic [ADDR_WIDTH-1:0]      s_apb_paddr,
input  logic                       s_apb_psel,
input  logic                       s_apb_penable,
input  logic                       s_apb_pwrite,
input  logic [DATA_WIDTH-1:0]      s_apb_pwdata,
input  logic [DATA_WIDTH/8-1:0]    s_apb_pstrb,
output logic [DATA_WIDTH-1:0]      s_apb_prdata,
output logic                       s_apb_pready,
output logic                       s_apb_pslverr,
```

#### 1.2 可配置Master接口
- **AXI4模式**: 完整的AXI4 Master接口信号
- **AHB模式**: 标准的AHB Master接口信号
- **自动选择**: 根据BUS_TYPE参数自动启用对应接口

### 2. 寄存器映射详情

#### 2.1 关键寄存器
| 地址 | 寄存器 | 功能 | 访问 |
|------|--------|------|------|
| 0x0000 | REG_VERSION | 版本信息 (Major.Minor.Patch) | RO |
| 0x0004 | REG_FEATURE | 功能特性位图 | RO |
| 0x0008 | REG_CONTROL | 编解码控制、启动等 | RW |
| 0x000C | REG_STATUS | 运行状态监控 | RO |
| 0x0010 | REG_IRQ_STATUS | 中断状态 (写1清除) | RW1C |
| 0x0014 | REG_IRQ_MASK | 中断屏蔽控制 | RW |

#### 2.2 配置寄存器
| 地址 | 寄存器 | 功能 | 默认值 |
|------|--------|------|--------|
| 0x0020 | REG_SAMPLE_RATE | 采样率 (Hz) | 48000 |
| 0x0024 | REG_BITRATE | 比特率 (bps) | 64000 |
| 0x0028 | REG_FRAME_LEN | 帧长度 (samples) | 480 |
| 0x002C | REG_CHANNELS | 通道数 (1-8) | 1 |

#### 2.3 缓冲区管理
| 地址 | 寄存器 | 功能 |
|------|--------|------|
| 0x0030 | REG_INPUT_ADDR | 输入缓冲区地址 |
| 0x0034 | REG_OUTPUT_ADDR | 输出缓冲区地址 |
| 0x0038 | REG_BUFFER_SIZE | 缓冲区大小配置 |

### 3. 版本管理策略

#### 3.1 版本寄存器格式
```
REG_VERSION [31:0]
├─ [31:16] MAJOR_VER: 主版本号
├─ [15:8]  MINOR_VER: 子版本号  
└─ [7:0]   PATCH_VER: 修订版本号
```

#### 3.2 功能特性寄存器
```
REG_FEATURE [31:0]
├─ [7] OPUS_SUPPORT: Opus编解码支持
├─ [6] LC3_SUPPORT: LC3编解码支持
├─ [5] LC3PLUS_SUPPORT: LC3plus编解码支持
├─ [4] AHB_SUPPORT: AHB接口支持
├─ [3] AXI4_SUPPORT: AXI4接口支持
├─ [2] DECODE_SUPPORT: 解码器支持
├─ [1] ENCODE_SUPPORT: 编码器支持
└─ [0] MULTI_CHANNEL: 多通道支持
```

## 工具链支持

### 1. 寄存器代码生成工具

#### 1.1 功能特性
- **输入**: JSON寄存器定义文件
- **输出**: SystemVerilog模块、C头文件、Python测试、文档
- **自动化**: 完全自动化的代码生成流程

#### 1.2 使用方法
```bash
# 生成所有寄存器相关文件
make generate_regs

# 手动调用生成工具
python3 scripts/utils/gen_registers.py docs/specifications/register_map.json -o rtl/generated
```

#### 1.3 生成文件
- `audio_codec_regs.sv` - SystemVerilog寄存器模块
- `audio_codec_regs.h` - C/C++头文件定义
- `test_audio_codec_regs.py` - Python测试脚本
- `audio_codec_register_map.md` - 详细文档

### 2. 验证增强

#### 2.1 协议检查
- AXI4 Protocol Checker集成
- AHB Protocol Checker集成
- APB Protocol Checker集成

#### 2.2 接口测试
- 总线切换功能验证
- 寄存器访问权限测试
- 协议一致性验证

## SoC集成优势

### 1. 灵活的总线适配 🔧

#### 1.1 编译时配置
```systemverilog
// SoC集成示例 - AXI4配置
audio_codec_top #(
  .BUS_TYPE("AXI4"),
  .ADDR_WIDTH(32),
  .DATA_WIDTH(32)
) u_audio_codec (
  .clk(codec_clk),
  .rst_n(codec_rst_n),
  .m_axi_*(axi_interconnect_*),  // 连接到AXI互连
  .s_apb_*(apb_codec_*),         // 连接到APB总线
  .irq(codec_irq)
);
```

#### 1.2 AHB配置示例
```systemverilog
// SoC集成示例 - AHB配置  
audio_codec_top #(
  .BUS_TYPE("AHB"),
  .ADDR_WIDTH(32),
  .DATA_WIDTH(32)
) u_audio_codec (
  .clk(codec_clk),
  .rst_n(codec_rst_n),
  .m_ahb_*(ahb_matrix_*),        // 连接到AHB矩阵
  .s_apb_*(apb_codec_*),         // 连接到APB总线
  .irq(codec_irq)
);
```

### 2. 标准化软件接口 💻

#### 2.1 驱动程序示例
```c
#include "audio_codec_regs.h"

int audio_codec_init(uintptr_t base_addr) {
    // 检查版本兼容性
    uint32_t version = AUDIO_CODEC_READ(base_addr, REG_VERSION);
    if (REG_VERSION_MAJOR_VER_GET(version) != 1) {
        return -1; // 版本不兼容
    }
    
    // 检查功能支持
    uint32_t features = AUDIO_CODEC_READ(base_addr, REG_FEATURE);
    if (!(features & REG_FEATURE_LC3PLUS_SUPPORT_MASK)) {
        return -2; // 不支持LC3plus
    }
    
    // 基础配置
    AUDIO_CODEC_WRITE(base_addr, REG_SAMPLE_RATE, 48000);
    AUDIO_CODEC_WRITE(base_addr, REG_BITRATE, 64000);
    AUDIO_CODEC_WRITE(base_addr, REG_CHANNELS, 1);
    
    return 0;
}
```

### 3. 中断处理优化 ⚡

#### 3.1 分离的中断控制
- 独立的中断状态寄存器
- 可配置的中断屏蔽
- 写1清除的中断标志

#### 3.2 中断处理示例
```c
void audio_codec_irq_handler(uintptr_t base_addr) {
    uint32_t irq_status = AUDIO_CODEC_READ(base_addr, REG_IRQ_STATUS);
    
    if (irq_status & REG_IRQ_STATUS_FRAME_DONE_IRQ_MASK) {
        // 处理帧完成中断
        handle_frame_done();
        // 清除中断标志
        AUDIO_CODEC_WRITE(base_addr, REG_IRQ_STATUS, REG_IRQ_STATUS_FRAME_DONE_IRQ_MASK);
    }
    
    if (irq_status & REG_IRQ_STATUS_ERROR_IRQ_MASK) {
        // 处理错误中断
        handle_error();
        AUDIO_CODEC_WRITE(base_addr, REG_IRQ_STATUS, REG_IRQ_STATUS_ERROR_IRQ_MASK);
    }
}
```

## 实施计划

### 阶段1: 基础架构实现 (Week 1-2)
- [ ] 实现APB slave接口模块
- [ ] 实现AXI4/AHB master适配器
- [ ] 完善寄存器代码生成工具
- [ ] 生成初始寄存器文件

### 阶段2: 集成验证 (Week 3-4)  
- [ ] 更新顶层模块集成
- [ ] 实现总线协议检查器
- [ ] 完成基础接口验证
- [ ] 软件驱动程序开发

### 阶段3: 完整测试 (Week 5-6)
- [ ] 端到端接口测试
- [ ] 多总线配置验证  
- [ ] 性能基准测试
- [ ] 文档完善

## 预期收益

### 1. 技术收益 📈
- **更好的SoC集成**: 支持主流总线协议
- **标准化接口**: 符合行业标准的APB寄存器接口
- **维护性提升**: JSON配置驱动的寄存器管理
- **扩展性增强**: 易于添加新功能和寄存器

### 2. 开发效率提升 ⚡
- **自动化工具**: 寄存器代码自动生成
- **一致性保证**: 硬件和软件接口自动同步
- **验证完整**: 协议级验证和功能测试
- **文档同步**: 自动生成的最新文档

### 3. 产业化优势 🏭
- **广泛兼容**: 支持不同SoC平台的总线架构
- **标准合规**: 遵循ARM AMBA标准
- **软件生态**: 标准化的驱动和API接口
- **版本管理**: 完善的版本控制和兼容性机制

---

**更新状态**: 接口需求分析完成，设计规范已制定，工具链已开发，可以开始具体实现工作。 