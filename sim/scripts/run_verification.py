#!/usr/bin/env python3
"""
LC3plus编码器完整验证脚本 (Complete Verification Script)

功能：自动化执行完整的LC3plus编码器验证流程
作者：Audio Codec Design Team
版本：v1.0
日期：2024-06-11
"""

import os
import sys
import subprocess
import time
import json
from pathlib import Path
import argparse

class LC3plusVerificationRunner:
    def __init__(self):
        """初始化验证运行器"""
        self.project_root = Path(__file__).parent.parent.parent
        self.sim_path = self.project_root / "sim"
        self.rtl_path = self.project_root / "rtl"
        self.scripts_path = self.sim_path / "scripts"
        self.results_path = self.sim_path / "results"
        
        # 创建结果目录
        self.results_path.mkdir(parents=True, exist_ok=True)
        
        # 仿真配置
        self.sim_config = {
            'simulator': 'iverilog',  # 或 'modelsim', 'questasim'
            'top_module': 'tb_lc3plus_encoder_top',
            'timeout': 3600,  # 1小时超时
            'wave_dump': True
        }
        
        # 验证步骤
        self.verification_steps = [
            'generate_test_vectors',
            'compile_rtl',
            'run_simulation',
            'analyze_results',
            'generate_report'
        ]
        
        self.step_results = {}
    
    def log(self, message, level='INFO'):
        """日志输出"""
        timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
        print(f"[{timestamp}] [{level}] {message}")
    
    def run_command(self, cmd, cwd=None, timeout=None):
        """运行系统命令"""
        if cwd is None:
            cwd = self.project_root
        
        self.log(f"执行命令: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
        
        try:
            result = subprocess.run(
                cmd,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=timeout or 300
            )
            
            if result.returncode == 0:
                self.log("命令执行成功")
                return True, result.stdout, result.stderr
            else:
                self.log(f"命令执行失败: {result.stderr}", "ERROR")
                return False, result.stdout, result.stderr
                
        except subprocess.TimeoutExpired:
            self.log("命令执行超时", "ERROR")
            return False, "", "Timeout"
        except Exception as e:
            self.log(f"命令执行异常: {e}", "ERROR")
            return False, "", str(e)
    
    def step_generate_test_vectors(self):
        """步骤1: 生成测试向量"""
        self.log("=== 步骤1: 生成测试向量 ===")
        
        # 运行测试向量生成脚本
        generator_script = self.scripts_path / "generate_test_vectors.py"
        
        if not generator_script.exists():
            self.log("测试向量生成脚本不存在", "ERROR")
            return False
        
        success, stdout, stderr = self.run_command([
            sys.executable, str(generator_script)
        ], timeout=600)
        
        if success:
            self.log("测试向量生成成功")
            self.step_results['generate_test_vectors'] = {
                'status': 'PASS',
                'details': 'Test vectors generated successfully'
            }
            return True
        else:
            self.log("测试向量生成失败", "ERROR")
            self.step_results['generate_test_vectors'] = {
                'status': 'FAIL',
                'details': stderr
            }
            return False
    
    def step_compile_rtl(self):
        """步骤2: 编译RTL代码"""
        self.log("=== 步骤2: 编译RTL代码 ===")
        
        # RTL文件列表
        rtl_files = [
            self.rtl_path / "processing" / "mdct_transform.v",
            self.rtl_path / "processing" / "spectral_analysis.v",
            self.rtl_path / "processing" / "quantization_control.v",
            self.rtl_path / "processing" / "entropy_coding.v",
            self.rtl_path / "processing" / "bitstream_packing.v",
            self.rtl_path / "lc3plus_encoder_top.v"
        ]
        
        # 检查文件存在性
        missing_files = []
        for file in rtl_files:
            if not file.exists():
                missing_files.append(str(file))
        
        if missing_files:
            self.log(f"缺少RTL文件: {missing_files}", "ERROR")
            self.step_results['compile_rtl'] = {
                'status': 'FAIL',
                'details': f'Missing RTL files: {missing_files}'
            }
            return False
        
        # testbench文件
        tb_file = self.sim_path / "testbench" / "tb_lc3plus_encoder_top.sv"
        if not tb_file.exists():
            self.log("测试平台文件不存在", "ERROR")
            self.step_results['compile_rtl'] = {
                'status': 'FAIL',
                'details': 'Testbench file missing'
            }
            return False
        
        # 编译命令
        if self.sim_config['simulator'] == 'iverilog':
            compile_cmd = [
                'iverilog',
                '-g2012',  # SystemVerilog 2012
                '-o', str(self.results_path / 'simulation'),
                str(tb_file)
            ] + [str(f) for f in rtl_files]
            
        elif self.sim_config['simulator'] == 'modelsim':
            # ModelSim编译流程
            self.log("ModelSim编译流程暂未实现", "ERROR")
            return False
        else:
            self.log(f"不支持的仿真器: {self.sim_config['simulator']}", "ERROR")
            return False
        
        success, stdout, stderr = self.run_command(compile_cmd)
        
        if success:
            self.log("RTL代码编译成功")
            self.step_results['compile_rtl'] = {
                'status': 'PASS',
                'details': 'RTL compilation successful'
            }
            return True
        else:
            self.log("RTL代码编译失败", "ERROR")
            self.step_results['compile_rtl'] = {
                'status': 'FAIL',
                'details': stderr
            }
            return False
    
    def step_run_simulation(self):
        """步骤3: 运行仿真"""
        self.log("=== 步骤3: 运行仿真 ===")
        
        sim_executable = self.results_path / 'simulation'
        if not sim_executable.exists():
            self.log("仿真可执行文件不存在", "ERROR")
            self.step_results['run_simulation'] = {
                'status': 'FAIL',
                'details': 'Simulation executable not found'
            }
            return False
        
        # 设置仿真环境变量
        sim_env = os.environ.copy()
        if self.sim_config['wave_dump']:
            sim_env['VCD_FILE'] = str(self.results_path / 'simulation.vcd')
        
        # 运行仿真
        sim_cmd = [str(sim_executable)]
        
        self.log("开始运行仿真...")
        start_time = time.time()
        
        success, stdout, stderr = self.run_command(
            sim_cmd, 
            cwd=self.results_path,
            timeout=self.sim_config['timeout']
        )
        
        end_time = time.time()
        sim_time = end_time - start_time
        
        # 保存仿真输出
        with open(self.results_path / 'simulation.log', 'w') as f:
            f.write("=== STDOUT ===\n")
            f.write(stdout)
            f.write("\n=== STDERR ===\n")
            f.write(stderr)
        
        if success:
            self.log(f"仿真完成，耗时: {sim_time:.2f} 秒")
            self.step_results['run_simulation'] = {
                'status': 'PASS',
                'details': f'Simulation completed in {sim_time:.2f} seconds',
                'runtime': sim_time
            }
            return True
        else:
            self.log("仿真失败", "ERROR")
            self.step_results['run_simulation'] = {
                'status': 'FAIL',
                'details': stderr,
                'runtime': sim_time
            }
            return False
    
    def step_analyze_results(self):
        """步骤4: 分析结果"""
        self.log("=== 步骤4: 分析仿真结果 ===")
        
        log_file = self.results_path / 'simulation.log'
        if not log_file.exists():
            self.log("仿真日志文件不存在", "ERROR")
            self.step_results['analyze_results'] = {
                'status': 'FAIL',
                'details': 'Simulation log file not found'
            }
            return False
        
        # 分析仿真日志
        analysis_results = self.analyze_simulation_log(log_file)
        
        # 判断测试是否通过
        if analysis_results['pass_rate'] >= 95.0:
            self.log(f"验证通过! 通过率: {analysis_results['pass_rate']:.1f}%")
            status = 'PASS'
        else:
            self.log(f"验证失败! 通过率: {analysis_results['pass_rate']:.1f}%", "ERROR")
            status = 'FAIL'
        
        self.step_results['analyze_results'] = {
            'status': status,
            'details': analysis_results
        }
        
        return status == 'PASS'
    
    def analyze_simulation_log(self, log_file):
        """分析仿真日志文件"""
        results = {
            'total_frames': 0,
            'passed_frames': 0,
            'failed_frames': 0,
            'pass_rate': 0.0,
            'avg_snr': 0.0,
            'min_snr': 999.0,
            'errors': [],
            'warnings': []
        }
        
        try:
            with open(log_file, 'r') as f:
                content = f.read()
            
            # 查找关键信息
            lines = content.split('\n')
            for line in lines:
                if 'PASS' in line and '帧' in line:
                    results['passed_frames'] += 1
                elif 'FAIL' in line and '帧' in line:
                    results['failed_frames'] += 1
                elif 'ERROR' in line:
                    results['errors'].append(line.strip())
                elif 'WARNING' in line or 'Warning' in line:
                    results['warnings'].append(line.strip())
                elif '总测试帧数:' in line:
                    try:
                        results['total_frames'] = int(line.split(':')[1].strip())
                    except:
                        pass
                elif '通过率:' in line:
                    try:
                        rate_str = line.split(':')[1].strip().replace('%', '')
                        results['pass_rate'] = float(rate_str)
                    except:
                        pass
                elif '平均SNR:' in line:
                    try:
                        snr_str = line.split(':')[1].strip().replace('dB', '')
                        results['avg_snr'] = float(snr_str)
                    except:
                        pass
            
            # 计算通过率(如果没有在日志中找到)
            if results['total_frames'] == 0:
                results['total_frames'] = results['passed_frames'] + results['failed_frames']
            
            if results['total_frames'] > 0:
                results['pass_rate'] = (results['passed_frames'] / results['total_frames']) * 100
            
        except Exception as e:
            self.log(f"分析日志文件失败: {e}", "ERROR")
            results['errors'].append(f"Log analysis failed: {e}")
        
        return results
    
    def step_generate_report(self):
        """步骤5: 生成验证报告"""
        self.log("=== 步骤5: 生成验证报告 ===")
        
        report_data = {
            'verification_info': {
                'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
                'simulator': self.sim_config['simulator'],
                'top_module': self.sim_config['top_module']
            },
            'step_results': self.step_results,
            'overall_status': self.get_overall_status()
        }
        
        # 生成JSON报告
        json_report = self.results_path / 'verification_report.json'
        with open(json_report, 'w', encoding='utf-8') as f:
            json.dump(report_data, f, indent=2, ensure_ascii=False)
        
        # 生成文本报告
        text_report = self.results_path / 'verification_report.txt'
        self.generate_text_report(text_report, report_data)
        
        self.log(f"验证报告生成: {json_report}")
        self.log(f"验证报告生成: {text_report}")
        
        self.step_results['generate_report'] = {
            'status': 'PASS',
            'details': 'Reports generated successfully'
        }
        
        return True
    
    def generate_text_report(self, file_path, report_data):
        """生成文本格式验证报告"""
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write("=" * 60 + "\n")
            f.write("LC3plus编码器验证报告\n")
            f.write("=" * 60 + "\n\n")
            
            # 基本信息
            info = report_data['verification_info']
            f.write(f"验证时间: {info['timestamp']}\n")
            f.write(f"仿真器: {info['simulator']}\n")
            f.write(f"顶层模块: {info['top_module']}\n\n")
            
            # 各步骤结果
            f.write("验证步骤结果:\n")
            f.write("-" * 40 + "\n")
            for step, result in report_data['step_results'].items():
                status_icon = "✅" if result['status'] == 'PASS' else "❌"
                f.write(f"{status_icon} {step}: {result['status']}\n")
                if 'details' in result:
                    f.write(f"   详情: {result['details']}\n")
                f.write("\n")
            
            # 总体状态
            overall = report_data['overall_status']
            f.write(f"总体验证状态: {overall['status']}\n")
            f.write(f"成功步骤: {overall['passed_steps']}/{overall['total_steps']}\n")
            
            if overall['status'] == 'PASS':
                f.write("\n🎉 LC3plus编码器验证通过!\n")
            else:
                f.write("\n❌ LC3plus编码器验证失败，需要进一步调试。\n")
    
    def get_overall_status(self):
        """获取总体验证状态"""
        total_steps = len(self.step_results)
        passed_steps = sum(1 for result in self.step_results.values() 
                          if result['status'] == 'PASS')
        
        overall_status = 'PASS' if passed_steps == total_steps else 'FAIL'
        
        return {
            'status': overall_status,
            'total_steps': total_steps,
            'passed_steps': passed_steps,
            'failed_steps': total_steps - passed_steps
        }
    
    def run_verification(self, steps=None):
        """运行完整验证流程"""
        if steps is None:
            steps = self.verification_steps
        
        self.log("开始LC3plus编码器验证流程")
        self.log(f"验证步骤: {steps}")
        
        start_time = time.time()
        
        for step in steps:
            step_method = getattr(self, f'step_{step}', None)
            if step_method is None:
                self.log(f"未知验证步骤: {step}", "ERROR")
                continue
            
            if not step_method():
                self.log(f"步骤 {step} 失败，停止验证", "ERROR")
                break
        
        end_time = time.time()
        total_time = end_time - start_time
        
        self.log(f"验证流程完成，总耗时: {total_time:.2f} 秒")
        
        # 打印结果摘要
        self.print_summary()
        
        return self.get_overall_status()['status'] == 'PASS'
    
    def print_summary(self):
        """打印验证结果摘要"""
        print("\n" + "=" * 60)
        print("验证结果摘要")
        print("=" * 60)
        
        for step, result in self.step_results.items():
            status_icon = "✅" if result['status'] == 'PASS' else "❌"
            print(f"{status_icon} {step}: {result['status']}")
        
        overall = self.get_overall_status()
        print(f"\n总体状态: {overall['status']}")
        print(f"成功步骤: {overall['passed_steps']}/{overall['total_steps']}")
        
        if overall['status'] == 'PASS':
            print("\n🎉 LC3plus编码器验证成功!")
        else:
            print("\n❌ 验证失败，请检查报告了解详情。")

def main():
    parser = argparse.ArgumentParser(description='LC3plus编码器验证运行器')
    parser.add_argument('--steps', nargs='+', 
                       choices=['generate_test_vectors', 'compile_rtl', 
                               'run_simulation', 'analyze_results', 'generate_report'],
                       help='指定要运行的验证步骤')
    parser.add_argument('--simulator', choices=['iverilog', 'modelsim', 'questasim'],
                       default='iverilog', help='指定仿真器')
    parser.add_argument('--timeout', type=int, default=3600,
                       help='仿真超时时间(秒)')
    
    args = parser.parse_args()
    
    runner = LC3plusVerificationRunner()
    
    # 更新配置
    if args.simulator:
        runner.sim_config['simulator'] = args.simulator
    if args.timeout:
        runner.sim_config['timeout'] = args.timeout
    
    # 运行验证
    success = runner.run_verification(args.steps)
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main() 