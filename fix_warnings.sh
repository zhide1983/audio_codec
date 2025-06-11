#!/bin/bash

echo "修复RTL模块中的位选择警告..."

# 修复 mdct_transform.v 中的问题
echo "修复 mdct_transform.v..."
sed -i 's/output_count\[15:0\]/6'\''h0, output_count/g' rtl/processing/mdct_transform.v

# 修复 spectral_analysis.v 中的问题
echo "修复 spectral_analysis.v..."
sed -i 's/coefficient_count\[15:0\]/6'\''h0, coefficient_count/g' rtl/processing/spectral_analysis.v

echo "警告修复完成！"

# 验证修复结果
echo "验证修复结果..."
echo "mdct_transform.v中的调试信息赋值:"
grep -n "coefficient_count\|output_count" rtl/processing/mdct_transform.v | tail -3

echo "spectral_analysis.v中的调试信息赋值:"
grep -n "coefficient_count\|output_count" rtl/processing/spectral_analysis.v | tail -3 