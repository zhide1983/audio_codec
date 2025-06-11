#!/bin/bash

# =============================================================================
# LC3plus编码器增强测试脚本 v2.0
# 提供实时进度监控和详细日志
# =============================================================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 配置参数
PROJECT_NAME="LC3plus编码器"
VERSION="v2.0"
LOG_DIR="sim/logs"
RESULT_DIR="sim/results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/test_${TIMESTAMP}.log"
MONITOR_LOG="${LOG_DIR}/monitor_${TIMESTAMP}.log"

# 函数：打印带颜色的消息
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
}

print_header() {
    echo -e "${WHITE}=================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${WHITE}=================================================${NC}"
    echo "=================================================" >> "$LOG_FILE"
    echo "$1" >> "$LOG_FILE"
    echo "=================================================" >> "$LOG_FILE"
}

# 函数：创建目录
create_dirs() {
    print_msg "$BLUE" "📁 创建测试目录..."
    mkdir -p "$LOG_DIR"
    mkdir -p "$RESULT_DIR"
    mkdir -p "sim/waveforms"
    print_msg "$GREEN" "✅ 目录创建完成"
}

# 函数：检查环境
check_environment() {
    print_msg "$BLUE" "🔍 检查仿真环境..."
    
    if ! command -v iverilog &> /dev/null; then
        print_msg "$RED" "❌ 错误：找不到 iverilog"
        exit 1
    fi
    
    if ! command -v vvp &> /dev/null; then
        print_msg "$RED" "❌ 错误：找不到 vvp"
        exit 1
    fi
    
    print_msg "$GREEN" "✅ iverilog 版本: $(iverilog -V 2>&1 | head -1)"
    print_msg "$GREEN" "✅ 仿真环境检查通过"
}

# 函数：编译RTL
compile_rtl() {
    print_header "🔨 编译RTL代码"
    
    local start_time=$(date +%s)
    
    print_msg "$BLUE" "📋 收集RTL文件..."
    
    # RTL文件列表
    local rtl_files=(
        "rtl/common/lc3plus_defines.v"
        "rtl/processing/mdct_transform.v"
        "rtl/processing/spectral_analysis.v"
        "rtl/control/quantization_control.v"
        "rtl/entropy/entropy_encoder.v"
        "rtl/packing/bitstream_packer.v"
        "rtl/storage/coefficient_storage.v"
        "rtl/control/frame_control.v"
        "rtl/interface/audio_interface.v"
        "rtl/interface/bitstream_interface.v"
        "rtl/interface/system_interface.v"
        "rtl/lc3plus_encoder_top_corrected.v"
        "sim/testbench/tb_enhanced.sv"
    )
    
    # 检查文件存在性
    local missing_files=0
    for file in "${rtl_files[@]}"; do
        if [[ -f "$file" ]]; then
            print_msg "$CYAN" "  ✓ $file"
        else
            print_msg "$RED" "  ❌ $file (文件不存在)"
            ((missing_files++))
        fi
    done
    
    if [[ $missing_files -gt 0 ]]; then
        print_msg "$RED" "❌ 发现 $missing_files 个缺失文件，无法编译"
        exit 1
    fi
    
    print_msg "$BLUE" "🔧 开始编译..."
    
    # 编译命令
    local compile_cmd="iverilog \
        -g2012 \
        -Wall \
        -Winfloop \
        -o ${RESULT_DIR}/lc3plus_enhanced \
        ${rtl_files[*]}"
    
    print_msg "$CYAN" "编译命令: $compile_cmd"
    
    # 执行编译并捕获输出
    if $compile_cmd 2>&1 | tee -a "$LOG_FILE"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        print_msg "$GREEN" "✅ 编译成功！用时: ${duration}秒"
        print_msg "$GREEN" "📦 可执行文件: ${RESULT_DIR}/lc3plus_enhanced"
        
        # 检查文件大小
        local file_size=$(stat -c%s "${RESULT_DIR}/lc3plus_enhanced" 2>/dev/null || echo "未知")
        print_msg "$CYAN" "📊 文件大小: ${file_size} 字节"
        
        return 0
    else
        print_msg "$RED" "❌ 编译失败"
        exit 1
    fi
}

