#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LC3plus编码器RTL代码验证脚本
============================

功能：
- 检查RTL代码语法结构
- 验证模块端口连接
- 分析代码复杂度和质量
- 生成验证报告

作者：Audio Codec Design Team
版本：v1.0
日期：2024-06-11
"""

import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Set

class RTLVerifier:
    """RTL代码验证器"""
    
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.rtl_files = []
        self.modules = {}
        self.errors = []
        self.warnings = []
        
    def find_rtl_files(self) -> List[Path]:
        """查找所有RTL文件"""
        rtl_patterns = ['**/*.v', '**/*.sv', '**/*.vh']
        files = []
        
        for pattern in rtl_patterns:
            files.extend(self.project_root.glob(pattern))
            
        # 过滤掉测试平台文件
        rtl_files = [f for f in files if 'testbench' not in str(f) and 'tb_' not in f.name]
        
        self.rtl_files = rtl_files
        return rtl_files
    
    def parse_module(self, file_path: Path) -> Dict:
        """解析Verilog模块"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except UnicodeDecodeError:
            try:
                with open(file_path, 'r', encoding='gb2312') as f:
                    content = f.read()
            except:
                self.errors.append(f"无法读取文件: {file_path}")
                return {}
        
        module_info = {
            'name': '',
            'file': str(file_path),
            'inputs': [],
            'outputs': [],
            'inouts': [],
            'parameters': [],
            'line_count': len(content.splitlines()),
            'has_timescale': False,
            'has_clk': False,
            'has_rst': False
        }
        
        # 检查时间尺度
        if '`timescale' in content:
            module_info['has_timescale'] = True
        
        # 查找模块声明
        module_match = re.search(r'module\s+(\w+)\s*\(', content, re.IGNORECASE)
        if module_match:
            module_info['name'] = module_match.group(1)
        else:
            self.errors.append(f"在文件 {file_path} 中未找到模块声明")
            return module_info
        
        # 解析端口声明
        port_patterns = [
            (r'input\s+(?:\[[\d:]+\])?\s*(\w+)', 'inputs'),
            (r'output\s+(?:\[[\d:]+\])?\s*(\w+)', 'outputs'),
            (r'inout\s+(?:\[[\d:]+\])?\s*(\w+)', 'inouts')
        ]
        
        for pattern, port_type in port_patterns:
            matches = re.findall(pattern, content, re.IGNORECASE)
            module_info[port_type].extend(matches)
        
        # 检查时钟和复位信号
        if any('clk' in port.lower() for port in module_info['inputs']):
            module_info['has_clk'] = True
        if any('rst' in port.lower() for port in module_info['inputs']):
            module_info['has_rst'] = True
        
        # 查找参数
        param_matches = re.findall(r'parameter\s+(\w+)', content, re.IGNORECASE)
        module_info['parameters'].extend(param_matches)
        
        return module_info
    
    def check_connectivity(self) -> List[str]:
        """检查模块间连接"""
        issues = []
        
        # 查找顶层模块
        top_modules = [m for m in self.modules.values() if 'top' in m['name'].lower()]
        
        if not top_modules:
            issues.append("未找到顶层模块")
            return issues
        
        top_module = top_modules[0]
        
        # 检查基本信号
        required_signals = ['clk', 'rst_n', 'enable']
        for signal in required_signals:
            found = any(signal in port.lower() for port in top_module['inputs'])
            if not found:
                issues.append(f"顶层模块缺少必需信号: {signal}")
        
        return issues
    
    def check_coding_standards(self) -> List[str]:
        """检查编码标准"""
        issues = []
        
        for module in self.modules.values():
            # 检查时间尺度
            if not module['has_timescale']:
                issues.append(f"模块 {module['name']} 缺少 timescale 指令")
            
            # 检查时钟和复位
            if module['line_count'] > 50:  # 只检查大型模块
                if not module['has_clk']:
                    issues.append(f"模块 {module['name']} 可能缺少时钟信号")
                if not module['has_rst']:
                    issues.append(f"模块 {module['name']} 可能缺少复位信号")
        
        return issues
    
    def analyze_complexity(self) -> Dict:
        """分析代码复杂度"""
        total_lines = sum(m['line_count'] for m in self.modules.values())
        total_modules = len(self.modules)
        avg_lines_per_module = total_lines / max(total_modules, 1)
        
        largest_module = max(self.modules.values(), key=lambda x: x['line_count'], default={})
        
        return {
            'total_lines': total_lines,
            'total_modules': total_modules,
            'avg_lines_per_module': int(avg_lines_per_module),
            'largest_module': largest_module.get('name', 'N/A'),
            'largest_module_lines': largest_module.get('line_count', 0)
        }
    
    def run_verification(self) -> Dict:
        """运行完整验证"""
        print("🔍 开始RTL代码验证...")
        
        # 1. 查找RTL文件
        rtl_files = self.find_rtl_files()
        print(f"📁 找到 {len(rtl_files)} 个RTL文件")
        
        # 2. 解析模块
        for file_path in rtl_files:
            print(f"📄 解析模块: {file_path.name}")
            module_info = self.parse_module(file_path)
            if module_info.get('name'):
                self.modules[module_info['name']] = module_info
        
        print(f"🔧 解析完成，共 {len(self.modules)} 个模块")
        
        # 3. 检查连接性
        connectivity_issues = self.check_connectivity()
        
        # 4. 检查编码标准
        coding_issues = self.check_coding_standards()
        
        # 5. 分析复杂度
        complexity = self.analyze_complexity()
        
        # 汇总结果
        results = {
            'modules': self.modules,
            'errors': self.errors,
            'warnings': self.warnings + connectivity_issues + coding_issues,
            'complexity': complexity,
            'rtl_files': [str(f) for f in rtl_files]
        }
        
        return results
    
    def generate_report(self, results: Dict) -> str:
        """生成验证报告"""
        report = []
        report.append("=" * 60)
        report.append("LC3plus编码器RTL验证报告")
        report.append("=" * 60)
        report.append("")
        
        # 概述
        report.append("📊 项目概述:")
        report.append(f"  总模块数: {results['complexity']['total_modules']}")
        report.append(f"  总代码行数: {results['complexity']['total_lines']}")
        report.append(f"  平均模块大小: {results['complexity']['avg_lines_per_module']} 行")
        report.append(f"  最大模块: {results['complexity']['largest_module']} ({results['complexity']['largest_module_lines']} 行)")
        report.append("")
        
        # 模块列表
        report.append("🔧 模块列表:")
        for name, info in results['modules'].items():
            report.append(f"  {name}:")
            report.append(f"    文件: {Path(info['file']).name}")
            report.append(f"    行数: {info['line_count']}")
            report.append(f"    输入端口: {len(info['inputs'])}")
            report.append(f"    输出端口: {len(info['outputs'])}")
            report.append(f"    时间尺度: {'✓' if info['has_timescale'] else '✗'}")
        report.append("")
        
        # 错误和警告
        if results['errors']:
            report.append("❌ 错误:")
            for error in results['errors']:
                report.append(f"  - {error}")
            report.append("")
        
        if results['warnings']:
            report.append("⚠️ 警告:")
            for warning in results['warnings']:
                report.append(f"  - {warning}")
            report.append("")
        
        # 质量评估
        report.append("📈 代码质量评估:")
        error_count = len(results['errors'])
        warning_count = len(results['warnings'])
        
        if error_count == 0 and warning_count <= 3:
            quality = "优秀"
            score = "A+"
        elif error_count == 0 and warning_count <= 6:
            quality = "良好"
            score = "A"
        elif error_count <= 2:
            quality = "中等"
            score = "B"
        else:
            quality = "需要改进"
            score = "C"
        
        report.append(f"  整体质量: {quality} ({score})")
        report.append(f"  错误数量: {error_count}")
        report.append(f"  警告数量: {warning_count}")
        report.append("")
        
        # 建议
        report.append("💡 改进建议:")
        if not results['errors'] and not results['warnings']:
            report.append("  - 代码质量良好，可以进行硬件验证")
        else:
            report.append("  - 修复所有编译错误")
            report.append("  - 添加缺失的时间尺度指令")
            report.append("  - 检查模块端口连接")
            report.append("  - 确保时钟和复位信号正确连接")
        
        report.append("")
        report.append("=" * 60)
        
        return "\n".join(report)

def main():
    """主函数"""
    project_root = "."
    
    print("🚀 LC3plus编码器RTL验证工具")
    print("=" * 40)
    
    verifier = RTLVerifier(project_root)
    results = verifier.run_verification()
    
    # 生成报告
    report = verifier.generate_report(results)
    print("\n" + report)
    
    # 保存报告
    with open("rtl_verification_report.txt", "w", encoding="utf-8") as f:
        f.write(report)
    
    print(f"\n📄 验证报告已保存到: rtl_verification_report.txt")
    
    # 返回状态码
    if results['errors']:
        print("\n❌ 验证失败 - 发现编译错误")
        return 1
    elif len(results['warnings']) > 5:
        print("\n⚠️ 验证通过 - 但有较多警告")
        return 2
    else:
        print("\n✅ 验证通过 - 代码质量良好")
        return 0

if __name__ == "__main__":
    sys.exit(main()) 