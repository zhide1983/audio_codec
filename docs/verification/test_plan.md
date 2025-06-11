# 音频编解码器硬件加速器验证测试计划

## 1. 验证总体策略

### 1.1 验证目标

1. **功能正确性**: 确保RTL实现与参考代码功能一致
2. **比特精确性**: 编解码输出与参考代码逐比特匹配
3. **性能验证**: 满足实时处理性能要求
4. **鲁棒性验证**: 异常情况下的正确处理

### 1.2 验证层次

```
系统级验证 (Level 4)
├── 完整编解码流程验证
├── 多通道并行处理验证
└── 性能压力测试

子系统级验证 (Level 3)
├── LC3plus编码器验证
├── LC3plus解码器验证
└── 内存子系统验证

模块级验证 (Level 2)
├── MDCT/IMDCT模块验证
├── 量化/反量化模块验证
├── 霍夫曼编解码模块验证
└── 比特流处理模块验证

单元级验证 (Level 1)
├── DSP运算单元验证
├── 内存控制器验证
├── 寄存器接口验证
└── 时钟复位验证
```

## 2. 参考模型构建

### 2.1 Golden Model

基于官方LC3plus C代码构建参考模型：

```c
// 参考模型接口
typedef struct {
    int sample_rate;      // 采样率
    int bitrate;          // 比特率  
    int frame_length;     // 帧长度
    int channels;         // 通道数
    int bit_depth;        // 位深度
} lc3plus_config_t;

// 编码接口
int lc3plus_encode_ref(
    const int16_t* input_pcm,    // 输入PCM数据
    uint8_t* output_bitstream,   // 输出比特流
    lc3plus_config_t* config     // 配置参数
);

// 解码接口  
int lc3plus_decode_ref(
    const uint8_t* input_bitstream,  // 输入比特流
    int16_t* output_pcm,             // 输出PCM数据
    lc3plus_config_t* config         // 配置参数
);
```

### 2.2 测试向量生成

```python
# 测试向量生成脚本
def generate_test_vectors():
    configs = [
        # 不同采样率测试
        {'sample_rate': 16000, 'bitrate': 32000, 'frame_length': 160},
        {'sample_rate': 48000, 'bitrate': 64000, 'frame_length': 480},
        
        # 不同比特率测试
        {'sample_rate': 48000, 'bitrate': 96000, 'frame_length': 480},
        {'sample_rate': 48000, 'bitrate': 128000, 'frame_length': 480},
        
        # 边界条件测试
        {'sample_rate': 8000, 'bitrate': 16000, 'frame_length': 80},
        {'sample_rate': 96000, 'bitrate': 320000, 'frame_length': 960},
    ]
    
    test_signals = [
        'sine_wave',      # 正弦波
        'white_noise',    # 白噪声  
        'chirp',          # 扫频信号
        'speech',         # 语音信号
        'music',          # 音乐信号
        'silence',        # 静音
    ]
    
    return generate_combinations(configs, test_signals)
```

## 3. 验证环境架构

### 3.1 测试平台架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Verification Environment                │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Test Cases  │  │ Reference   │  │   Test Vector       │ │
│  │ Generator   │  │   Model     │  │    Database         │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Testbench   │  │  Checker    │  │    Coverage         │ │
│  │ Controller  │  │   Engine    │  │   Collector         │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              DUT (Design Under Test)                   │ │
│  │          Audio Codec Hardware Accelerator              │ │
│  └─────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Waveform    │  │   Report    │  │     Debug           │ │
│  │ Dumper      │  │ Generator   │  │    Interface        │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 测试框架实现

```verilog
// 主测试平台
module tb_audio_codec;
    // 时钟和复位
    reg clk;
    reg rst_n;
    
    // AXI接口
    axi4_if axi_if();
    
    // DUT实例化
    audio_codec_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .axi_if(axi_if)
    );
    
    // 测试控制器
    test_controller test_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .axi_if(axi_if)
    );
    
    // 参考模型
    reference_model ref_model (
        .clk(clk),
        .rst_n(rst_n)
    );
    
    // 比较器
    result_checker checker (
        .dut_output(dut.output_data),
        .ref_output(ref_model.output_data),
        .match(result_match)
    );
    
    // 覆盖率收集
    covergroup lc3plus_coverage;
        sample_rate: coverpoint test_ctrl.config.sample_rate {
            bins rates[] = {8000, 16000, 24000, 32000, 44100, 48000, 96000};
        }
        bitrate: coverpoint test_ctrl.config.bitrate {
            bins low = {[16000:32000]};
            bins mid = {[32001:128000]};
            bins high = {[128001:320000]};
        }
        frame_length: coverpoint test_ctrl.config.frame_length {
            bins short = {[80:160]};
            bins medium = {[240:480]};
            bins long = {[720:960]};
        }
    endgroup
    
endmodule
```

## 4. 测试用例设计

### 4.1 基础功能测试

#### 4.1.1 编码器测试
```python
class EncoderTests:
    def test_basic_encoding(self):
        """基础编码功能测试"""
        for config in test_configs:
            pcm_data = generate_test_pcm(config)
            
            # RTL编码
            rtl_bitstream = rtl_encode(pcm_data, config)
            
            # 参考编码
            ref_bitstream = ref_encode(pcm_data, config)
            
            # 比特流比较
            assert bitstream_compare(rtl_bitstream, ref_bitstream)
    
    def test_boundary_conditions(self):
        """边界条件测试"""
        test_cases = [
            {'type': 'silence', 'duration': 1000},
            {'type': 'max_amplitude', 'duration': 1000},
            {'type': 'dc_signal', 'duration': 1000},
        ]
        
        for case in test_cases:
            self.verify_encoding(case)
```

