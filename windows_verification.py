#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
LC3plus编码器Windows验证脚本
功能：在Windows环境下验证RTL代码的完整性和质量
作者：Audio Codec Design Team
版本：v1.0
日期：2024-06-11
"""

import os
import re
import sys
from pathlib import Path
from datetime import datetime

def print_header(title):
    """打印带颜色的标题"""
    print(f"\n{'='*60}")
    print(f"🚀 {title}")
    print('='*60)

def print_success(msg):
    """打印成功消息"""
    print(f"✅ {msg}")

def print_error(msg):
    """打印错误消息"""
    print(f"❌ {msg}")

def print_warning(msg):
    """打印警告消息"""
    print(f"⚠️  {msg}")

def print_info(msg):
    """打印信息消息"""
    print(f"ℹ️  {msg}")

class RTLVerifier:
    """RTL代码验证器"""
    
    def __init__(self, project_root):
        self.project_root = Path(project_root)
        self.rtl_dir = self.project_root / "rtl"
        self.sim_dir = self.project_root / "sim"
        self.errors = []
        self.warnings = []
        self.modules = {}
        
    def find_rtl_files(self):
        """查找所有RTL文件"""
        rtl_files = []
        for pattern in ["**/*.v", "**/*.sv"]:
            rtl_files.extend(self.rtl_dir.glob(pattern))
        return sorted(rtl_files)
    
    def parse_module(self, file_path):
        """解析Verilog模块"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # 查找模块声明
            module_pattern = r'module\s+(\w+)'
            module_match = re.search(module_pattern, content)
            
            if not module_match:
                return None
                
            module_name = module_match.group(1)
            
            # 统计代码行数
            lines = content.split('\n')
            non_empty_lines = [line for line in lines if line.strip() and not line.strip().startswith('//')]
            code_lines = len(non_empty_lines)
            
            # 检查时间尺度
            has_timescale = '`timescale' in content
            
            # 统计端口
            input_ports = len(re.findall(r'\binput\b', content))
            output_ports = len(re.findall(r'\boutput\b', content))
            
            return {
                'name': module_name,
                'file': file_path.name,
                'path': str(file_path),
                'lines': code_lines,
                'has_timescale': has_timescale,
                'input_ports': input_ports,
                'output_ports': output_ports
            }
            
        except Exception as e:
            self.errors.append(f"解析文件 {file_path} 时出错: {e}")
            return None
    
    def check_file_structure(self):
        """检查文件结构"""
        print_info("检查项目文件结构...")
        
        required_dirs = [
            self.project_root / "rtl",
            self.project_root / "sim",
            self.project_root / "docs"
        ]
        
        for dir_path in required_dirs:
            if dir_path.exists():
                print_success(f"目录存在: {dir_path.name}")
            else:
                self.warnings.append(f"缺少目录: {dir_path}")
    
    def check_core_modules(self):
        """检查核心模块"""
        print_info("检查核心处理模块...")
        
        required_modules = {
            'mdct_transform.v': 'MDCT变换模块',
            'spectral_analysis.v': '频谱分析模块',
            'quantization_control.v': '量化控制模块',
            'entropy_coding.v': '熵编码模块',
            'bitstream_packing.v': '比特流打包模块'
        }
        
        processing_dir = self.rtl_dir / "processing"
        
        for filename, description in required_modules.items():
            file_path = processing_dir / filename
            if file_path.exists():
                print_success(f"{description}: {filename}")
            else:
                self.errors.append(f"缺少{description}: {filename}")
    
    def check_memory_modules(self):
        """检查存储器模块"""
        print_info("检查存储器模块...")
        
        memory_modules = {
            'audio_buffer_ram.v': '音频缓冲RAM',
            'work_buffer_ram.v': '工作缓冲RAM',
            'coeff_storage_rom.v': '系数存储ROM'
        }
        
        memory_dir = self.rtl_dir / "memory"
        
        for filename, description in memory_modules.items():
            file_path = memory_dir / filename
            if file_path.exists():
                print_success(f"{description}: {filename}")
            else:
                self.warnings.append(f"缺少{description}: {filename}")
    
    def check_top_module(self):
        """检查顶层模块"""
        print_info("检查顶层集成模块...")
        
        top_files = list(self.rtl_dir.glob("*top*.v"))
        if top_files:
            for top_file in top_files:
                print_success(f"找到顶层模块: {top_file.name}")
        else:
            self.errors.append("未找到顶层模块文件")
    
    def analyze_code_quality(self):
        """分析代码质量"""
        print_info("分析代码质量...")
        
        rtl_files = self.find_rtl_files()
        total_lines = 0
        modules_with_timescale = 0
        
        for file_path in rtl_files:
            module_info = self.parse_module(file_path)
            if module_info:
                self.modules[module_info['name']] = module_info
                total_lines += module_info['lines']
                
                if module_info['has_timescale']:
                    modules_with_timescale += 1
                else:
                    self.warnings.append(f"模块 {module_info['name']} 缺少时间尺度声明")
        
        print_success(f"找到 {len(self.modules)} 个模块")
        print_success(f"总代码行数: {total_lines}")
        print_success(f"平均模块大小: {total_lines // len(self.modules) if self.modules else 0} 行")
        
        if modules_with_timescale == len(self.modules):
            print_success("所有模块都有时间尺度声明")
        else:
            print_warning(f"{modules_with_timescale}/{len(self.modules)} 模块有时间尺度声明")
    
    def check_testbench(self):
        """检查测试平台"""
        print_info("检查验证环境...")
        
        tb_dir = self.sim_dir / "testbench"
        if not tb_dir.exists():
            self.warnings.append("缺少测试平台目录")
            return
        
        tb_files = list(tb_dir.glob("tb_*.sv")) + list(tb_dir.glob("tb_*.v"))
        if tb_files:
            for tb_file in tb_files:
                print_success(f"找到测试平台: {tb_file.name}")
        else:
            self.warnings.append("未找到测试平台文件")
    
    def generate_report(self):
        """生成验证报告"""
        print_header("生成验证报告")
        
        # 计算总体评分
        total_score = 100
        total_score -= len(self.errors) * 20  # 每个错误扣20分
        total_score -= len(self.warnings) * 5  # 每个警告扣5分
        total_score = max(0, total_score)
        
        # 确定等级
        if total_score >= 90:
            grade = "A+ (优秀)"
        elif total_score >= 80:
            grade = "A (良好)"
        elif total_score >= 70:
            grade = "B (合格)"
        else:
            grade = "C (需要改进)"
        
        print(f"\n📊 项目统计:")
        print(f"  总模块数: {len(self.modules)}")
        print(f"  总代码行数: {sum(m['lines'] for m in self.modules.values())}")
        print(f"  错误数量: {len(self.errors)}")
        print(f"  警告数量: {len(self.warnings)}")
        print(f"\n📈 代码质量: {grade}")
        print(f"  总体评分: {total_score}/100")
        
        if self.errors:
            print(f"\n❌ 发现错误:")
            for error in self.errors:
                print(f"  - {error}")
        
        if self.warnings:
            print(f"\n⚠️  发现警告:")
            for warning in self.warnings:
                print(f"  - {warning}")
        
        # 保存报告
        report_path = self.project_root / "windows_verification_report.txt"
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write("LC3plus编码器Windows验证报告\n")
            f.write("="*50 + "\n\n")
            f.write(f"验证时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"项目路径: {self.project_root}\n\n")
            
            f.write(f"项目统计:\n")
            f.write(f"  总模块数: {len(self.modules)}\n")
            f.write(f"  总代码行数: {sum(m['lines'] for m in self.modules.values())}\n")
            f.write(f"  错误数量: {len(self.errors)}\n")
            f.write(f"  警告数量: {len(self.warnings)}\n\n")
            
            f.write(f"代码质量: {grade}\n")
            f.write(f"总体评分: {total_score}/100\n\n")
            
            if self.modules:
                f.write("模块详情:\n")
                for name, info in self.modules.items():
                    f.write(f"  {name}:\n")
                    f.write(f"    文件: {info['file']}\n")
                    f.write(f"    行数: {info['lines']}\n")
                    f.write(f"    输入端口: {info['input_ports']}\n")
                    f.write(f"    输出端口: {info['output_ports']}\n")
                    f.write(f"    时间尺度: {'✓' if info['has_timescale'] else '✗'}\n\n")
            
            if self.errors:
                f.write("错误列表:\n")
                for error in self.errors:
                    f.write(f"  - {error}\n")
                f.write("\n")
            
            if self.warnings:
                f.write("警告列表:\n")
                for warning in self.warnings:
                    f.write(f"  - {warning}\n")
        
        print_success(f"验证报告已保存到: {report_path}")
        
        return total_score >= 70  # 70分及以上视为验证通过
    
    def run_verification(self):
        """运行完整验证"""
        print_header("LC3plus编码器Windows环境验证")
        
        self.check_file_structure()
        self.check_core_modules()
        self.check_memory_modules()
        self.check_top_module()
        self.analyze_code_quality()
        self.check_testbench()
        
        success = self.generate_report()
        
        if success:
            print_success("✅ 验证通过！项目状态良好")
        else:
            print_error("❌ 验证失败，需要修复问题")
        
        return success

def main():
    """主函数"""
    if len(sys.argv) > 1:
        project_root = sys.argv[1]
    else:
        project_root = os.getcwd()
    
    verifier = RTLVerifier(project_root)
    success = verifier.run_verification()
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main() 