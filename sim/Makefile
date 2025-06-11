#=============================================================================
# LC3plus编码器验证Makefile (LC3plus Encoder Verification Makefile)
# 
# 功能：自动化LC3plus编码器的完整验证流程
# 作者：Audio Codec Design Team
# 版本：v1.0
# 日期：2024-06-11
#=============================================================================

# 项目路径配置
PROJECT_ROOT := $(shell pwd)/..
SIM_DIR := $(PROJECT_ROOT)/sim
RTL_DIR := $(PROJECT_ROOT)/rtl
SCRIPTS_DIR := $(SIM_DIR)/scripts
RESULTS_DIR := $(SIM_DIR)/results
TEST_VECTORS_DIR := $(SIM_DIR)/test_vectors
REFERENCE_DIR := $(SIM_DIR)/reference
TESTBENCH_DIR := $(SIM_DIR)/testbench

# LC3plus参考代码路径
LC3PLUS_REF_DIR := $(PROJECT_ROOT)/LC3plus_ETSI_src_v17171_20200723

# 仿真器配置
SIMULATOR := iverilog
SIMULATOR_FLAGS := -g2012 -Wall
VVP_FLAGS := 
WAVE_FORMAT := vcd

# 顶层模块
TOP_MODULE := tb_lc3plus_encoder_top

# RTL文件列表
RTL_FILES := \
	$(RTL_DIR)/processing/mdct_transform.v \
	$(RTL_DIR)/processing/spectral_analysis.v \
	$(RTL_DIR)/processing/entropy_coding.v \
	$(RTL_DIR)/processing/bitstream_packing.v \
	$(RTL_DIR)/lc3plus_encoder_top.v

# 测试平台文件
TB_FILES := \
	$(TESTBENCH_DIR)/$(TOP_MODULE).sv

# 输出文件
SIM_EXECUTABLE := $(RESULTS_DIR)/lc3plus_encoder_sim
VCD_FILE := $(RESULTS_DIR)/simulation.vcd
LOG_FILE := $(RESULTS_DIR)/simulation.log
REPORT_FILE := $(RESULTS_DIR)/verification_report.txt

# Python解释器
PYTHON := python3

#=============================================================================
# 默认目标
#=============================================================================

.PHONY: all
all: verify

#=============================================================================
# 帮助信息
#=============================================================================

.PHONY: help
help:
	@echo "LC3plus编码器验证Makefile"
	@echo ""
	@echo "主要目标:"
	@echo "  verify           - 运行完整验证流程"
	@echo "  test-vectors     - 生成测试向量"
	@echo "  compile          - 编译RTL代码"
	@echo "  simulate         - 运行仿真"
	@echo "  analyze          - 分析结果"
	@echo "  report           - 生成报告"
	@echo ""
	@echo "维护目标:"
	@echo "  clean            - 清理生成文件"
	@echo "  clean-all        - 清理所有文件(包括测试向量)"
	@echo "  setup            - 设置验证环境"
	@echo "  check-env        - 检查环境依赖"
	@echo ""
	@echo "调试目标:"
	@echo "  compile-only     - 仅编译不运行"
	@echo "  quick-sim        - 快速仿真(跳过测试向量生成)"
	@echo "  view-waves       - 查看波形文件"
	@echo ""
	@echo "配置变量:"
	@echo "  SIMULATOR=$(SIMULATOR)"
	@echo "  TOP_MODULE=$(TOP_MODULE)"
	@echo "  WAVE_FORMAT=$(WAVE_FORMAT)"

#=============================================================================
# 环境检查
#=============================================================================

.PHONY: check-env
check-env:
	@echo "检查验证环境..."
	@which $(SIMULATOR) > /dev/null || (echo "错误: 找不到仿真器 $(SIMULATOR)" && exit 1)
	@which $(PYTHON) > /dev/null || (echo "错误: 找不到Python解释器" && exit 1)
	@test -d $(LC3PLUS_REF_DIR) || (echo "错误: 找不到LC3plus参考代码目录" && exit 1)
	@echo "环境检查通过"

#=============================================================================
# 设置验证环境
#=============================================================================