#### 4.1.2 解码器测试
```python
class DecoderTests:
    def test_basic_decoding(self):
        """基础解码功能测试"""
        for config in test_configs:
            # 使用参考编码器生成比特流
            bitstream = ref_encode(test_pcm, config)
            
            # RTL解码
            rtl_pcm = rtl_decode(bitstream, config)
            
            # 参考解码
            ref_pcm = ref_decode(bitstream, config)
            
            # PCM数据比较
            assert pcm_compare(rtl_pcm, ref_pcm, tolerance=1)
    
    def test_error_concealment(self):
        """错误隐藏测试"""
        # 丢包测试
        for loss_rate in [1, 5, 10, 20]:  # 丢包率%
            self.verify_packet_loss(loss_rate)
```

### 4.2 随机化测试

```python
class RandomizedTests:
    def test_random_configs(self):
        """随机配置测试"""
        for i in range(1000):
            config = generate_random_config()
            pcm_data = generate_random_pcm(config)
            
            # 编码-解码循环测试
            bitstream = rtl_encode(pcm_data, config)
            decoded_pcm = rtl_decode(bitstream, config)
            
            # 质量评估
            snr = calculate_snr(pcm_data, decoded_pcm)
            assert snr > min_snr_threshold
    
    def test_stress_conditions(self):
        """压力测试"""
        # 连续处理大量帧
        # 快速配置切换
        # 内存压力测试
        pass
```

### 4.3 性能测试

```python
class PerformanceTests:
    def test_latency(self):
        """延迟测试"""
        # 测量端到端延迟
        latency = measure_processing_latency()
        assert latency < max_allowed_latency
    
    def test_throughput(self):
        """吞吐量测试"""
        # 多通道并行处理
        throughput = measure_multi_channel_throughput()
        assert throughput >= target_throughput
    
    def test_power_consumption(self):
        """功耗测试"""
        # 动态功耗测量
        power = measure_dynamic_power()
        assert power < max_power_budget
```

## 5. 验证基础设施

### 5.1 仿真脚本

```makefile
# Makefile for verification
VERILOG_FILES = $(shell find ../rtl -name "*.v" -o -name "*.sv")
TB_FILES = $(shell find . -name "tb_*.sv")

# 基础仿真
sim_basic:
	iverilog -g2012 -o sim_basic $(VERILOG_FILES) tb_basic.sv
	./sim_basic
	gtkwave tb_basic.vcd &

# 回归测试
regression:
	python3 scripts/run_regression.py

# 覆盖率分析
coverage:
	python3 scripts/coverage_analysis.py

# 性能分析
performance:
	python3 scripts/performance_analysis.py

clean:
	rm -f *.vcd *.out sim_* 
	rm -rf results/
```

### 5.2 自动化测试脚本

```python
#!/usr/bin/env python3
# run_regression.py

import os
import subprocess
import json
from datetime import datetime

class RegressionRunner:
    def __init__(self):
        self.test_suite = [
            'test_basic_encoder',
            'test_basic_decoder', 
            'test_random_configs',
            'test_boundary_conditions',
            'test_error_handling',
        ]
        
    def run_test(self, test_name):
        """运行单个测试"""
        cmd = f"iverilog -g2012 -o {test_name} {test_name}.sv"
        result = subprocess.run(cmd, shell=True, capture_output=True)
        
        if result.returncode == 0:
            # 运行仿真
            sim_result = subprocess.run(f"./{test_name}", 
                                      capture_output=True, text=True)
            return self.parse_result(sim_result.stdout)
        else:
            return {'status': 'COMPILE_ERROR', 'error': result.stderr}
    
    def run_all_tests(self):
        """运行所有测试"""
        results = {}
        
        for test in self.test_suite:
            print(f"Running {test}...")
            results[test] = self.run_test(test)
            
        self.generate_report(results)
        return results
    
    def generate_report(self, results):
        """生成测试报告"""
        report = {
            'timestamp': datetime.now().isoformat(),
            'summary': self.summarize_results(results),
            'details': results
        }
        
        with open('test_report.json', 'w') as f:
            json.dump(report, f, indent=2)

if __name__ == "__main__":
    runner = RegressionRunner()
    runner.run_all_tests()
```

## 6. 验证检查点

### 6.1 功能验证里程碑

1. **阶段1**: 基础模块验证 (Week 1-2)
   - [ ] DSP运算单元验证通过
   - [ ] 内存接口验证通过
   - [ ] 寄存器访问验证通过

2. **阶段2**: 核心算法验证 (Week 3-4)
   - [ ] MDCT/IMDCT模块验证通过
   - [ ] 量化模块比特精确匹配
   - [ ] 霍夫曼编解码验证通过

3. **阶段3**: 编解码器验证 (Week 5-6)
   - [ ] LC3plus编码器功能验证
   - [ ] LC3plus解码器功能验证
   - [ ] 端到端编解码验证

4. **阶段4**: 系统验证 (Week 7-8)
   - [ ] 多通道并行处理验证
   - [ ] 性能指标达成验证
   - [ ] 鲁棒性测试通过

### 6.2 验证质量标准

- **代码覆盖率**: >95%
- **功能覆盖率**: >90%
- **比特精确率**: 100%
- **回归测试通过率**: >99% 