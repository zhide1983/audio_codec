# Audio Codec Hardware Accelerator Project

## 项目概述

本项目旨在设计一个高性能的音频编解码器硬件加速器，支持LC3plus标准，并计划扩展到LC3和Opus标准。项目采用标准的IC设计流程，包含完整的设计文档、RTL实现和验证环境。

## 项目目标

- **主要目标**: 实现LC3plus音频编解码器的硬件加速
- **扩展目标**: 支持LC3和Opus标准
- **性能目标**: 实时编解码，低功耗，高吞吐量
- **验证目标**: 与官方参考代码完全兼容，比特精确匹配

## 支持的音频标准

### LC3plus (当前支持)
- 采样率: 8/16/24/32/44.1/48/96 kHz
- 帧长度: 2.5/5/10 ms
- 比特率: 16-1280 kbps per channel
- 支持多声道、高分辨率模式、丢包隐藏

### LC3 (计划扩展)
- 低复杂度通信编解码器

### Opus (计划扩展)
- 通用音频编解码器

## 项目结构

```
audio_codec/
├── README.md                          # 项目主文档
├── docs/                              # 设计文档目录
│   ├── architecture/                  # 架构设计文档
│   ├── specifications/                # 规格说明文档
│   ├── algorithms/                    # 算法分析文档
│   └── verification/                  # 验证方案文档
├── rtl/                              # RTL设计代码
│   ├── common/                       # 通用模块
│   ├── lc3plus/                      # LC3plus专用模块
│   ├── lc3/                          # LC3专用模块(未来)
│   ├── opus/                         # Opus专用模块(未来)
│   └── top/                          # 顶层集成
├── sim/                              # 仿真验证环境
│   ├── testbench/                    # 测试平台
│   ├── scripts/                      # 仿真脚本
│   ├── models/                       # 行为模型
│   └── results/                      # 仿真结果
├── sw/                               # 软件相关
│   ├── reference/                    # 参考实现
│   ├── tools/                        # 辅助工具
│   └── drivers/                      # 驱动程序
├── spec/                             # 标准协议文档
├── LC3plus_ETSI_src_v17171_20200723/ # 官方参考代码
└── scripts/                          # 项目脚本
    ├── build/                        # 构建脚本
    ├── test/                         # 测试脚本
    └── utils/                        # 实用工具
```

## 开发环境

- **操作系统**: Ubuntu Linux
- **仿真工具**: Icarus Verilog (iverilog)
- **波形查看**: GTKWave
- **构建工具**: Make, CMake
- **语言**: SystemVerilog/Verilog, C/C++, Python

## 验证策略

1. **单元测试**: 每个RTL模块的独立验证
2. **集成测试**: 子系统级验证
3. **系统测试**: 完整编解码器验证
4. **参考比对**: 与官方C代码比特精确匹配
5. **性能测试**: 时序、功耗、面积分析

## 快速开始

```bash
# 环境配置
make setup

# 构建参考模型
make reference

# 运行基础测试
make test

# 生成测试向量
make testvectors

# RTL仿真
make sim
```

## 项目状态

- [x] 项目架构设计
- [ ] LC3plus算法分析
- [ ] RTL架构设计
- [ ] 核心模块实现
- [ ] 验证环境搭建
- [ ] 系统集成测试
- [ ] 性能优化
- [ ] LC3扩展支持
- [ ] Opus扩展支持

## 贡献指南

请参考 `docs/development/CONTRIBUTING.md` 了解详细的开发流程和编码规范。

## 许可证

本项目遵循相关音频标准的许可协议，具体请参考各标准的官方文档。 