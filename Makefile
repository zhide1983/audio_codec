# Audio Codec Hardware Accelerator Project Makefile
# 
# Main Makefile for building and testing the audio codec hardware accelerator
#

# 项目配置
PROJECT_NAME = audio_codec
TOP_MODULE = audio_codec_top
RTL_DIR = rtl
SIM_DIR = sim
SW_DIR = sw
SCRIPTS_DIR = scripts

# 工具配置
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave
PYTHON = python3

# 编译选项
VERILOG_FLAGS = -g2012 -Wall
INCLUDE_DIRS = -I$(RTL_DIR)/common -I$(RTL_DIR)/lc3plus -I$(SIM_DIR)/testbench

# RTL文件
RTL_SOURCES = $(shell find $(RTL_DIR) -name "*.v" -o -name "*.sv")
TB_SOURCES = $(shell find $(SIM_DIR)/testbench -name "*.sv")

# 目标定义
.PHONY: all setup clean help reference test sim regression coverage

# 默认目标
all: help

# 显示帮助信息
help:
	@echo "Audio Codec Hardware Accelerator Build System"
	@echo "=============================================="
	@echo ""
	@echo "Available targets:"
	@echo "  setup      - Setup development environment"
	@echo "  reference  - Build reference model"
	@echo "  test       - Run basic tests"
	@echo "  sim        - Run RTL simulation"
	@echo "  regression - Run full regression test"
	@echo "  coverage   - Generate coverage report"
	@echo "  clean      - Clean build artifacts"
	@echo "  help       - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make setup           # First time setup"
	@echo "  make reference       # Build C reference model"
	@echo "  make sim             # Run basic simulation"
	@echo "  make regression      # Full test suite"

# 环境配置
setup:
	@echo "Setting up development environment..."
	@mkdir -p $(SIM_DIR)/results
	@mkdir -p $(SW_DIR)/reference/build
	@mkdir -p logs
	@echo "Checking tools..."
	@which $(IVERILOG) || (echo "Error: iverilog not found. Please install Icarus Verilog."; exit 1)
	@which $(PYTHON) || (echo "Error: python3 not found. Please install Python 3."; exit 1)
	@echo "Installing Python dependencies..."
	@$(PYTHON) -m pip install -r requirements.txt 2>/dev/null || echo "No requirements.txt found"
	@echo "Environment setup complete!"

# 构建参考模型
reference:
	@echo "Building LC3plus reference model..."
	@cd LC3plus_ETSI_src_v17171_20200723/src/fixed_point && make
	@cd LC3plus_ETSI_src_v17171_20200723/src/floating_point && make
	@echo "Building wrapper library..."
	@cd $(SW_DIR)/reference && $(MAKE)
	@echo "Reference model build complete!"

# 基础测试
test:
	@echo "Running basic functionality tests..."
	@$(PYTHON) $(SCRIPTS_DIR)/test/run_basic_tests.py
	@echo "Basic tests complete!"

# RTL仿真
sim: sim_encoder sim_decoder sim_system

sim_encoder:
	@echo "Running encoder simulation..."
	@cd $(SIM_DIR) && $(IVERILOG) $(VERILOG_FLAGS) $(INCLUDE_DIRS) \
		-o sim_encoder $(RTL_SOURCES) testbench/tb_encoder.sv
	@cd $(SIM_DIR) && $(VVP) sim_encoder
	@echo "Encoder simulation complete. Waveform: $(SIM_DIR)/encoder.vcd"

sim_decoder:
	@echo "Running decoder simulation..."
	@cd $(SIM_DIR) && $(IVERILOG) $(VERILOG_FLAGS) $(INCLUDE_DIRS) \
		-o sim_decoder $(RTL_SOURCES) testbench/tb_decoder.sv
	@cd $(SIM_DIR) && $(VVP) sim_decoder
	@echo "Decoder simulation complete. Waveform: $(SIM_DIR)/decoder.vcd"

sim_system:
	@echo "Running system-level simulation..."
	@cd $(SIM_DIR) && $(IVERILOG) $(VERILOG_FLAGS) $(INCLUDE_DIRS) \
		-o sim_system $(RTL_SOURCES) testbench/tb_system.sv
	@cd $(SIM_DIR) && $(VVP) sim_system
	@echo "System simulation complete. Waveform: $(SIM_DIR)/system.vcd"

# 回归测试
regression:
	@echo "Running full regression test suite..."
	@$(PYTHON) $(SCRIPTS_DIR)/test/run_regression.py
	@echo "Regression tests complete! Check results in $(SIM_DIR)/results/"

# 覆盖率分析
coverage:
	@echo "Generating coverage report..."
	@$(PYTHON) $(SCRIPTS_DIR)/test/coverage_analysis.py
	@echo "Coverage report generated in $(SIM_DIR)/results/coverage/"

# 代码检查
lint:
	@echo "Running RTL code checks..."
	@$(PYTHON) $(SCRIPTS_DIR)/utils/rtl_lint.py $(RTL_DIR)

# RTL设计规则检查
check-rules:
	@echo "Checking RTL design rules..."
	@$(PYTHON) $(SCRIPTS_DIR)/check_rtl_rules.py $(RTL_DIR)
	@echo "RTL design rules check completed"

# 综合检查 (需要综合工具)
synth:
	@echo "Running synthesis check..."
	@$(PYTHON) $(SCRIPTS_DIR)/build/synthesis_check.py

# 性能分析
performance:
	@echo "Running performance analysis..."
	@$(PYTHON) $(SCRIPTS_DIR)/test/performance_analysis.py

# 生成寄存器文件
generate_regs:
	@echo "Generating register files..."
	@$(PYTHON) $(SCRIPTS_DIR)/utils/gen_registers.py docs/specifications/register_map.json -o rtl/generated

# 生成文档
docs:
	@echo "Generating documentation..."
	@$(PYTHON) $(SCRIPTS_DIR)/utils/gen_docs.py

# 清理
clean:
	@echo "Cleaning build artifacts..."
	@rm -f $(SIM_DIR)/*.vcd $(SIM_DIR)/sim_* $(SIM_DIR)/*.out
	@rm -rf $(SIM_DIR)/results/*
	@rm -rf $(SW_DIR)/reference/build/*
	@cd LC3plus_ETSI_src_v17171_20200723/src/fixed_point && make clean 2>/dev/null || true
	@cd LC3plus_ETSI_src_v17171_20200723/src/floating_point && make clean 2>/dev/null || true
	@find . -name "*.pyc" -delete
	@find . -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo "Clean complete!"

# 深度清理
distclean: clean
	@echo "Performing deep clean..."
	@rm -rf logs/*
	@echo "Deep clean complete!"

# 开发者工具
dev-tools:
	@echo "Installing development tools..."
	@$(PYTHON) -m pip install verilator-python
	@echo "Development tools installed!"

# 快速验证 (用于CI/CD)
quick-verify: reference
	@echo "Running quick verification..."
	@$(PYTHON) $(SCRIPTS_DIR)/test/quick_verify.py
	@echo "Quick verification complete!" 