# 音频编解码器硬件加速器接口需求规范

## 1. 总线接口要求

### 1.1 主存储器接口 (Master Interface)

#### 1.1.1 接口选择
- **支持总线类型**: AXI4 / AHB
- **配置方式**: 编译时参数选择
- **数据位宽**: 32位
- **地址位宽**: 32位
- **接口角色**: 音频codec模块作为Master

#### 1.1.2 功能用途
- 音频数据读取（PCM输入数据）
- 编码结果写入（比特流输出）
- 解码结果写入（PCM输出数据）
- DMA数据传输控制

#### 1.1.3 性能要求
- **AXI4模式**: 
  - 支持突发传输（Burst）
  - 支持Outstanding事务
  - 支持写响应缓存
- **AHB模式**:
  - 支持连续传输
  - 支持忙等待处理
  - 支持错误响应

### 1.2 寄存器配置接口 (Slave Interface)

#### 1.2.1 接口规范
- **总线类型**: APB (Advanced Peripheral Bus)
- **数据位宽**: 32位
- **地址位宽**: 32位（字节寻址）
- **接口角色**: 音频codec模块作为Slave

#### 1.2.2 功能用途
- 模块配置参数设置
- 运行状态监控
- 中断状态管理
- 调试信息读取

#### 1.2.3 访问特性
- 所有寄存器32位对齐
- 支持字节、半字、全字访问
- 读写权限可配置
- 支持保留位处理

## 2. 寄存器配置管理

### 2.1 JSON配置规范

#### 2.1.1 配置文件结构
```json
{
  "register_map": {
    "version": "1.0.0",
    "description": "Audio Codec Register Map",
    "base_address": "0x00000000",
    "address_width": 32,
    "data_width": 32,
    "byte_addressing": true,
    "registers": [
      // 寄存器定义数组
    ]
  }
}
```

#### 2.1.2 寄存器定义格式
```json
{
  "name": "REG_NAME",
  "address": "0x0000",
  "reset_value": "0x00000000",
  "description": "Register description",
  "access": "RW",
  "fields": [
    {
      "name": "FIELD_NAME",
      "bits": "31:0",
      "access": "RW",
      "reset_value": "0x0",
      "description": "Field description"
    }
  ]
}
```

### 2.2 版本信息要求

#### 2.2.1 版本寄存器
- **地址**: 0x0000 (ID寄存器)
- **格式**: [31:16] = 版本号, [15:8] = 子版本, [7:0] = 修订号
- **访问**: 只读
- **用途**: 软件兼容性检查

#### 2.2.2 功能寄存器
- **地址**: 0x0004 (FEATURE寄存器)  
- **格式**: 各位表示支持的功能特性
- **访问**: 只读
- **用途**: 运行时功能检测

## 3. 接口设计规范

### 3.1 顶层模块接口

#### 3.1.1 通用参数
```systemverilog
parameter BUS_TYPE = "AXI4";        // "AXI4" or "AHB"
parameter ADDR_WIDTH = 32;          // 地址位宽
parameter DATA_WIDTH = 32;          // 数据位宽
parameter MASTER_ID_WIDTH = 4;      // Master ID位宽
```

#### 3.1.2 AXI4接口端口
```systemverilog
// AXI4 Master Interface (当BUS_TYPE = "AXI4"时有效)
output logic [MASTER_ID_WIDTH-1:0]   m_axi_awid,
output logic [ADDR_WIDTH-1:0]        m_axi_awaddr,
output logic [7:0]                   m_axi_awlen,
output logic [2:0]                   m_axi_awsize,
output logic [1:0]                   m_axi_awburst,
output logic                         m_axi_awvalid,
input  logic                         m_axi_awready,
// ... 其他AXI信号
```

#### 3.1.3 AHB接口端口  
```systemverilog
// AHB Master Interface (当BUS_TYPE = "AHB"时有效)
output logic [ADDR_WIDTH-1:0]        m_ahb_haddr,
output logic [2:0]                   m_ahb_hsize,
output logic [1:0]                   m_ahb_htrans,
output logic [DATA_WIDTH-1:0]        m_ahb_hwdata,
output logic                         m_ahb_hwrite,
input  logic [DATA_WIDTH-1:0]        m_ahb_hrdata,
input  logic                         m_ahb_hready,
input  logic [1:0]                   m_ahb_hresp,
// ... 其他AHB信号
```

