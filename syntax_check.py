#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Verilog语法检查工具
==================

检查常见的Verilog语法错误，特别是iverilog编译器会报告的问题
"""

import re
import os
from pathlib import Path

def check_task_calls(content, filename):
    """检查任务调用语法"""
    errors = []
    warnings = []
    
    # 查找任务定义
    task_definitions = re.findall(r'task\s+(\w+)', content)
    
    # 查找任务调用 - 检查是否有空括号
    for task_name in task_definitions:
        # 查找带空括号的任务调用
        empty_parens_calls = re.findall(fr'{task_name}\s*\(\s*\)\s*;', content)
        if empty_parens_calls:
            errors.append(f"任务 '{task_name}' 使用了空括号调用，应该使用无括号调用")
    
    return errors, warnings

def check_break_statements(content, filename):
    """检查break语句（iverilog不支持）"""
    errors = []
    
    break_matches = re.finditer(r'\bbreak\s*;', content)
    for match in break_matches:
        line_num = content[:match.start()].count('\n') + 1
        errors.append(f"第{line_num}行: 使用了break语句，iverilog不支持")
    
    return errors

def check_timescale(content, filename):
    """检查timescale指令"""
    warnings = []
    
    if '`timescale' not in content:
        warnings.append(f"缺少timescale指令")
    
    return warnings

def check_function_conflicts(content, filename):
    """检查函数名与端口名冲突"""
    errors = []
    
    # 查找端口声明
    input_ports = re.findall(r'input\s+(?:\[[\d:]+\])?\s*(\w+)', content)
    output_ports = re.findall(r'output\s+(?:\[[\d:]+\])?\s*(\w+)', content)
    all_ports = set(input_ports + output_ports)
    
    # 查找函数定义
    functions = re.findall(r'function\s+(?:\[[\d:]+\])?\s*(\w+)', content)
    
    # 检查冲突
    for func in functions:
        if func in all_ports:
            errors.append(f"函数 '{func}' 与端口名冲突")
    
    return errors

def check_file(filepath):
    """检查单个文件"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except UnicodeDecodeError:
        try:
            with open(filepath, 'r', encoding='gb2312') as f:
                content = f.read()
        except Exception as e:
            return [f"无法读取文件: {e}"], []
    
    filename = Path(filepath).name
    errors = []
    warnings = []
    
    # 执行各项检查
    task_errors, task_warnings = check_task_calls(content, filename)
    errors.extend(task_errors)
    warnings.extend(task_warnings)
    
    break_errors = check_break_statements(content, filename)
    errors.extend(break_errors)
    
    timescale_warnings = check_timescale(content, filename)
    warnings.extend(timescale_warnings)
    
    function_errors = check_function_conflicts(content, filename)
    errors.extend(function_errors)
    
    return errors, warnings

def main():
    """主函数"""
    print("🔍 Verilog语法检查工具")
    print("=" * 40)
    
    # 要检查的文件
    files_to_check = [
        "sim/testbench/tb_simple_encoder.sv",
        "rtl/processing/spectral_analysis.v",
        "rtl/processing/quantization_control.v",
        "rtl/processing/entropy_coding.v", 
        "rtl/processing/bitstream_packing.v",
        "rtl/lc3plus_encoder_top.v"
    ]
    
    total_errors = 0
    total_warnings = 0
    
    for filepath in files_to_check:
        if not os.path.exists(filepath):
            print(f"⚠️ 文件不存在: {filepath}")
            continue
            
        print(f"\n📄 检查文件: {Path(filepath).name}")
        errors, warnings = check_file(filepath)
        
        if errors:
            print(f"❌ 发现 {len(errors)} 个错误:")
            for error in errors:
                print(f"   - {error}")
        
        if warnings:
            print(f"⚠️ 发现 {len(warnings)} 个警告:")
            for warning in warnings:
                print(f"   - {warning}")
        
        if not errors and not warnings:
            print("✅ 语法检查通过")
        
        total_errors += len(errors)
        total_warnings += len(warnings)
    
    print("\n" + "=" * 40)
    print("📊 检查总结:")
    print(f"   总错误数: {total_errors}")
    print(f"   总警告数: {total_warnings}")
    
    if total_errors == 0:
        print("\n✅ 所有文件语法检查通过！")
        print("   代码应该可以在iverilog中正确编译")
        return 0
    else:
        print("\n❌ 发现语法错误，需要修复")
        return 1

if __name__ == "__main__":
    exit(main()) 