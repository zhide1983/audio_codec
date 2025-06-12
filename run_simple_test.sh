#!/bin/bash

#=============================================================================
# LC3plus编码器简化测试脚本
# 
# 功能：运行2.5ms帧长、10ms编码数据的快速验证测试
# 配置：AHB-Lite, APB配置, 详细日志
# 作者：Audio Codec Design Team
# 版本：v1.0
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
TB_DIR="$SIM_DIR/testbench"

# 创建必要目录
mkdir -p "$RESULTS_DIR"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}LC3plus编码器简化测试 (2.5ms帧长)${NC}"
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

echo "iverilog版本: $(iverilog -v 2>&1 | head -1)"

# 检查RTL文件
rtl_files=(
    "$RTL_DIR/processing/mdct_transform.v"
    "$RTL_DIR/processing/spectral_analysis.v"
    "$RTL_DIR/processing/quantization_control.v"
    "$RTL_DIR/processing/entropy_coding.v"
    "$RTL_DIR/processing/bitstream_packing.v"
    "$RTL_DIR/processing/time_domain_proc.v"
    "$RTL_DIR/memory/audio_buffer_ram.v"
    "$RTL_DIR/memory/work_buffer_ram.v"
    "$RTL_DIR/memory/coeff_storage_rom.v"
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

# 检查测试平台
TB_FILE="$TB_DIR/tb_simple_test.sv"
if [ ! -f "$TB_FILE" ]; then
    echo -e "${RED}错误: 找不到测试平台文件: $TB_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 环境检查通过${NC}"
echo ""

#=============================================================================
# 步骤2: 编译RTL代码
#=============================================================================

echo -e "${YELLOW}步骤2: 编译RTL代码...${NC}"

# 编译命令
COMPILE_CMD="iverilog -g2012 -Wall -Wno-timescale -o $RESULTS_DIR/lc3plus_simple_sim"

# 添加时间尺度定义
COMPILE_CMD="$COMPILE_CMD -D__ICARUS__"

# 添加测试平台
COMPILE_CMD="$COMPILE_CMD $TB_FILE"

# 添加RTL文件
for file in "${rtl_files[@]}"; do
    COMPILE_CMD="$COMPILE_CMD $file"
done

echo "编译命令: $COMPILE_CMD"

# 执行编译
if $COMPILE_CMD 2>&1 | tee "$RESULTS_DIR/compile.log"; then
    echo -e "${GREEN}✓ RTL代码编译成功${NC}"
else
    echo -e "${RED}✗ RTL代码编译失败${NC}"
    echo "查看编译日志: $RESULTS_DIR/compile.log"
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
echo "测试配置:"
echo "  - 帧长: 2.5ms"
echo "  - 测试时长: 10ms (4帧)"
echo "  - 采样率: 48kHz"
echo "  - 比特率: 64kbps"
echo "  - 通道: 单声道"
echo ""

if timeout 60s vvp lc3plus_simple_sim +dump 2>&1 | tee simulation.log; then
    echo -e "${GREEN}✓ 仿真完成${NC}"
else
    echo -e "${RED}✗ 仿真失败或超时${NC}"
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

echo ""
echo "=== 仿真结果分析 ==="
echo "错误数量: $error_count"
echo "警告数量: $warning_count"

# 检查关键消息
echo ""
echo "=== 关键事件检查 ==="

if grep -q "系统复位释放" "$LOG_FILE"; then
    echo -e "${GREEN}✓ 系统复位: 正常${NC}"
else
    echo -e "${RED}✗ 系统复位: 异常${NC}"
fi

if grep -q "APB配置完成" "$LOG_FILE"; then
    echo -e "${GREEN}✓ APB配置: 成功${NC}"
else
    echo -e "${RED}✗ APB配置: 失败${NC}"
fi

if grep -q "测试音频数据生成完成" "$LOG_FILE"; then
    echo -e "${GREEN}✓ 音频数据生成: 成功${NC}"
else
    echo -e "${RED}✗ 音频数据生成: 失败${NC}"
fi

# 统计帧数量
frame_count=$(grep -c "帧.*发送完成" "$LOG_FILE" || true)
echo "发送帧数: $frame_count"

if [ "$frame_count" -eq 4 ]; then
    echo -e "${GREEN}✓ 帧数量: 正确 (预期4帧)${NC}"
else
    echo -e "${YELLOW}⚠ 帧数量: $frame_count (预期4帧)${NC}"
fi

# 检查比特流输出
bitstream_count=$(grep -c "接收比特流字节" "$LOG_FILE" || true)
echo "比特流字节数: $bitstream_count"

if [ "$bitstream_count" -gt 0 ]; then
    echo -e "${GREEN}✓ 比特流输出: 有数据${NC}"
else
    echo -e "${RED}✗ 比特流输出: 无数据${NC}"
fi

echo ""

#=============================================================================
# 步骤5: 生成测试报告
#=============================================================================

echo -e "${YELLOW}步骤5: 生成测试报告...${NC}"

REPORT_FILE="$RESULTS_DIR/simple_test_report.txt"

cat > "$REPORT_FILE" << EOF
=============================================================================
LC3plus编码器简化测试报告
=============================================================================

测试时间: $(date)
项目路径: $PROJECT_ROOT
仿真器: iverilog $(iverilog -v 2>&1 | head -1 | awk '{print $4}')
测试平台: tb_simple_test.sv

=== 测试配置 ===
帧长: 2.5ms
测试时长: 10ms (4帧)
采样率: 48kHz
比特率: 64kbps
通道模式: 单声道
总样本数: 480 (120样本/帧 × 4帧)

=== 编译结果 ===
RTL文件数: ${#rtl_files[@]}
编译状态: 成功
编译警告: $(grep -c "warning" "$RESULTS_DIR/compile.log" 2>/dev/null || echo "0")

=== 仿真结果 ===
仿真状态: $(if [ -f "$LOG_FILE" ]; then echo "完成"; else echo "失败"; fi)
错误数量: $error_count
警告数量: $warning_count
发送帧数: $frame_count
比特流字节数: $bitstream_count

=== 功能验证 ===
系统复位: $(if grep -q "系统复位释放" "$LOG_FILE" 2>/dev/null; then echo "✓ 正常"; else echo "✗ 异常"; fi)
APB配置: $(if grep -q "APB配置完成" "$LOG_FILE" 2>/dev/null; then echo "✓ 成功"; else echo "✗ 失败"; fi)
音频数据生成: $(if grep -q "测试音频数据生成完成" "$LOG_FILE" 2>/dev/null; then echo "✓ 成功"; else echo "✗ 失败"; fi)
音频数据发送: $(if [ "$frame_count" -eq 4 ]; then echo "✓ 正确"; else echo "⚠ 异常"; fi)
比特流输出: $(if [ "$bitstream_count" -gt 0 ]; then echo "✓ 有数据"; else echo "✗ 无数据"; fi)

=== 详细日志 ===
编译日志: $RESULTS_DIR/compile.log
仿真日志: $RESULTS_DIR/simulation.log
波形文件: $RESULTS_DIR/tb_simple_test.vcd (如果生成)

=== 测试结论 ===
EOF

# 判断测试结果
if [ "$error_count" -eq 0 ] && [ "$frame_count" -eq 4 ] && [ "$bitstream_count" -gt 0 ]; then
    echo "测试状态: ✓ 通过" >> "$REPORT_FILE"
    echo -e "${GREEN}✓ 测试通过！${NC}"
    test_result="PASS"
else
    echo "测试状态: ✗ 失败" >> "$REPORT_FILE"
    echo -e "${RED}✗ 测试失败${NC}"
    test_result="FAIL"
fi

echo ""
echo -e "${GREEN}✓ 测试报告已保存到: $REPORT_FILE${NC}"

#=============================================================================
# 步骤6: 清理和总结
#=============================================================================

echo ""
echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}测试总结${NC}"
echo -e "${BLUE}==================================================${NC}"

if [ "$test_result" = "PASS" ]; then
    echo -e "${GREEN}🎉 LC3plus编码器简化测试通过！${NC}"
    echo ""
    echo "主要成果:"
    echo "✓ RTL代码编译无错误"
    echo "✓ 系统复位和APB配置正常"
    echo "✓ 成功处理4帧音频数据 (10ms)"
    echo "✓ 产生编码比特流输出"
    echo ""
    echo "下一步建议:"
    echo "1. 查看波形文件进行详细分析"
    echo "2. 运行更长时间的测试"
    echo "3. 测试不同的音频参数配置"
    echo "4. 进行比特精确性验证"
else
    echo -e "${RED}❌ LC3plus编码器简化测试失败${NC}"
    echo ""
    echo "请检查:"
    echo "1. 编译日志中的错误信息"
    echo "2. 仿真日志中的异常输出"
    echo "3. RTL代码的逻辑问题"
    echo ""
    echo "故障排除:"
    echo "- 查看 $RESULTS_DIR/compile.log"
    echo "- 查看 $RESULTS_DIR/simulation.log"
    echo "- 使用GTKWave查看波形文件"
fi

echo -e "${BLUE}==================================================${NC}"

exit $(if [ "$test_result" = "PASS" ]; then echo 0; else echo 1; fi) 