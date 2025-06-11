@echo off
echo =============================================
echo LC3plus编码器RTL编译测试 (清洁版本)
echo =============================================

echo 正在编译RTL代码 (使用清洁测试平台)...

iverilog -g2012 -Wall -o sim/results/lc3plus_clean ^
  sim/testbench/tb_clean.sv ^
  rtl/processing/mdct_transform.v ^
  rtl/processing/spectral_analysis.v ^
  rtl/processing/quantization_control.v ^
  rtl/processing/entropy_coding.v ^
  rtl/processing/bitstream_packing.v ^
  rtl/lc3plus_encoder_top.v

if %ERRORLEVEL% equ 0 (
    echo.
    echo ✅ 编译成功！
    echo 可执行文件：sim/results/lc3plus_clean
    echo.
    echo 使用清洁版本测试平台，避免了语法兼容性问题
) else (
    echo.
    echo ❌ 编译失败，错误代码：%ERRORLEVEL%
    echo 请检查上面的错误信息
)

echo.
echo ============================================= 