.PHONY: setup
setup: check-env
	@echo "设置验证环境..."
	@mkdir -p $(RESULTS_DIR)
	@mkdir -p $(TEST_VECTORS_DIR)
	@mkdir -p $(REFERENCE_DIR)
	@echo "验证环境设置完成"

#=============================================================================
# 测试向量生成
#=============================================================================

$(TEST_VECTORS_DIR)/.vectors_generated: setup
	@echo "生成测试向量..."
	@cd $(SCRIPTS_DIR) && $(PYTHON) generate_test_vectors.py
	@touch $@

.PHONY: test-vectors
test-vectors: $(TEST_VECTORS_DIR)/.vectors_generated

#=============================================================================
# RTL编译
#=============================================================================

$(SIM_EXECUTABLE): $(RTL_FILES) $(TB_FILES) setup
	@echo "编译RTL代码..."
	@echo "  仿真器: $(SIMULATOR)"
	@echo "  顶层模块: $(TOP_MODULE)"
	@echo "  RTL文件: $(words $(RTL_FILES)) 个"
	$(SIMULATOR) $(SIMULATOR_FLAGS) -o $@ $(TB_FILES) $(RTL_FILES)
	@echo "RTL编译完成"

.PHONY: compile
compile: $(SIM_EXECUTABLE)

.PHONY: compile-only
compile-only: compile

#=============================================================================
# 仿真运行
#=============================================================================

$(LOG_FILE): $(SIM_EXECUTABLE) test-vectors
	@echo "运行仿真..."
	@echo "  可执行文件: $(SIM_EXECUTABLE)"
	@echo "  日志文件: $(LOG_FILE)"
ifeq ($(SIMULATOR),iverilog)
	@cd $(RESULTS_DIR) && vvp $(VVP_FLAGS) $(SIM_EXECUTABLE) | tee $(LOG_FILE)
else
	@echo "暂不支持仿真器: $(SIMULATOR)"
	@exit 1
endif
	@echo "仿真完成"

.PHONY: simulate
simulate: $(LOG_FILE)

.PHONY: quick-sim
quick-sim: $(SIM_EXECUTABLE)
	@echo "快速仿真(跳过测试向量生成)..."
	@cd $(RESULTS_DIR) && vvp $(VVP_FLAGS) $(SIM_EXECUTABLE) | tee $(LOG_FILE)

#=============================================================================
# 结果分析
#=============================================================================

.PHONY: analyze
analyze: $(LOG_FILE)
	@echo "分析仿真结果..."
	@cd $(SCRIPTS_DIR) && $(PYTHON) -c "\
import sys; \
sys.path.append('.'); \
from run_verification import LC3plusVerificationRunner; \
runner = LC3plusVerificationRunner(); \
results = runner.analyze_simulation_log('$(LOG_FILE)'); \
print(f'通过率: {results[\"pass_rate\"]:.1f}%'); \
print(f'总帧数: {results[\"total_frames\"]}'); \
print(f'通过帧数: {results[\"passed_frames\"]}'); \
print(f'失败帧数: {results[\"failed_frames\"]}'); \
"

#=============================================================================
# 报告生成
#=============================================================================

$(REPORT_FILE): $(LOG_FILE)
	@echo "生成验证报告..."
	@cd $(SCRIPTS_DIR) && $(PYTHON) run_verification.py --steps generate_report
	@echo "验证报告生成完成: $(REPORT_FILE)"

.PHONY: report
report: $(REPORT_FILE)

#=============================================================================
# 完整验证流程
#=============================================================================

.PHONY: verify
verify: setup test-vectors compile simulate analyze report
	@echo ""
	@echo "=== LC3plus编码器验证完成 ==="
	@echo ""
	@if grep -q "验证通过" $(REPORT_FILE); then \
		echo "🎉 验证结果: 通过"; \
		echo "详细报告请查看: $(REPORT_FILE)"; \
	else \
		echo "❌ 验证结果: 失败"; \
		echo "请检查日志: $(LOG_FILE)"; \
		echo "详细报告: $(REPORT_FILE)"; \
		exit 1; \
	fi

#=============================================================================
# 完整自动化验证(使用Python脚本)
#=============================================================================

.PHONY: auto-verify
auto-verify: setup
	@echo "运行自动化验证流程..."
	@cd $(SCRIPTS_DIR) && $(PYTHON) run_verification.py
	@echo "自动化验证完成"

