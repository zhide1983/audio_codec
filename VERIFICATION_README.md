# LC3plus编码器验证指南

## 概述

本项目提供了完整的LC3plus音频编码器硬件加速器设计和验证环境。支持完整的系统级验证，包括与参考C代码的比对。

## 项目结构

```
audio_codec/
├── rtl/                           # RTL设计文件
│   ├── processing/                # 处理模块
│   │   ├── mdct_transform.v       # MDCT变换模块
│   │   ├── spectral_analysis.v    # 频谱分析模块  
│   │   ├── quantization_control.v # 量化控制模块
│   │   ├── entropy_coding.v       # 熵编码模块
│   │   └── bitstream_packing.v    # 比特流打包模块
│   └── lc3plus_encoder_top.v      # 顶层集成模块
├── sim/                           # 仿真验证环境
│   ├── testbench/                 # 测试平台
│   ├── scripts/                   # 验证脚本
│   ├── test_vectors/              # 测试向量
│   ├── reference/                 # 参考数据
│   └── results/                   # 验证结果
├── docs/                          # 设计文档
└── LC3plus_ETSI_src_v17171_20200723/ # LC3plus参考C代码
```

## 系统要求

### 必需工具
- **Icarus Verilog** (iverilog) - 开源Verilog仿真器
- **GTKWave** (可选) - 波形查看器
- **Python 3.6+** (可选) - 用于高级验证脚本

### 安装方法

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install iverilog gtkwave python3 python3-pip
```

#### Windows (使用WSL)
```bash
# 在WSL中安装
sudo apt-get install iverilog gtkwave
```

#### macOS
```bash
brew install icarus-verilog gtkwave python3
```

## 快速开始

### 方法1: 使用自动化脚本 (推荐)

```bash
# 1. 进入项目根目录
cd audio_codec

# 2. 运行完整验证流程
./run_verification.sh
```

脚本将自动执行以下步骤：
1. ✅ 环境检查
2. ✅ RTL代码编译
3. ✅ 仿真运行
4. ✅ 结果分析
5. ✅ 报告生成

### 方法2: 手动验证步骤

如果需要更精细的控制，可以手动执行各个步骤：

#### 步骤1: 环境准备
```bash
# 创建必要目录
mkdir -p sim/results sim/test_vectors sim/reference

# 检查工具
iverilog -V
vvp -V
```

#### 步骤2: 编译RTL代码
```bash
cd sim

# 编译所有RTL文件
iverilog -g2012 -Wall \
    -o results/lc3plus_sim \
    testbench/tb_simple_encoder.sv \
    ../rtl/processing/mdct_transform.v \
    ../rtl/processing/spectral_analysis.v \
    ../rtl/processing/quantization_control.v \
    ../rtl/processing/entropy_coding.v \
    ../rtl/processing/bitstream_packing.v \
    ../rtl/lc3plus_encoder_top.v
```

#### 步骤3: 运行仿真
```bash
cd results

# 运行仿真 (带波形输出)
vvp lc3plus_sim +dump

# 或者运行仿真并保存日志
vvp lc3plus_sim +dump > simulation.log 2>&1
```

#### 步骤4: 查看结果
```bash
# 查看仿真日志
cat simulation.log

# 查看波形 (如果安装了GTKWave)
gtkwave tb_simple_encoder.vcd
```

## 验证内容

### 基本功能验证
- ✅ 6阶段流水线集成
- ✅ MDCT变换 (160/320/640点)
- ✅ 频谱分析和感知建模
- ✅ 自适应量化控制
- ✅ 算术编码压缩
- ✅ LC3plus比特流格式

### 性能验证
- ✅ 实时处理能力 (>1.0x)
- ✅ 压缩比目标 (>3:1)
- ✅ 延时控制 (<1ms)
- ✅ 功耗管理 (<100mW)

### 接口验证
- ✅ AXI4-Stream音频输入
- ✅ AXI4-Stream比特流输出
- ✅ APB配置接口
- ✅ 统一存储器接口

## 测试配置

### 支持的音频参数
| 参数 | 支持值 |
|------|--------|
| 采样率 | 16kHz, 24kHz, 48kHz |
| 帧长 | 5ms, 10ms |
| 比特率 | 16-320 kbps |
| 通道 | 单声道, 立体声 |

### 默认测试配置
- **采样率**: 16kHz
- **帧长**: 10ms  
- **比特率**: 32kbps
- **通道**: 单声道
- **测试帧数**: 10帧
- **测试信号**: 1kHz正弦波

## 输出文件

验证完成后，将在`sim/results/`目录下生成：

### 基本文件
- `lc3plus_sim` - 仿真可执行文件
- `simulation.log` - 详细仿真日志
- `verification_report.txt` - 验证报告

### 可选文件
- `tb_simple_encoder.vcd` - 波形文件
- `verification_report.json` - JSON格式报告

## 结果解读

### 成功标志
```
✅ 基本验证通过
LC3plus编码器能够正常编码音频数据
```

### 关键指标
- **压缩比**: 应 >2.5:1
- **完成帧数**: 应等于测试帧数
- **错误数量**: 应为0
- **输出字节数**: 应与目标比特率匹配

### 失败排查
如果验证失败，检查以下项目：

1. **编译错误**
   ```bash
   # 检查RTL语法
   iverilog -t null rtl/lc3plus_encoder_top.v
   ```

2. **仿真错误**
   ```bash
   # 查看详细错误信息
   grep -i error sim/results/simulation.log
   ```

3. **接口问题**
   ```bash
   # 检查波形文件中的握手信号
   gtkwave sim/results/tb_simple_encoder.vcd
   ```

## 高级验证

### 使用Python脚本
```bash
cd sim/scripts

# 生成测试向量
python3 generate_test_vectors.py

# 运行完整验证
python3 run_verification.py
```

### 自定义测试
修改`sim/testbench/tb_simple_encoder.sv`中的参数：
```systemverilog
parameter FRAME_SAMPLES = 240;     // 24kHz@10ms
parameter TEST_FRAMES = 50;        // 更多测试帧
```

### 多配置测试
```bash
# 测试不同配置
./run_verification.sh --config 48k_stereo
./run_verification.sh --config 24k_mono
```

## 性能优化

### 仿真加速
- 减少测试帧数
- 关闭波形输出
- 使用更快的仿真器

### 调试优化
- 启用详细日志
- 添加调试信号
- 使用断点功能

## 故障排除

### 常见问题

1. **找不到iverilog**
   ```bash
   sudo apt-get install iverilog
   ```

2. **编译失败**
   - 检查Verilog语法
   - 确认文件路径正确
   - 验证模块接口匹配

3. **仿真超时**
   - 检查时钟信号
   - 验证复位逻辑
   - 确认握手协议

4. **输出异常**
   - 检查测试激励
   - 验证模块参数
   - 确认数据路径

### 获取帮助
- 查看详细日志文件
- 检查波形文件
- 参考设计文档
- 联系开发团队

## 下一步工作

验证通过后，可以进行：
- ✅ FPGA原型实现
- ✅ 硬件验证测试
- ✅ 性能优化调整
- ✅ 产品化准备

---

**注意**: 本验证环境专门为LC3plus编码器设计，确保所有RTL模块已正确实现并符合LC3plus标准规范。 