# 函数：实时监控仿真
monitor_simulation() {
    local sim_pid=$1
    local log_file=$2
    
    print_msg "$BLUE" "📊 启动仿真监控..."
    
    {
        local start_time=$(date +%s)
        local last_progress=""
        local frame_count=0
        local sample_count=0
        
        while kill -0 "$sim_pid" 2>/dev/null; do
            sleep 2
            
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            
            # 从日志中提取进度信息
            if [[ -f "$log_file" ]]; then
                local latest_progress=$(tail -20 "$log_file" | grep -E "(总进度|帧.*进度)" | tail -1 || echo "")
                local latest_frame=$(tail -20 "$log_file" | grep -o "第[0-9]*帧" | tail -1 || echo "")
                local latest_samples=$(tail -20 "$log_file" | grep -o "[0-9]*样本" | tail -1 || echo "")
                
                if [[ "$latest_progress" != "$last_progress" && -n "$latest_progress" ]]; then
                    print_msg "$PURPLE" "📈 [${elapsed}s] $latest_progress"
                    last_progress="$latest_progress"
                fi
                
                # 检查错误
                local errors=$(tail -10 "$log_file" | grep -E "(ERROR|❌|error)" || echo "")
                if [[ -n "$errors" ]]; then
                    print_msg "$RED" "⚠️  检测到错误: $errors"
                fi
                
                # 检查完成状态
                local completion=$(tail -5 "$log_file" | grep -E "(验证测试通过|验证测试失败)" || echo "")
                if [[ -n "$completion" ]]; then
                    print_msg "$GREEN" "🎯 $completion"
                    break
                fi
            fi
            
            # 显示运行时间
            if [[ $((elapsed % 10)) -eq 0 ]]; then
                print_msg "$CYAN" "⏱️  仿真运行时间: ${elapsed}秒"
            fi
        done
        
        print_msg "$BLUE" "📊 仿真监控结束"
    } > "$MONITOR_LOG" 2>&1 &
    
    local monitor_pid=$!
    echo $monitor_pid
}

# 函数：运行仿真
run_simulation() {
    print_header "🚀 运行增强仿真测试"
    
    local sim_start=$(date +%s)
    
    # 准备仿真日志
    local sim_log="${LOG_DIR}/simulation_${TIMESTAMP}.log"
    
    print_msg "$BLUE" "📝 仿真日志: $sim_log"
    print_msg "$BLUE" "🎮 启动仿真..."
    
    # 启动仿真（后台运行）
    local sim_cmd="${RESULT_DIR}/lc3plus_enhanced +dump"
    
    print_msg "$CYAN" "仿真命令: vvp $sim_cmd"
    
    # 启动仿真进程
    vvp $sim_cmd > "$sim_log" 2>&1 &
    local sim_pid=$!
    
    print_msg "$GREEN" "✅ 仿真进程启动 (PID: $sim_pid)"
    
    # 启动监控
    local monitor_pid=$(monitor_simulation $sim_pid "$sim_log")
    
    # 实时显示日志
    print_msg "$BLUE" "📺 实时显示仿真输出..."
    echo ""
    
    # 跟踪日志文件
    tail -f "$sim_log" &
    local tail_pid=$!
    
    # 等待仿真完成
    wait $sim_pid
    local sim_exit_code=$?
    
    # 停止日志跟踪
    kill $tail_pid 2>/dev/null || true
    kill $monitor_pid 2>/dev/null || true
    
    local sim_end=$(date +%s)
    local sim_duration=$((sim_end - sim_start))
    
    echo ""
    
    if [[ $sim_exit_code -eq 0 ]]; then
        print_msg "$GREEN" "✅ 仿真成功完成！用时: ${sim_duration}秒"
    else
        print_msg "$RED" "❌ 仿真异常退出 (退出码: $sim_exit_code)"
        return 1
    fi
    
    return 0
}

