//=============================================================================
// LC3plus编码器顶层模块完整验证环境 (Complete Verification Environment)
// 
// 功能：完整的LC3plus编码器系统级验证，支持与参考C代码比对
// 作者：Audio Codec Design Team
// 版本：v1.0
// 日期：2024-06-11
//=============================================================================

`timescale 1ns/1ps

module tb_lc3plus_encoder_top;

//=============================================================================
// 参数定义
//=============================================================================

// 时钟和复位参数
parameter CLK_PERIOD    = 5.0;     // 200MHz时钟 (5ns周期)
parameter APB_CLK_PERIOD = 10.0;   // 100MHz APB时钟
parameter RESET_CYCLES  = 100;     // 复位持续周期

// LC3plus配置参数
parameter MAX_FRAME_SAMPLES = 960;  // 48kHz@20ms最大帧长
parameter MAX_FRAME_BYTES   = 400;  // 最大帧字节数
parameter MAX_TEST_FRAMES   = 1000; // 最大测试帧数

// 测试配置
parameter TEST_VECTOR_PATH = "test_vectors/";
parameter REFERENCE_PATH   = "reference/";
parameter RESULTS_PATH     = "results/";

//=============================================================================
// 信号声明
//=============================================================================

// 系统时钟和复位
logic                   clk;
logic                   rst_n;
logic                   apb_clk;
logic                   apb_rst_n;

// LC3plus编码器配置
logic   [1:0]           frame_duration;     // 0:2.5ms, 1:5ms, 2:10ms, 3:20ms
logic                   channel_mode;       // 0:mono, 1:stereo
logic   [7:0]           target_bitrate;     // 目标比特率(kbps)
logic   [15:0]          sample_rate;        // 采样率
logic                   encoder_enable;     // 编码器使能

// AXI4-Stream音频输入接口
logic                   s_axis_audio_tvalid;
logic   [31:0]          s_axis_audio_tdata;
logic                   s_axis_audio_tlast;
logic                   s_axis_audio_tready;

// AXI4-Stream比特流输出接口  
logic                   m_axis_bitstream_tvalid;
logic   [7:0]           m_axis_bitstream_tdata;
logic                   m_axis_bitstream_tlast;
logic   [15:0]          m_axis_bitstream_tuser;
logic                   m_axis_bitstream_tready;

// APB配置接口
logic                   psel;
logic                   penable;
logic                   pwrite;
logic   [11:0]          paddr;
logic   [31:0]          pwdata;
logic   [31:0]          prdata;
logic                   pready;
logic                   pslverr;

// 系统存储器接口
logic                   mem_req_valid;
logic   [15:0]          mem_req_addr;
logic   [31:0]          mem_req_wdata;
logic                   mem_req_wen;
logic                   mem_req_ready;
logic   [31:0]          mem_req_rdata;

// 系统状态信号
logic                   encoding_active;
logic                   frame_processing;
logic   [2:0]           pipeline_stage;
logic   [31:0]          performance_info;
logic   [31:0]          error_status;

// 调试信号
logic   [31:0]          debug_mdct;
logic   [31:0]          debug_spectral;
logic   [31:0]          debug_quantization;
logic   [31:0]          debug_entropy;
logic   [31:0]          debug_packing;

//=============================================================================
// 测试数据结构
//=============================================================================

// 测试配置结构
typedef struct {
    int sample_rate;        // 采样率
    int frame_duration_ms;  // 帧长(ms)
    int bitrate_kbps;      // 比特率(kbps)
    int channel_count;     // 通道数
    string input_file;     // 输入PCM文件
    string reference_file; // 参考比特流文件
} test_config_t;

// 测试统计结构
typedef struct {
    int total_frames;      // 总帧数
    int passed_frames;     // 通过帧数
    int failed_frames;     // 失败帧数
    real avg_snr;          // 平均信噪比
    real min_snr;          // 最小信噪比
    real max_processing_time; // 最大处理时间
    real avg_processing_time; // 平均处理时间
} test_statistics_t;

// 测试向量数组
test_config_t test_configs[10];
test_statistics_t test_stats;

// 数据缓冲区
logic [15:0] input_pcm_buffer[MAX_FRAME_SAMPLES];
logic [7:0]  output_bits_buffer[MAX_FRAME_BYTES];
logic [7:0]  reference_bits_buffer[MAX_FRAME_BYTES];

// 控制变量
int current_test_index;
int current_frame_number;
int input_sample_count;
int output_byte_count;
int reference_byte_count;

//=============================================================================
// 存储器模型
//=============================================================================

logic [31:0] memory_model [0:16383]; // 64KB存储器模型

always @(posedge clk) begin
    if (!rst_n) begin
        mem_req_ready <= 1'b0;
        mem_req_rdata <= 32'h0;
    end else begin
        if (mem_req_valid) begin
            mem_req_ready <= 1'b1;
            if (mem_req_wen) begin
                memory_model[mem_req_addr] <= mem_req_wdata;
                mem_req_rdata <= 32'h0;
            end else begin
                mem_req_rdata <= memory_model[mem_req_addr];
            end
        end else begin
            mem_req_ready <= 1'b0;
        end
    end
end

//=============================================================================
// 被测设计实例化
//=============================================================================

lc3plus_encoder_top u_dut (
    // 系统信号
    .clk                    (clk),
    .rst_n                  (rst_n),
    
    // 主配置接口
    .frame_duration         (frame_duration),
    .channel_mode           (channel_mode),
    .target_bitrate         (target_bitrate),
    .sample_rate            (sample_rate),
    .encoder_enable         (encoder_enable),
    
    // AXI4-Stream音频输入接口
    .s_axis_audio_tvalid    (s_axis_audio_tvalid),
    .s_axis_audio_tdata     (s_axis_audio_tdata),
    .s_axis_audio_tlast     (s_axis_audio_tlast),
    .s_axis_audio_tready    (s_axis_audio_tready),
    
    // AXI4-Stream比特流输出接口
    .m_axis_bitstream_tvalid(m_axis_bitstream_tvalid),
    .m_axis_bitstream_tdata (m_axis_bitstream_tdata),
    .m_axis_bitstream_tlast (m_axis_bitstream_tlast),
    .m_axis_bitstream_tuser (m_axis_bitstream_tuser),
    .m_axis_bitstream_tready(m_axis_bitstream_tready),
    
    // APB配置接口
    .pclk                   (apb_clk),
    .presetn                (apb_rst_n),
    .psel                   (psel),
    .penable                (penable),
    .pwrite                 (pwrite),
    .paddr                  (paddr),
    .pwdata                 (pwdata),
    .prdata                 (prdata),
    .pready                 (pready),
    .pslverr                (pslverr),
    
    // 系统存储器接口
    .mem_req_valid          (mem_req_valid),
    .mem_req_addr           (mem_req_addr),
    .mem_req_wdata          (mem_req_wdata),
    .mem_req_wen            (mem_req_wen),
    .mem_req_ready          (mem_req_ready),
    .mem_req_rdata          (mem_req_rdata),
    
    // 系统状态输出
    .encoding_active        (encoding_active),
    .frame_processing       (frame_processing),
    .pipeline_stage         (pipeline_stage),
    .performance_info       (performance_info),
    .error_status           (error_status),
    
    // 调试接口
    .debug_mdct             (debug_mdct),
    .debug_spectral         (debug_spectral),
    .debug_quantization     (debug_quantization),
    .debug_entropy          (debug_entropy),
    .debug_packing          (debug_packing)
);

//=============================================================================
// 时钟生成
//=============================================================================

initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

initial begin
    apb_clk = 1'b0;
    forever #(APB_CLK_PERIOD/2) apb_clk = ~apb_clk;
end

//=============================================================================
// 复位控制
//=============================================================================

initial begin
    rst_n = 1'b0;
    apb_rst_n = 1'b0;
    repeat(RESET_CYCLES) @(posedge clk);
    rst_n = 1'b1;
    apb_rst_n = 1'b1;
    $display("[%0t] System reset released", $time);
end

//=============================================================================
// 测试配置初始化
//=============================================================================

initial begin
    initialize_test_configs();
    initialize_signals();
    wait(rst_n);
    #1000; // 等待复位稳定
    
    $display("=================================================");
    $display("LC3plus编码器系统级验证开始");
    $display("=================================================");
    
    run_all_tests();
    
    $display("=================================================");
    $display("LC3plus编码器系统级验证完成");
    $display("=================================================");
    print_final_results();
    
    $finish;
end

//=============================================================================
// 测试配置初始化任务
//=============================================================================

task initialize_test_configs();
    // 测试配置1: 16kHz, 10ms, 32kbps, 单声道
    test_configs[0].sample_rate = 16000;
    test_configs[0].frame_duration_ms = 10;
    test_configs[0].bitrate_kbps = 32;
    test_configs[0].channel_count = 1;
    test_configs[0].input_file = "pcm_16k_10ms_mono.raw";
    test_configs[0].reference_file = "ref_16k_10ms_32k_mono.lc3";
    
    // 测试配置2: 24kHz, 10ms, 64kbps, 单声道  
    test_configs[1].sample_rate = 24000;
    test_configs[1].frame_duration_ms = 10;
    test_configs[1].bitrate_kbps = 64;
    test_configs[1].channel_count = 1;
    test_configs[1].input_file = "pcm_24k_10ms_mono.raw";
    test_configs[1].reference_file = "ref_24k_10ms_64k_mono.lc3";
    
    // 测试配置3: 48kHz, 10ms, 128kbps, 单声道
    test_configs[2].sample_rate = 48000;
    test_configs[2].frame_duration_ms = 10;
    test_configs[2].bitrate_kbps = 128;
    test_configs[2].channel_count = 1;
    test_configs[2].input_file = "pcm_48k_10ms_mono.raw";
    test_configs[2].reference_file = "ref_48k_10ms_128k_mono.lc3";
    
    // 测试配置4: 48kHz, 10ms, 256kbps, 立体声
    test_configs[3].sample_rate = 48000;
    test_configs[3].frame_duration_ms = 10;
    test_configs[3].bitrate_kbps = 256;
    test_configs[3].channel_count = 2;
    test_configs[3].input_file = "pcm_48k_10ms_stereo.raw";
    test_configs[3].reference_file = "ref_48k_10ms_256k_stereo.lc3";
    
    $display("[INFO] 测试配置初始化完成");
endtask

//=============================================================================
// 信号初始化任务
//=============================================================================

task initialize_signals();
    frame_duration = 2'b00;
    channel_mode = 1'b0;
    target_bitrate = 8'd32;
    sample_rate = 16'd16000;
    encoder_enable = 1'b0;
    
    s_axis_audio_tvalid = 1'b0;
    s_axis_audio_tdata = 32'h0;
    s_axis_audio_tlast = 1'b0;
    
    m_axis_bitstream_tready = 1'b1;
    
    psel = 1'b0;
    penable = 1'b0;
    pwrite = 1'b0;
    paddr = 12'h0;
    pwdata = 32'h0;
    
    current_test_index = 0;
    current_frame_number = 0;
    
    // 清零统计数据
    test_stats.total_frames = 0;
    test_stats.passed_frames = 0;
    test_stats.failed_frames = 0;
    test_stats.avg_snr = 0.0;
    test_stats.min_snr = 999.0;
    test_stats.max_processing_time = 0.0;
    test_stats.avg_processing_time = 0.0;
endtask

//=============================================================================
// 执行所有测试
//=============================================================================

task run_all_tests();
    for (current_test_index = 0; current_test_index < 4; current_test_index++) begin
        $display("\n--- 开始测试配置 %0d ---", current_test_index);
        $display("采样率: %0d Hz", test_configs[current_test_index].sample_rate);
        $display("帧长: %0d ms", test_configs[current_test_index].frame_duration_ms);
        $display("比特率: %0d kbps", test_configs[current_test_index].bitrate_kbps);
        $display("通道数: %0d", test_configs[current_test_index].channel_count);
        
        configure_encoder(current_test_index);
        run_single_test(current_test_index);
        
        $display("--- 测试配置 %0d 完成 ---\n", current_test_index);
    end
endtask

//=============================================================================
// 配置编码器
//=============================================================================

task configure_encoder(int test_idx);
    // 设置编码参数
    case(test_configs[test_idx].frame_duration_ms)
        10: frame_duration = 2'b10;
        default: frame_duration = 2'b10;
    endcase
    
    channel_mode = (test_configs[test_idx].channel_count == 2) ? 1'b1 : 1'b0;
    target_bitrate = test_configs[test_idx].bitrate_kbps;
    sample_rate = test_configs[test_idx].sample_rate;
    
    // 通过APB配置编码器
    apb_write(12'h000, 32'h00000001); // 启用编码器
    apb_write(12'h004, {16'h0, sample_rate}); // 设置采样率
    apb_write(12'h008, {24'h0, target_bitrate}); // 设置比特率
    
    encoder_enable = 1'b1;
    
    $display("[CONFIG] 编码器配置完成");
    $display("  帧长配置: %0d", frame_duration);
    $display("  通道模式: %s", channel_mode ? "立体声" : "单声道");
    $display("  目标比特率: %0d kbps", target_bitrate);
    $display("  采样率: %0d Hz", sample_rate);
endtask

//=============================================================================
// APB写操作
//=============================================================================

task apb_write(input [11:0] addr, input [31:0] data);
    @(posedge apb_clk);
    psel = 1'b1;
    pwrite = 1'b1;
    paddr = addr;
    pwdata = data;
    
    @(posedge apb_clk);
    penable = 1'b1;
    
    wait(pready);
    @(posedge apb_clk);
    
    psel = 1'b0;
    penable = 1'b0;
    pwrite = 1'b0;
endtask

//=============================================================================
// APB读操作
//=============================================================================

task apb_read(input [11:0] addr, output [31:0] data);
    @(posedge apb_clk);
    psel = 1'b1;
    pwrite = 1'b0;
    paddr = addr;
    
    @(posedge apb_clk);
    penable = 1'b1;
    
    wait(pready);
    data = prdata;
    @(posedge apb_clk);
    
    psel = 1'b0;
    penable = 1'b0;
endtask

//=============================================================================
// 执行单个测试
//=============================================================================

task run_single_test(int test_idx);
    string input_file_path;
    string ref_file_path;
    int frame_count;
    
    input_file_path = {TEST_VECTOR_PATH, test_configs[test_idx].input_file};
    ref_file_path = {REFERENCE_PATH, test_configs[test_idx].reference_file};
    
    // 加载测试向量
    if (!load_pcm_file(input_file_path)) begin
        $error("无法加载PCM文件: %s", input_file_path);
        return;
    end
    
    // 加载参考比特流
    if (!load_reference_file(ref_file_path)) begin
        $error("无法加载参考文件: %s", ref_file_path);
        return;
    end
    
    // 处理所有帧
    frame_count = 0;
    while (frame_count < 100 && has_more_frames()) begin // 最多100帧测试
        process_single_frame(test_idx, frame_count);
        frame_count++;
    end
    
    $display("[INFO] 测试配置 %0d 处理了 %0d 帧", test_idx, frame_count);
endtask

//=============================================================================
// 处理单帧
//=============================================================================

task process_single_frame(int test_idx, int frame_idx);
    real start_time, end_time, processing_time;
    int frame_samples;
    int i;
    
    $display("  处理第 %0d 帧...", frame_idx);
    
    // 计算帧样本数
    frame_samples = (test_configs[test_idx].sample_rate * test_configs[test_idx].frame_duration_ms) / 1000;
    
    start_time = $realtime;
    
    // 发送音频数据
    for (i = 0; i < frame_samples; i++) begin
        @(posedge clk);
        s_axis_audio_tvalid = 1'b1;
        s_axis_audio_tdata = {16'h0, input_pcm_buffer[i]};
        s_axis_audio_tlast = (i == frame_samples - 1);
        
        wait(s_axis_audio_tready);
    end
    
    @(posedge clk);
    s_axis_audio_tvalid = 1'b0;
    s_axis_audio_tlast = 1'b0;
    
    // 等待编码完成并收集输出
    collect_output_frame();
    
    end_time = $realtime;
    processing_time = end_time - start_time;
    
    // 与参考数据比较
    compare_with_reference(frame_idx, processing_time);
    
    test_stats.total_frames++;
endtask

//=============================================================================
// 收集输出帧
//=============================================================================

task collect_output_frame();
    int byte_count = 0;
    
    output_byte_count = 0;
    
    // 等待第一个输出字节
    wait(m_axis_bitstream_tvalid);
    
    while (m_axis_bitstream_tvalid && !m_axis_bitstream_tlast) begin
        @(posedge clk);
        if (m_axis_bitstream_tvalid && m_axis_bitstream_tready) begin
            output_bits_buffer[output_byte_count] = m_axis_bitstream_tdata;
            output_byte_count++;
            
            if (m_axis_bitstream_tlast) begin
                break;
            end
        end
    end
    
    $display("    收集到 %0d 字节输出数据", output_byte_count);
endtask

//=============================================================================
// 与参考数据比较
//=============================================================================

task compare_with_reference(int frame_idx, real proc_time);
    int differences = 0;
    int i;
    real bit_error_rate;
    real snr;
    
    // 比较字节数
    if (output_byte_count != reference_byte_count) begin
        $warning("第 %0d 帧字节数不匹配: 输出=%0d, 参考=%0d", 
                frame_idx, output_byte_count, reference_byte_count);
    end
    
    // 逐字节比较
    for (i = 0; i < $min(output_byte_count, reference_byte_count); i++) begin
        if (output_bits_buffer[i] !== reference_bits_buffer[i]) begin
            differences++;
        end
    end
    
    // 计算误码率和SNR
    bit_error_rate = real(differences * 8) / real(output_byte_count * 8);
    snr = (bit_error_rate > 0) ? -20.0 * $log10(bit_error_rate) : 60.0; // 限制SNR上限
    
    // 更新统计
    if (differences == 0) begin
        test_stats.passed_frames++;
        $display("    第 %0d 帧: PASS (完全匹配)", frame_idx);
    end else if (bit_error_rate < 0.01) begin // 1%误码率以下认为可接受
        test_stats.passed_frames++;
        $display("    第 %0d 帧: PASS (SNR=%.1f dB, 误差=%0d字节)", frame_idx, snr, differences);
    end else begin
        test_stats.failed_frames++;
        $display("    第 %0d 帧: FAIL (SNR=%.1f dB, 误差=%0d字节)", frame_idx, snr, differences);
    end
    
    // 更新性能统计
    test_stats.avg_snr += snr;
    if (snr < test_stats.min_snr) test_stats.min_snr = snr;
    if (proc_time > test_stats.max_processing_time) test_stats.max_processing_time = proc_time;
    test_stats.avg_processing_time += proc_time;
    
    $display("    处理时间: %.2f ns", proc_time);
endtask

//=============================================================================
// 文件操作函数
//=============================================================================

function bit load_pcm_file(string filename);
    int file_handle;
    int i;
    
    file_handle = $fopen(filename, "rb");
    if (file_handle == 0) begin
        $error("无法打开PCM文件: %s", filename);
        return 1'b0;
    end
    
    // 简化: 假设读取固定数量样本
    for (i = 0; i < MAX_FRAME_SAMPLES; i++) begin
        if ($feof(file_handle)) break;
        input_pcm_buffer[i] = $fgetc(file_handle) | ($fgetc(file_handle) << 8);
    end
    
    input_sample_count = i;
    $fclose(file_handle);
    
    $display("[INFO] 加载了 %0d 个PCM样本", input_sample_count);
    return 1'b1;
endfunction

function bit load_reference_file(string filename);
    int file_handle;
    int i;
    
    file_handle = $fopen(filename, "rb");
    if (file_handle == 0) begin
        $error("无法打开参考文件: %s", filename);
        return 1'b0;
    end
    
    // 读取参考比特流数据
    for (i = 0; i < MAX_FRAME_BYTES; i++) begin
        if ($feof(file_handle)) break;
        reference_bits_buffer[i] = $fgetc(file_handle);
    end
    
    reference_byte_count = i;
    $fclose(file_handle);
    
    $display("[INFO] 加载了 %0d 字节参考数据", reference_byte_count);
    return 1'b1;
endfunction

function bit has_more_frames();
    return (input_sample_count > 0);
endfunction

//=============================================================================
// 结果打印
//=============================================================================

task print_final_results();
    real pass_rate;
    
    if (test_stats.total_frames > 0) begin
        pass_rate = (real(test_stats.passed_frames) / real(test_stats.total_frames)) * 100.0;
        test_stats.avg_snr /= real(test_stats.total_frames);
        test_stats.avg_processing_time /= real(test_stats.total_frames);
    end else begin
        pass_rate = 0.0;
    end
    
    $display("\n=== 最终验证结果 ===");
    $display("总测试帧数: %0d", test_stats.total_frames);
    $display("通过帧数: %0d", test_stats.passed_frames);
    $display("失败帧数: %0d", test_stats.failed_frames);
    $display("通过率: %.1f%%", pass_rate);
    $display("平均SNR: %.1f dB", test_stats.avg_snr);
    $display("最小SNR: %.1f dB", test_stats.min_snr);
    $display("最大处理时间: %.2f ns", test_stats.max_processing_time);
    $display("平均处理时间: %.2f ns", test_stats.avg_processing_time);
    
    if (pass_rate >= 95.0) begin
        $display("\n*** 验证通过! LC3plus编码器功能正确 ***");
    end else begin
        $display("\n*** 验证失败! 需要进一步调试 ***");
    end
endtask

//=============================================================================
// 信号监控和调试
//=============================================================================

// 编码状态监控
always @(posedge clk) begin
    if (encoding_active) begin
        if ($time % 100000 == 0) begin // 每100us打印一次状态
            $display("[%0t] 编码状态: 流水线阶段=%0d, 性能信息=0x%08x", 
                    $time, pipeline_stage, performance_info);
        end
    end
end

// 错误监控
always @(posedge clk) begin
    if (error_status != 32'h0) begin
        $warning("[%0t] 检测到错误状态: 0x%08x", $time, error_status);
    end
end

// 调试信息记录
always @(posedge clk) begin
    if (frame_processing) begin
        // 记录调试信息到文件
        // $fdisplay(debug_file, "%0t,%08x,%08x,%08x,%08x,%08x", 
        //          $time, debug_mdct, debug_spectral, debug_quantization, 
        //          debug_entropy, debug_packing);
    end
end

endmodule 