#!/bin/bash

#=============================================================================
# LC3plus编码器完整验证脚本
# 
# 功能：自动化执行LC3plus编码器的完整验证流程
# 作者：Audio Codec Design Team
# 版本：v1.0
# 日期：2024-06-11
#=============================================================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目路径
PROJECT_ROOT=$(pwd)
SIM_DIR="$PROJECT_ROOT/sim"
RTL_DIR="$PROJECT_ROOT/rtl"
RESULTS_DIR="$SIM_DIR/results"

# 创建必要目录
mkdir -p "$RESULTS_DIR"
mkdir -p "$SIM_DIR/test_vectors"
mkdir -p "$SIM_DIR/reference"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}LC3plus编码器完整验证流程${NC}"
echo -e "${BLUE}==================================================${NC}"
echo ""

#=============================================================================
# 步骤1: 环境检查
#=============================================================================

echo -e "${YELLOW}步骤1: 检查验证环境...${NC}"

# 检查仿真器
if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}错误: 找不到iverilog仿真器${NC}"
    echo "请安装Icarus Verilog: sudo apt-get install iverilog"
    exit 1
fi

# 检查RTL文件
rtl_files=(
    "$RTL_DIR/processing/mdct_transform.v"
    "$RTL_DIR/processing/spectral_analysis.v"
    "$RTL_DIR/processing/quantization_control.v"
    "$RTL_DIR/processing/entropy_coding.v"
    "$RTL_DIR/processing/bitstream_packing.v"
    "$RTL_DIR/lc3plus_encoder_top.v"
)

missing_files=()
for file in "${rtl_files[@]}"; do
    if [ ! -f "$file" ]; then
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -ne 0 ]; then
    echo -e "${RED}错误: 缺少RTL文件:${NC}"
    for file in "${missing_files[@]}"; do
        echo "  $file"
    done
    exit 1
fi

echo -e "${GREEN}✓ 环境检查通过${NC}"
echo ""

#=============================================================================
# 步骤2: 编译RTL代码
#=============================================================================

echo -e "${YELLOW}步骤2: 编译RTL代码...${NC}"

# 测试平台文件
TB_FILE="$SIM_DIR/testbench/tb_simple_encoder.sv"

# 检查测试平台文件
if [ ! -f "$TB_FILE" ]; then
    echo -e "${RED}错误: 找不到测试平台文件: $TB_FILE${NC}"
    exit 1
fi

# 编译命令
COMPILE_CMD="iverilog -g2012 -Wall -o $RESULTS_DIR/lc3plus_sim $TB_FILE"

# 添加RTL文件
for file in "${rtl_files[@]}"; do
    COMPILE_CMD="$COMPILE_CMD $file"
done

echo "编译命令: $COMPILE_CMD"

# 执行编译
if $COMPILE_CMD; then
    echo -e "${GREEN}✓ RTL代码编译成功${NC}"
else
    echo -e "${RED}✗ RTL代码编译失败${NC}"
    exit 1
fi

echo ""

#=============================================================================
# 步骤3: 运行仿真
#=============================================================================

echo -e "${YELLOW}步骤3: 运行仿真...${NC}"

cd "$RESULTS_DIR"

# 运行仿真
echo "开始仿真..."
if vvp lc3plus_sim +dump > simulation.log 2>&1; then
    echo -e "${GREEN}✓ 仿真完成${NC}"
else
    echo -e "${RED}✗ 仿真失败${NC}"
    echo "查看日志: $RESULTS_DIR/simulation.log"
    exit 1
fi

cd "$PROJECT_ROOT"
echo ""

#=============================================================================
# 步骤4: 分析结果
#=============================================================================

echo -e "${YELLOW}步骤4: 分析仿真结果...${NC}"

LOG_FILE="$RESULTS_DIR/simulation.log"

if [ ! -f "$LOG_FILE" ]; then
    echo -e "${RED}错误: 找不到仿真日志文件${NC}"
    exit 1
fi

# 分析日志
echo "分析仿真日志..."

# 检查是否有错误
error_count=$(grep -c "ERROR\|Error\|error" "$LOG_FILE" || true)
warning_count=$(grep -c "WARNING\|Warning\|warning" "$LOG_FILE" || true)

# 检查编码完成情况
completed_frames=$(grep -c "帧处理完成" "$LOG_FILE" || true)
verification_pass=$(grep -c "基本验证通过" "$LOG_FILE" || true)

echo "仿真结果分析:"
echo "  错误数量: $error_count"
echo "  警告数量: $warning_count"
echo "  完成帧数: $completed_frames"
echo "  验证状态: $([ $verification_pass -gt 0 ] && echo "通过" || echo "失败")"

