#!/usr/bin/env python3
"""
RTL设计规则检查脚本
检查Verilog代码是否符合项目设计约束：
1. 禁用移位操作符 (<<, >>, >>>)
2. 禁用非常数循环次数的for语句
3. 验证单端口存储器使用
4. 检查Verilog 2001标准遵循

Author: Audio Codec Design Team
Date: 2024-06-11
Version: 1.0
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Tuple, Dict
import argparse

class RTLRuleChecker:
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.shift_operators = ['<<', '>>', '>>>']
        
    def check_file(self, filepath: str) -> bool:
        """检查单个Verilog文件"""
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
                lines = content.splitlines()
                
            self.check_shift_operators(filepath, lines)
            self.check_for_loops(filepath, lines)
            self.check_memory_ports(filepath, lines)
            self.check_verilog_standard(filepath, lines)
            
            return len(self.errors) == 0
            
        except Exception as e:
            self.errors.append(f"{filepath}: 文件读取错误 - {str(e)}")
            return False
    
    def check_shift_operators(self, filepath: str, lines: List[str]):
        """检查移位操作符使用"""
        for line_num, line in enumerate(lines, 1):
            # 移除注释
            comment_pos = line.find('//')
            if comment_pos >= 0:
                line = line[:comment_pos]
            
            # 检查移位操作符
            for op in self.shift_operators:
                if op in line:
                    # 确认不是在字符串中
                    if not self._in_string(line, line.find(op)):
                        self.errors.append(
                            f"{filepath}:{line_num}: 禁用移位操作符 '{op}' - {line.strip()}"
                        )
    
    def check_for_loops(self, filepath: str, lines: List[str]):
        """检查for循环约束"""
        for line_num, line in enumerate(lines, 1):
            # 移除注释
            comment_pos = line.find('//')
            if comment_pos >= 0:
                line = line[:comment_pos]
            
            # 检查for循环
            if 'for' in line.lower() and '(' in line:
                # 提取for循环条件
                for_match = re.search(r'for\s*\(\s*.*?;\s*(.*?);\s*.*?\)', line, re.IGNORECASE)
                if for_match:
                    condition = for_match.group(1).strip()
                    if not self._is_constant_loop_condition(condition):
                        self.errors.append(
                            f"{filepath}:{line_num}: 禁用非常数循环次数的for语句 - {line.strip()}"
                        )
    
    def check_memory_ports(self, filepath: str, lines: List[str]):
        """检查存储器端口使用"""
        dual_port_indicators = [
            '_a', '_b',           # 端口A/B命名
            'addr_a', 'addr_b',   # 双端口地址
            'wdata_a', 'wdata_b', # 双端口写数据
            'rdata_a', 'rdata_b'  # 双端口读数据
        ]
        
        for line_num, line in enumerate(lines, 1):
            # 移除注释
            comment_pos = line.find('//')
            if comment_pos >= 0:
                line = line[:comment_pos]
            
            for indicator in dual_port_indicators:
                if indicator in line.lower():
                    # 检查是否在仲裁器模块中（仲裁器允许有这些信号）
                    if 'arbiter' not in filepath.lower():
                        self.warnings.append(
                            f"{filepath}:{line_num}: 疑似双端口存储器使用 '{indicator}' - {line.strip()}"
                        )
    
    def check_verilog_standard(self, filepath: str, lines: List[str]):
        """检查Verilog 2001标准遵循"""
        # SystemVerilog特性检查
        sv_features = [
            'logic', 'bit', 'byte',      # SystemVerilog数据类型
            'interface', 'modport',       # 接口特性
            'class', 'package',           # OOP特性
            'always_ff', 'always_comb',   # SystemVerilog always
            'unique', 'priority',         # 案例语句修饰符
            '.*',                         # 通配符连接
        ]
        
        for line_num, line in enumerate(lines, 1):
            # 移除注释和字符串
            comment_pos = line.find('//')
            if comment_pos >= 0:
                line = line[:comment_pos]
            
            for feature in sv_features:
                if feature in line:
                    # 排除在注释或字符串中的情况
                    if not self._in_string(line, line.find(feature)):
                        self.warnings.append(
                            f"{filepath}:{line_num}: 可能的SystemVerilog特性 '{feature}' - {line.strip()}"
                        )
    
    def _in_string(self, line: str, pos: int) -> bool:
        """检查位置是否在字符串内"""
        if pos < 0:
            return False
        
        quote_count = 0
        for i in range(pos):
            if line[i] == '"' and (i == 0 or line[i-1] != '\\'):
                quote_count += 1
        
        return quote_count % 2 == 1
    
    def _is_constant_loop_condition(self, condition: str) -> bool:
        """检查循环条件是否为常数"""
        # 简单的常数检查
        constant_patterns = [
            r'\b\d+\b',                    # 纯数字
            r'\b[A-Z_][A-Z0-9_]*\b',      # 参数或常数（大写）
            r'\bparameter\b',              # parameter关键字
            r'\blocalparam\b',             # localparam关键字
        ]
        
        # 检查是否包含变量（小写开头的标识符）
        variable_pattern = r'\b[a-z][a-zA-Z0-9_]*\b'
        variables = re.findall(variable_pattern, condition)
        
        # 排除已知的常数关键字
        constants = ['i', 'j', 'k']  # 循环变量本身不算
        variables = [v for v in variables if v not in constants]
        
        return len(variables) == 0
    
    def check_directory(self, directory: str, pattern: str = "*.v") -> bool:
        """检查目录下的所有Verilog文件"""
        verilog_files = []
        for root, dirs, files in os.walk(directory):
            for file in files:
                if file.endswith('.v') or file.endswith('.vh'):
                    verilog_files.append(os.path.join(root, file))
        
        success = True
        for filepath in verilog_files:
            print(f"检查文件: {filepath}")
            if not self.check_file(filepath):
                success = False
        
        return success
    
    def print_report(self):
        """打印检查报告"""
        print("\n" + "="*80)
        print("RTL设计规则检查报告")
        print("="*80)
        
        if self.errors:
            print(f"\n❌ 发现 {len(self.errors)} 个错误:")
            for error in self.errors:
                print(f"  {error}")
        
        if self.warnings:
            print(f"\n⚠️  发现 {len(self.warnings)} 个警告:")
            for warning in self.warnings:
                print(f"  {warning}")
        
        if not self.errors and not self.warnings:
            print("\n✅ 所有检查通过，代码符合RTL设计规则")
        
        print(f"\n检查摘要:")
        print(f"  错误: {len(self.errors)}")
        print(f"  警告: {len(self.warnings)}")
        print("="*80)

def main():
    parser = argparse.ArgumentParser(description='RTL设计规则检查工具')
    parser.add_argument('path', help='要检查的文件或目录路径')
    parser.add_argument('--strict', action='store_true', help='严格模式，警告也视为错误')
    parser.add_argument('--exclude', nargs='*', default=[], help='排除的文件模式')
    
    args = parser.parse_args()
    
    checker = RTLRuleChecker()
    
    if os.path.isfile(args.path):
        success = checker.check_file(args.path)
    elif os.path.isdir(args.path):
        success = checker.check_directory(args.path)
    else:
        print(f"错误: 路径 {args.path} 不存在")
        return 1
    
    checker.print_report()
    
    # 确定退出码
    if args.strict:
        exit_code = 0 if (len(checker.errors) == 0 and len(checker.warnings) == 0) else 1
    else:
        exit_code = 0 if len(checker.errors) == 0 else 1
    
    return exit_code

if __name__ == "__main__":
    sys.exit(main()) 