#### 3.1.4 APB接口端口
```systemverilog
// APB Slave Interface
input  logic [ADDR_WIDTH-1:0]        s_apb_paddr,
input  logic                         s_apb_psel,
input  logic                         s_apb_penable,
input  logic                         s_apb_pwrite,
input  logic [DATA_WIDTH-1:0]        s_apb_pwdata,
input  logic [DATA_WIDTH/8-1:0]      s_apb_pstrb,
output logic [DATA_WIDTH-1:0]        s_apb_prdata,
output logic                         s_apb_pready,
output logic                         s_apb_pslverr,
```

### 3.2 总线适配器设计

#### 3.2.1 Master总线适配器
- **AXI4适配器**: 将内部请求转换为AXI4协议
- **AHB适配器**: 将内部请求转换为AHB协议
- **统一内部接口**: 屏蔽外部总线差异

#### 3.2.2 APB寄存器适配器
- **地址解码**: 根据JSON配置自动生成
- **访问控制**: 支持读写权限检查
- **数据处理**: 支持字节、半字、全字访问

## 4. 实现要求

### 4.1 编译时配置

#### 4.1.1 总线选择参数
```systemverilog
// 在顶层模块或package中定义
parameter string BUS_TYPE = "AXI4";  // 或 "AHB"

// 条件编译示例
generate
  if (BUS_TYPE == "AXI4") begin : gen_axi_master
    axi4_master_adapter u_master_adapter (...);
  end else if (BUS_TYPE == "AHB") begin : gen_ahb_master  
    ahb_master_adapter u_master_adapter (...);
  end
endgenerate
```

#### 4.1.2 寄存器映射生成
- 基于JSON配置自动生成寄存器RTL代码
- 生成对应的C头文件
- 生成文档和验证用例

### 4.2 设计约束

#### 4.2.1 时序要求
- APB访问延迟: ≤ 2个时钟周期
- Master总线仲裁延迟: ≤ 4个时钟周期  
- 寄存器更新延迟: ≤ 1个时钟周期

#### 4.2.2 面积约束
- 总线适配器开销: ≤ 5% 总面积
- 寄存器银行开销: ≤ 3% 总面积

### 4.3 验证要求

#### 4.3.1 接口验证
- AXI4/AHB协议一致性检查
- APB协议一致性检查
- 总线切换功能验证

#### 4.3.2 寄存器验证
- 所有寄存器读写功能验证
- 访问权限验证
- 复位值验证
- 保留位行为验证

## 5. 工具支持

### 5.1 寄存器代码生成工具

#### 5.1.1 输入文件
- JSON寄存器定义文件
- 模板文件（SystemVerilog, C头文件等）

#### 5.1.2 输出文件
- SystemVerilog寄存器模块
- C/C++头文件定义
- Python测试脚本
- 寄存器文档（Markdown/HTML）

### 5.2 验证支持工具

#### 5.2.1 协议检查器
- AXI4 Protocol Checker
- AHB Protocol Checker  
- APB Protocol Checker

#### 5.2.2 覆盖率收集
- 寄存器访问覆盖率
- 总线事务覆盖率
- 功能覆盖率点

## 6. 应用示例

### 6.1 SoC集成示例

```systemverilog
// SoC中的集成示例
audio_codec_top #(
  .BUS_TYPE("AXI4"),
  .ADDR_WIDTH(32),
  .DATA_WIDTH(32)
) u_audio_codec (
  // 时钟复位
  .clk(codec_clk),
  .rst_n(codec_rst_n),
  
  // AXI4 Master接口连接到Memory Controller
  .m_axi_*(m_axi_codec_*),
  
  // APB Slave接口连接到APB总线
  .s_apb_*(s_apb_codec_*),
  
  // 其他信号
  .irq(codec_irq)
);
```

### 6.2 软件配置示例

```c
// 软件配置示例
#include "audio_codec_regs.h"

// 检查版本兼容性
uint32_t version = read_reg(AUDIO_CODEC_BASE + REG_VERSION);
if (GET_VERSION_MAJOR(version) != EXPECTED_MAJOR_VERSION) {
  // 版本不兼容处理
}

// 配置编码器
write_reg(AUDIO_CODEC_BASE + REG_SAMPLE_RATE, 48000);
write_reg(AUDIO_CODEC_BASE + REG_BITRATE, 64000);
write_reg(AUDIO_CODEC_BASE + REG_CONTROL, CTRL_ENCODE_EN);
```

## 7. 更新历史

| 版本 | 日期 | 修改内容 | 修改人 |
|------|------|----------|--------|
| 1.0 | 2024-06-11 | 初始版本，定义基本接口要求 | 设计团队 |

---

**注意**: 本规范会根据项目进展和需求变化进行持续更新，请关注版本变化。 