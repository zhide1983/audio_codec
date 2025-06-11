#!/usr/bin/env python3
"""
LC3plus测试向量生成脚本 (LC3plus Test Vector Generator)

功能：使用LC3plus参考C代码生成测试向量和参考比特流
作者：Audio Codec Design Team
版本：v1.0
日期：2024-06-11
"""

import os
import sys
import subprocess
import numpy as np
import wave
import struct
import argparse
from pathlib import Path

class LC3plusTestVectorGenerator:
    def __init__(self, reference_path="../LC3plus_ETSI_src_v17171_20200723"):
        """初始化测试向量生成器"""
        self.reference_path = Path(reference_path)
        self.test_vector_path = Path("../sim/test_vectors")
        self.reference_output_path = Path("../sim/reference")
        self.results_path = Path("../sim/results")
        
        # 创建输出目录
        self.test_vector_path.mkdir(parents=True, exist_ok=True)
        self.reference_output_path.mkdir(parents=True, exist_ok=True)
        self.results_path.mkdir(parents=True, exist_ok=True)
        
        # 测试配置列表
        self.test_configs = [
            {
                'sample_rate': 16000,
                'frame_duration': 10,  # ms
                'bitrate': 32,         # kbps
                'channels': 1,
                'name': '16k_10ms_32k_mono'
            },
            {
                'sample_rate': 24000,
                'frame_duration': 10,
                'bitrate': 64,
                'channels': 1,
                'name': '24k_10ms_64k_mono'
            },
            {
                'sample_rate': 48000,
                'frame_duration': 10,
                'bitrate': 128,
                'channels': 1,
                'name': '48k_10ms_128k_mono'
            },
            {
                'sample_rate': 48000,
                'frame_duration': 10,
                'bitrate': 256,
                'channels': 2,
                'name': '48k_10ms_256k_stereo'
            }
        ]
        
    def build_reference_encoder(self):
        """编译LC3plus参考编码器"""
        print("正在编译LC3plus参考编码器...")
        
        build_dir = self.reference_path / "build"
        build_dir.mkdir(exist_ok=True)
        
        try:
            # 运行cmake配置
            subprocess.run([
                "cmake", 
                "-S", str(self.reference_path),
                "-B", str(build_dir)
            ], check=True, capture_output=True, text=True)
            
            # 编译
            subprocess.run([
                "cmake", 
                "--build", str(build_dir),
                "--config", "Release"
            ], check=True, capture_output=True, text=True)
            
            print("LC3plus参考编码器编译成功")
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"编译失败: {e}")
            return False
    
    def generate_test_audio(self, sample_rate, duration_sec, channels, frequency=1000):
        """生成测试音频信号"""
        samples = int(sample_rate * duration_sec)
        t = np.linspace(0, duration_sec, samples, False)
        
        # 生成多频正弦波合成信号
        audio = np.zeros((samples, channels))
        
        for ch in range(channels):
            # 每个通道使用不同的频率组合
            freq_offset = ch * 100
            
            # 基频 + 谐波
            signal = (
                0.5 * np.sin(2 * np.pi * (frequency + freq_offset) * t) +
                0.3 * np.sin(2 * np.pi * (frequency * 2 + freq_offset) * t) +
                0.2 * np.sin(2 * np.pi * (frequency * 3 + freq_offset) * t) +
                0.1 * np.sin(2 * np.pi * (frequency * 4 + freq_offset) * t)
            )
            
            # 添加少量噪声使信号更真实
            noise = np.random.normal(0, 0.01, samples)
            signal += noise
            
            # 应用包络以避免突变
            envelope = np.ones(samples)
            fade_samples = int(0.01 * sample_rate)  # 10ms淡入淡出
            envelope[:fade_samples] = np.linspace(0, 1, fade_samples)
            envelope[-fade_samples:] = np.linspace(1, 0, fade_samples)
            
            signal *= envelope
            audio[:, ch] = signal
        
        # 归一化到16位PCM范围
        audio = np.clip(audio * 32767, -32768, 32767).astype(np.int16)
        
        return audio
    
    def save_pcm_file(self, audio_data, filename):
        """保存PCM文件"""
        with open(filename, 'wb') as f:
            for sample in audio_data:
                if len(sample.shape) == 0:  # 单声道
                    f.write(struct.pack('<h', int(sample)))
                else:  # 多声道
                    for ch_sample in sample:
                        f.write(struct.pack('<h', int(ch_sample)))
    
    def save_wav_file(self, audio_data, filename, sample_rate):
        """保存WAV文件"""
        with wave.open(str(filename), 'wb') as wav_file:
            wav_file.setnchannels(audio_data.shape[1] if len(audio_data.shape) > 1 else 1)
            wav_file.setsampwidth(2)  # 16-bit
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(audio_data.tobytes())
    
    def run_reference_encoder(self, input_wav, output_lc3, config):
        """运行LC3plus参考编码器"""
        encoder_path = self.reference_path / "build" / "lc3plus_encoder"
        
        # 检查编码器是否存在
        if not encoder_path.exists():
            # 尝试其他可能的路径
            encoder_paths = [
                self.reference_path / "build" / "Release" / "lc3plus_encoder.exe",
                self.reference_path / "build" / "lc3plus_encoder.exe",
                self.reference_path / "cmake-build-debug" / "lc3plus_encoder.exe"
            ]
            
            for path in encoder_paths:
                if path.exists():
                    encoder_path = path
                    break
            else:
                print(f"找不到LC3plus编码器: {encoder_path}")
                return False
        
        # 构建命令行参数
        cmd = [
            str(encoder_path),
            str(input_wav),
            str(output_lc3),
            f"{config['bitrate']}",
            f"-r{config['sample_rate']}",
            f"-f{config['frame_duration']}"
        ]
        
        try:
            print(f"运行命令: {' '.join(cmd)}")
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                print(f"编码成功: {output_lc3}")
                return True
            else:
                print(f"编码失败: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            print("编码超时")
            return False
        except Exception as e:
            print(f"编码异常: {e}")
            return False
    
    def generate_all_test_vectors(self):
        """生成所有测试配置的测试向量"""
        print("开始生成LC3plus测试向量...")
        
        # 首先编译参考编码器
        if not self.build_reference_encoder():
            print("无法编译参考编码器，退出")
            return False
        
        success_count = 0
        total_count = len(self.test_configs)
        
        for i, config in enumerate(self.test_configs):
            print(f"\n=== 生成测试向量 {i+1}/{total_count}: {config['name']} ===")
            
            # 生成测试音频 (5秒)
            duration = 5.0  # 秒
            audio_data = self.generate_test_audio(
                config['sample_rate'], 
                duration, 
                config['channels']
            )
            
            # 文件名
            pcm_file = self.test_vector_path / f"pcm_{config['name']}.raw"
            wav_file = self.test_vector_path / f"pcm_{config['name']}.wav"
            lc3_file = self.reference_output_path / f"ref_{config['name']}.lc3"
            
            # 保存PCM和WAV文件
            self.save_pcm_file(audio_data, pcm_file)
            self.save_wav_file(audio_data, wav_file, config['sample_rate'])
            
            print(f"生成音频文件: {wav_file}")
            print(f"  采样率: {config['sample_rate']} Hz")
            print(f"  时长: {duration} 秒")
            print(f"  通道数: {config['channels']}")
            print(f"  样本数: {len(audio_data)}")
            
            # 运行参考编码器
            if self.run_reference_encoder(wav_file, lc3_file, config):
                success_count += 1
                print(f"参考比特流生成: {lc3_file}")
                
                # 验证输出文件
                if lc3_file.exists():
                    file_size = lc3_file.stat().st_size
                    print(f"比特流文件大小: {file_size} 字节")
                else:
                    print("警告: 比特流文件未生成")
            else:
                print(f"配置 {config['name']} 编码失败")
        
        print(f"\n=== 测试向量生成完成 ===")
        print(f"成功: {success_count}/{total_count}")
        
        # 生成测试向量清单
        self.generate_test_manifest()
        
        return success_count == total_count
    
    def generate_test_manifest(self):
        """生成测试向量清单文件"""
        manifest_file = self.test_vector_path / "test_manifest.txt"
        
        with open(manifest_file, 'w') as f:
            f.write("# LC3plus测试向量清单\n")
            f.write("# 格式: 配置名,采样率,帧长(ms),比特率(kbps),通道数,PCM文件,参考文件\n")
            f.write("\n")
            
            for config in self.test_configs:
                f.write(f"{config['name']},{config['sample_rate']},{config['frame_duration']},")
                f.write(f"{config['bitrate']},{config['channels']},")
                f.write(f"pcm_{config['name']}.raw,ref_{config['name']}.lc3\n")
        
        print(f"测试清单生成: {manifest_file}")
    
    def verify_test_vectors(self):
        """验证生成的测试向量"""
        print("\n验证测试向量...")
        
        for config in self.test_configs:
            pcm_file = self.test_vector_path / f"pcm_{config['name']}.raw"
            wav_file = self.test_vector_path / f"pcm_{config['name']}.wav"
            lc3_file = self.reference_output_path / f"ref_{config['name']}.lc3"
            
            print(f"\n配置: {config['name']}")
            
            # 检查文件存在性
            if pcm_file.exists():
                size = pcm_file.stat().st_size
                expected_samples = config['sample_rate'] * 5  # 5秒
                expected_size = expected_samples * 2 * config['channels']  # 16位
                print(f"  PCM文件: {size} 字节 (期望: {expected_size})")
            else:
                print(f"  PCM文件: 缺失")
            
            if wav_file.exists():
                print(f"  WAV文件: 存在")
            else:
                print(f"  WAV文件: 缺失")
            
            if lc3_file.exists():
                size = lc3_file.stat().st_size
                print(f"  LC3文件: {size} 字节")
            else:
                print(f"  LC3文件: 缺失")

def main():
    parser = argparse.ArgumentParser(description='LC3plus测试向量生成器')
    parser.add_argument('--reference-path', 
                       default='../LC3plus_ETSI_src_v17171_20200723',
                       help='LC3plus参考代码路径')
    parser.add_argument('--verify-only', action='store_true',
                       help='仅验证现有测试向量')
    
    args = parser.parse_args()
    
    generator = LC3plusTestVectorGenerator(args.reference_path)
    
    if args.verify_only:
        generator.verify_test_vectors()
    else:
        if generator.generate_all_test_vectors():
            print("\n所有测试向量生成成功!")
            generator.verify_test_vectors()
        else:
            print("\n测试向量生成失败!")
            sys.exit(1)

if __name__ == "__main__":
    main() 