# 函数：分析结果
analyze_results() {
    print_header "📊 分析测试结果"
    
    local sim_log="${LOG_DIR}/simulation_${TIMESTAMP}.log"
    
    if [[ ! -f "$sim_log" ]]; then
        print_msg "$RED" "❌ 找不到仿真日志文件"
        return 1
    fi
    
    print_msg "$BLUE" "🔍 分析仿真日志..."
    
    # 提取关键统计信息
    local total_samples=$(grep -o "总样本数: [0-9]*" "$sim_log" | tail -1 | grep -o "[0-9]*" || echo "0")
    local total_bytes=$(grep -o "总字节数: [0-9]*" "$sim_log" | tail -1 | grep -o "[0-9]*" || echo "0")
    local frames_processed=$(grep -o "已完成帧数: [0-9]*/[0-9]*" "$sim_log" | tail -1 || echo "0/0")
    local compression_ratio=$(grep -o "压缩比: [0-9.]*:1" "$sim_log" | tail -1 | grep -o "[0-9.]*" || echo "0")
    local test_result=$(grep -E "(验证测试通过|验证测试失败)" "$sim_log" | tail -1 || echo "未知")
    
    # 错误统计
    local error_count=$(grep -c -E "(ERROR|❌|error)" "$sim_log" || echo "0")
    local warning_count=$(grep -c -E "(WARNING|⚠️|warning)" "$sim_log" || echo "0")
    
    # 显示结果摘要
    print_msg "$CYAN" "=== 测试结果摘要 ==="
    print_msg "$WHITE" "总样本数: $total_samples"
    print_msg "$WHITE" "总字节数: $total_bytes"
    print_msg "$WHITE" "处理帧数: $frames_processed"
    print_msg "$WHITE" "压缩比: ${compression_ratio}:1"
    print_msg "$WHITE" "错误数: $error_count"
    print_msg "$WHITE" "警告数: $warning_count"
    
    # 测试结果
    if [[ "$test_result" =~ "通过" ]]; then
        print_msg "$GREEN" "🎉 $test_result"
    elif [[ "$test_result" =~ "失败" ]]; then
        print_msg "$RED" "❌ $test_result"
    else
        print_msg "$YELLOW" "❓ 测试结果: $test_result"
    fi
    
    # 生成结果报告
    local report_file="${RESULT_DIR}/test_report_${TIMESTAMP}.txt"
    {
        echo "LC3plus编码器验证测试报告"
        echo "========================="
        echo "测试时间: $(date)"
        echo "版本: $VERSION"
        echo ""
        echo "测试结果摘要:"
        echo "  总样本数: $total_samples"
        echo "  总字节数: $total_bytes"
        echo "  处理帧数: $frames_processed"
        echo "  压缩比: ${compression_ratio}:1"
        echo "  错误数: $error_count"
        echo "  警告数: $warning_count"
        echo "  测试结果: $test_result"
        echo ""
        echo "详细日志: $sim_log"
        echo "监控日志: $MONITOR_LOG"
    } > "$report_file"
    
    print_msg "$CYAN" "📋 测试报告已生成: $report_file"
}

# 函数：清理临时文件
cleanup() {
    print_msg "$BLUE" "🧹 清理临时文件..."
    
    # 清理编译产物
    rm -f *.vcd 2>/dev/null || true
    rm -f *.out 2>/dev/null || true
    
    print_msg "$GREEN" "✅ 清理完成"
}

# 主函数
main() {
    local total_start=$(date +%s)
    
    print_header "$PROJECT_NAME 增强验证测试 $VERSION"
    print_msg "$CYAN" "🕐 测试开始时间: $(date)"
    print_msg "$CYAN" "📝 日志文件: $LOG_FILE"
    
    # 执行测试步骤
    create_dirs
    check_environment
    compile_rtl
    
    if run_simulation; then
        analyze_results
    else
        print_msg "$RED" "❌ 仿真失败，跳过结果分析"
    fi
    
    cleanup
    
    local total_end=$(date +%s)
    local total_duration=$((total_end - total_start))
    
    print_header "测试完成"
    print_msg "$GREEN" "🎯 总用时: ${total_duration}秒"
    print_msg "$CYAN" "📋 完整日志: $LOG_FILE"
    
    if [[ -f "${RESULT_DIR}/test_report_${TIMESTAMP}.txt" ]]; then
        print_msg "$CYAN" "📊 测试报告: ${RESULT_DIR}/test_report_${TIMESTAMP}.txt"
    fi
}

# 信号处理
trap cleanup EXIT
trap 'print_msg "$RED" "❌ 测试被中断"; cleanup; exit 1' INT TERM

# 执行主函数
main "$@" 