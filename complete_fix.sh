#!/bin/bash

echo "=================================================="
echo "LC3plus编码器编译问题完整修复脚本"
echo "=================================================="

# 步骤1: 修复warning问题
echo "步骤1: 修复位选择警告..."

# 修复 mdct_transform.v 中的问题
echo "修复 mdct_transform.v..."
if grep -q "output_count\[15:0\]" rtl/processing/mdct_transform.v; then
    sed -i 's/output_count\[15:0\]/6'\''h0, output_count/g' rtl/processing/mdct_transform.v
    echo "  ✓ MDCT模块警告已修复"
else
    echo "  - MDCT模块无需修复"
fi

# 修复 spectral_analysis.v 中的问题
echo "修复 spectral_analysis.v..."
if grep -q "coefficient_count\[15:0\]" rtl/processing/spectral_analysis.v; then
    sed -i 's/coefficient_count\[15:0\]/6'\''h0, coefficient_count/g' rtl/processing/spectral_analysis.v
    echo "  ✓ 频谱分析模块警告已修复"
else
    echo "  - 频谱分析模块无需修复"
fi

# 步骤2: 选择正确的顶层文件
echo ""
echo "步骤2: 选择修复后的顶层文件..."

if [ -f "rtl/lc3plus_encoder_top_fixed.v" ]; then
    echo "使用 lc3plus_encoder_top_fixed.v"
    TOP_FILE="rtl/lc3plus_encoder_top_fixed.v"
elif [ -f "rtl/lc3plus_encoder_top_corrected.v" ]; then
    echo "使用 lc3plus_encoder_top_corrected.v"
    TOP_FILE="rtl/lc3plus_encoder_top_corrected.v"
else
    echo "警告: 找不到修复版本的顶层文件，使用原始文件"
    TOP_FILE="rtl/lc3plus_encoder_top.v"
fi

# 步骤3: 编译测试
echo ""
echo "步骤3: 编译测试..."
echo "编译命令: iverilog -g2012 -Wall -o sim/results/lc3plus_clean sim/testbench/tb_clean.sv $TOP_FILE rtl/processing/*.v"

# 创建结果目录
mkdir -p sim/results

# 执行编译
if iverilog -g2012 -Wall -o sim/results/lc3plus_clean \
    sim/testbench/tb_clean.sv \
    $TOP_FILE \
    rtl/processing/mdct_transform.v \
    rtl/processing/spectral_analysis.v \
    rtl/processing/quantization_control.v \
    rtl/processing/entropy_coding.v \
    rtl/processing/bitstream_packing.v; then
    
    echo ""
    echo "✅ 编译成功！"
    echo "可执行文件: sim/results/lc3plus_clean"
    
    # 步骤4: 运行基本仿真测试
    echo ""
    echo "步骤4: 运行基本仿真测试..."
    cd sim/results
    if vvp lc3plus_clean > simulation.log 2>&1; then
        echo "✅ 仿真运行成功！"
        echo "仿真日志: sim/results/simulation.log"
        
        # 检查仿真结果
        if grep -q "Reset released" simulation.log; then
            echo "  ✓ 复位正常"
        fi
        if grep -q "Generating test audio" simulation.log; then
            echo "  ✓ 测试音频生成成功"
        fi
        if grep -q "Configuring encoder" simulation.log; then
            echo "  ✓ 编码器配置成功"
        fi
        if grep -q "Audio data sent" simulation.log; then
            echo "  ✓ 音频数据传输成功"
        fi
        if grep -q "LC3plus Encoder Test Complete" simulation.log; then
            echo "  ✅ 测试完整运行"
        fi
        
        # 检查错误和警告
        error_count=$(grep -c "ERROR\|Error\|error" simulation.log || true)
        warning_count=$(grep -c "WARNING\|Warning\|warning" simulation.log || true)
        echo "  错误数量: $error_count"
        echo "  警告数量: $warning_count"
        
    else
        echo "❌ 仿真运行失败"
        echo "查看日志: sim/results/simulation.log"
        head -20 simulation.log
    fi
    cd ../..
    
else
    echo ""
    echo "❌ 编译失败"
    echo "请检查错误信息"
fi

echo ""
echo "=================================================="
echo "修复脚本执行完成"
echo "=================================================="

# 生成修复报告
cat > COMPILATION_FIX_REPORT.md << EOF
# LC3plus编码器编译修复报告

## 修复时间
$(date)

## 修复内容

### 1. 位选择警告修复
- **mdct_transform.v**: 修复 output_count[15:0] 选择超出范围问题
- **spectral_analysis.v**: 修复 coefficient_count[15:0] 选择超出范围问题

### 2. 顶层模块选择
- 使用的顶层文件: $TOP_FILE

### 3. 编译结果
$(if [ -f "sim/results/lc3plus_clean" ]; then echo "✅ 编译成功"; else echo "❌ 编译失败"; fi)

### 4. 仿真结果
$(if [ -f "sim/results/simulation.log" ]; then echo "✅ 仿真日志已生成"; else echo "❌ 仿真未运行"; fi)

## 使用说明

编译成功后，可以使用以下命令运行仿真：
\`\`\`bash
cd sim/results
vvp lc3plus_clean +dump
\`\`\`

## 文件清单

- sim/results/lc3plus_clean - 编译后的仿真可执行文件
- sim/results/simulation.log - 仿真运行日志
- COMPILATION_FIX_REPORT.md - 本修复报告

EOF

echo "修复报告已生成: COMPILATION_FIX_REPORT.md" 