#=============================================================================
# 波形查看
#=============================================================================

.PHONY: view-waves
view-waves:
	@if [ -f $(VCD_FILE) ]; then \
		echo "查看波形文件: $(VCD_FILE)"; \
		if which gtkwave > /dev/null 2>&1; then \
			gtkwave $(VCD_FILE) &; \
		else \
			echo "请安装GTKWave查看波形文件"; \
		fi; \
	else \
		echo "波形文件不存在: $(VCD_FILE)"; \
		echo "请先运行仿真生成波形"; \
	fi

#=============================================================================
# 清理目标
#=============================================================================

.PHONY: clean
clean:
	@echo "清理生成文件..."
	@rm -f $(SIM_EXECUTABLE)
	@rm -f $(VCD_FILE)
	@rm -f $(LOG_FILE)
	@rm -f $(REPORT_FILE)
	@rm -f $(RESULTS_DIR)/*.json
	@rm -f $(RESULTS_DIR)/simulation
	@echo "清理完成"

.PHONY: clean-vectors
clean-vectors:
	@echo "清理测试向量..."
	@rm -rf $(TEST_VECTORS_DIR)/*
	@rm -rf $(REFERENCE_DIR)/*
	@echo "测试向量清理完成"

.PHONY: clean-all
clean-all: clean clean-vectors
	@echo "清理所有生成文件..."
	@rm -rf $(RESULTS_DIR)
	@echo "全部清理完成"

#=============================================================================
# 调试和开发目标
#=============================================================================

.PHONY: debug-compile
debug-compile:
	@echo "调试模式编译..."
	$(SIMULATOR) $(SIMULATOR_FLAGS) -DDEBUG -o $(SIM_EXECUTABLE) $(TB_FILES) $(RTL_FILES)

.PHONY: lint
lint:
	@echo "RTL代码检查..."
	@for file in $(RTL_FILES); do \
		echo "检查: $$file"; \
		verilator --lint-only -Wall $$file || true; \
	done

.PHONY: info
info:
	@echo "项目信息:"
	@echo "  项目根目录: $(PROJECT_ROOT)"
	@echo "  RTL目录: $(RTL_DIR)"
	@echo "  仿真目录: $(SIM_DIR)"
	@echo "  结果目录: $(RESULTS_DIR)"
	@echo "  RTL文件数: $(words $(RTL_FILES))"
	@echo "  顶层模块: $(TOP_MODULE)"
	@echo "  仿真器: $(SIMULATOR)"

#=============================================================================
# 批量测试目标
#=============================================================================

.PHONY: test-config-%
test-config-%:
	@echo "测试配置: $*"
	@cd $(SCRIPTS_DIR) && $(PYTHON) run_verification.py --config $*

.PHONY: regression
regression:
	@echo "运行回归测试..."
	@for config in 16k_mono 24k_mono 48k_mono 48k_stereo; do \
		$(MAKE) test-config-$$config || exit 1; \
	done
	@echo "回归测试完成"

#=============================================================================
# 持续集成目标
#=============================================================================

.PHONY: ci-verify
ci-verify: check-env clean-all verify
	@echo "CI验证完成"

.PHONY: ci-quick
ci-quick: check-env clean compile quick-sim
	@echo "CI快速验证完成"

#=============================================================================
# 文档生成
#=============================================================================

.PHONY: docs
docs:
	@echo "生成文档..."
	@echo "暂未实现文档生成功能"

#=============================================================================
# 文件监听
#=============================================================================

# 检查文件变化并重新编译的目标
.PHONY: watch
watch:
	@echo "监听文件变化..."
	@echo "使用Ctrl+C停止监听"
	@while true; do \
		inotifywait -e modify $(RTL_FILES) $(TB_FILES) 2>/dev/null && \
		echo "检测到文件变化，重新编译..." && \
		$(MAKE) compile; \
	done

#=============================================================================
# 特殊目标声明
#=============================================================================

# 避免与文件名冲突
.PHONY: all help verify test-vectors compile simulate analyze report clean

# 保持中间文件
.PRECIOUS: $(SIM_EXECUTABLE) $(LOG_FILE) $(VCD_FILE)

# 默认shell
SHELL := /bin/bash 