# 提取关键信息
if grep -q "压缩比:" "$LOG_FILE"; then
    compression_ratio=$(grep "压缩比:" "$LOG_FILE" | tail -1 | sed 's/.*压缩比: \([0-9.]*\):.*/\1/')
    echo "  压缩比: ${compression_ratio}:1"
fi

if grep -q "实际输出字节数:" "$LOG_FILE"; then
    output_bytes=$(grep "实际输出字节数:" "$LOG_FILE" | tail -1 | sed 's/.*实际输出字节数: \([0-9]*\).*/\1/')
    echo "  输出字节数: $output_bytes"
fi

echo ""

#=============================================================================
# 步骤5: 生成验证报告
#=============================================================================

echo -e "${YELLOW}步骤5: 生成验证报告...${NC}"

REPORT_FILE="$RESULTS_DIR/verification_report.txt"

cat > "$REPORT_FILE" << EOF
=============================================================================
LC3plus编码器验证报告
=============================================================================

验证时间: $(date)
项目路径: $PROJECT_ROOT
仿真器: iverilog

=== 验证配置 ===
测试帧数: 10
采样率: 16kHz
帧长: 10ms
比特率: 32kbps
通道: 单声道

=== 仿真结果 ===
错误数量: $error_count
警告数量: $warning_count
完成帧数: $completed_frames
验证状态: $([ $verification_pass -gt 0 ] && echo "通过" || echo "失败")

=== 性能指标 ===
EOF

if [ -n "$compression_ratio" ]; then
    echo "压缩比: ${compression_ratio}:1" >> "$REPORT_FILE"
fi

if [ -n "$output_bytes" ]; then
    echo "输出字节数: $output_bytes" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" << EOF

=== 详细日志 ===
详细仿真日志请查看: $LOG_FILE

=== 波形文件 ===
EOF

if [ -f "$RESULTS_DIR/tb_simple_encoder.vcd" ]; then
    echo "波形文件: $RESULTS_DIR/tb_simple_encoder.vcd" >> "$REPORT_FILE"
    echo "查看波形: gtkwave $RESULTS_DIR/tb_simple_encoder.vcd" >> "$REPORT_FILE"
else
    echo "波形文件: 未生成" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" << EOF

=== 总体评估 ===
EOF

if [ $verification_pass -gt 0 ] && [ $error_count -eq 0 ] && [ $completed_frames -gt 0 ]; then
    echo "✅ LC3plus编码器验证通过" >> "$REPORT_FILE"
    echo "编码器能够正常处理音频数据并生成LC3plus比特流" >> "$REPORT_FILE"
    echo ""
    echo -e "${GREEN}✓ 验证报告生成完成${NC}"
    OVERALL_RESULT="PASS"
else
    echo "❌ LC3plus编码器验证失败" >> "$REPORT_FILE"
    echo "需要进一步调试和优化" >> "$REPORT_FILE"
    echo ""
    echo -e "${YELLOW}⚠ 验证报告生成完成 (有问题)${NC}"
    OVERALL_RESULT="FAIL"
fi

echo "报告文件: $REPORT_FILE"
echo ""

#=============================================================================
# 最终结果
#=============================================================================

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}验证结果总结${NC}"
echo -e "${BLUE}==================================================${NC}"
echo ""

echo "验证步骤:"
echo -e "  ✓ 环境检查"
echo -e "  ✓ RTL编译"
echo -e "  ✓ 仿真运行"
echo -e "  ✓ 结果分析"
echo -e "  ✓ 报告生成"
echo ""

echo "关键文件:"
echo "  仿真可执行文件: $RESULTS_DIR/lc3plus_sim"
echo "  仿真日志: $LOG_FILE"
echo "  验证报告: $REPORT_FILE"

if [ -f "$RESULTS_DIR/tb_simple_encoder.vcd" ]; then
    echo "  波形文件: $RESULTS_DIR/tb_simple_encoder.vcd"
fi

echo ""

if [ "$OVERALL_RESULT" = "PASS" ]; then
    echo -e "${GREEN}🎉 LC3plus编码器验证成功!${NC}"
    echo -e "${GREEN}编码器已准备好进行后续开发工作${NC}"
    exit 0
else
    echo -e "${RED}❌ LC3plus编码器验证失败${NC}"
    echo -e "${RED}请检查日志和报告以了解具体问题${NC}"
    echo ""
    echo "调试建议:"
    echo "1. 查看详细日志: cat $LOG_FILE"
    echo "2. 检查波形文件(如果存在): gtkwave $RESULTS_DIR/tb_simple_encoder.vcd"
    echo "3. 检查RTL代码中的错误信息"
    echo "4. 验证模块间接口连接"
    exit 1
fi 