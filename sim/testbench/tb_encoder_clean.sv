//=============================================================================
// LC3plus编码器简化验证测试平台 (清洁版本)
// 
// 功能：提供基本的LC3plus编码器验证
// 作者：Audio Codec Design Team
// 版本：v1.1
// 日期：2024-06-11
//=============================================================================

`timescale 1ns/1ps

module tb_encoder_clean;

//=============================================================================
// 参数定义
//=============================================================================

parameter CLK_PERIOD = 5.0;        // 200MHz系统时钟
parameter APB_CLK_PERIOD = 10.0;   // 100MHz APB时钟
parameter FRAME_SAMPLES = 160;     // 16kHz@10ms帧样本数
parameter TEST_FRAMES = 10;        // 测试帧数

//=============================================================================
// 信号声明
//=============================================================================

// 系统时钟和复位
reg                     clk;
reg                     rst_n;
reg                     apb_clk;
reg                     apb_rst_n;

// LC3plus编码器接口
reg     [1:0]           frame_duration;
reg                     channel_mode;
reg     [7:0]           target_bitrate;
reg     [15:0]          sample_rate;
reg                     encoder_enable;

// AXI4-Stream音频输入
reg                     s_axis_audio_tvalid;
reg     [31:0]          s_axis_audio_tdata;
reg                     s_axis_audio_tlast;
wire                    s_axis_audio_tready;

// AXI4-Stream比特流输出
wire                    m_axis_bitstream_tvalid;
wire    [7:0]           m_axis_bitstream_tdata;
wire                    m_axis_bitstream_tlast;
wire    [15:0]          m_axis_bitstream_tuser;
reg                     m_axis_bitstream_tready;

// APB配置接口
reg                     psel;
reg                     penable;
reg                     pwrite;
reg     [11:0]          paddr;
reg     [31:0]          pwdata;
wire    [31:0]          prdata;
wire                    pready;
wire                    pslverr;

// 系统存储器接口
wire                    mem_req_valid;
wire    [15:0]          mem_req_addr;
wire    [31:0]          mem_req_wdata;
wire                    mem_req_wen;
reg                     mem_req_ready;
reg     [31:0]          mem_req_rdata;

// 状态和调试信号
wire                    encoding_active;
wire                    frame_processing;
wire    [2:0]           pipeline_stage;
wire    [31:0]          performance_info;
wire    [31:0]          error_status;
wire    [31:0]          debug_mdct;
wire    [31:0]          debug_spectral;
wire    [31:0]          debug_quantization;
wire    [31:0]          debug_entropy;
wire    [31:0]          debug_packing;

//=============================================================================
// 测试数据
//=============================================================================

// 测试音频数据 - 简单的正弦波
reg     [15:0]          test_audio [0:FRAME_SAMPLES*TEST_FRAMES-1];
reg     [7:0]           output_data [0:4095];
integer                 audio_index;
integer                 output_index;
integer                 frame_count;

// 存储器模型
reg     [31:0]          memory [0:16383];

//=============================================================================
// 时钟生成
//=============================================================================

initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

initial begin
    apb_clk = 0;
    forever #(APB_CLK_PERIOD/2) apb_clk = ~apb_clk;
end

//=============================================================================
// 复位控制
//=============================================================================

initial begin
    rst_n = 0;
    apb_rst_n = 0;
    #(CLK_PERIOD * 10);
    rst_n = 1;
    apb_rst_n = 1;
    $display("[%0t] Reset released", $time);
end

//=============================================================================
// 存储器模型
//=============================================================================

always @(posedge clk) begin
    if (!rst_n) begin
        mem_req_ready <= 1'b0;
        mem_req_rdata <= 32'h0;
    end else begin
        mem_req_ready <= mem_req_valid;
        if (mem_req_valid) begin
            if (mem_req_wen) begin
                memory[mem_req_addr[13:0]] <= mem_req_wdata;
                mem_req_rdata <= 32'h0;
            end else begin
                mem_req_rdata <= memory[mem_req_addr[13:0]];
            end
        end
    end
end

//=============================================================================
// 被测设计实例化
//=============================================================================

lc3plus_encoder_top u_dut (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .frame_duration             (frame_duration),
    .channel_mode               (channel_mode),
    .target_bitrate             (target_bitrate),
    .sample_rate                (sample_rate),
    .encoder_enable             (encoder_enable),
    
    .s_axis_audio_tvalid        (s_axis_audio_tvalid),
    .s_axis_audio_tdata         (s_axis_audio_tdata),
    .s_axis_audio_tlast         (s_axis_audio_tlast),
    .s_axis_audio_tready        (s_axis_audio_tready),
    
    .m_axis_bitstream_tvalid    (m_axis_bitstream_tvalid),
    .m_axis_bitstream_tdata     (m_axis_bitstream_tdata),
    .m_axis_bitstream_tlast     (m_axis_bitstream_tlast),
    .m_axis_bitstream_tuser     (m_axis_bitstream_tuser),
    .m_axis_bitstream_tready    (m_axis_bitstream_tready),
    
    .pclk                       (apb_clk),
    .presetn                    (apb_rst_n),
    .psel                       (psel),
    .penable                    (penable),
    .pwrite                     (pwrite),
    .paddr                      (paddr),
    .pwdata                     (pwdata),
    .prdata                     (prdata),
    .pready                     (pready),
    .pslverr                    (pslverr),
    
    .mem_req_valid              (mem_req_valid),
    .mem_req_addr               (mem_req_addr),
    .mem_req_wdata              (mem_req_wdata),
    .mem_req_wen                (mem_req_wen),
    .mem_req_ready              (mem_req_ready),
    .mem_req_rdata              (mem_req_rdata),
    
    .encoding_active            (encoding_active),
    .frame_processing           (frame_processing),
    .pipeline_stage             (pipeline_stage),
    .performance_info           (performance_info),
    .error_status               (error_status),
    .debug_mdct                 (debug_mdct),
    .debug_spectral             (debug_spectral),
    .debug_quantization         (debug_quantization),
    .debug_entropy              (debug_entropy),
    .debug_packing              (debug_packing)
);

//=============================================================================
// 测试向量生成
//=============================================================================

task generate_test_audio;
    integer i;
    real freq, phase, amplitude;
    begin
        $display("[INFO] 生成测试音频数据...");
        freq = 1000.0;  // 1kHz正弦波
        amplitude = 16384.0;  // 50%满刻度
        
        for (i = 0; i < FRAME_SAMPLES * TEST_FRAMES; i = i + 1) begin
            phase = 2.0 * 3.14159 * freq * i / 16000.0;
            test_audio[i] = $rtoi(amplitude * $sin(phase));
        end
        
        $display("[INFO] 生成了 %d 个音频样本", FRAME_SAMPLES * TEST_FRAMES);
    end
endtask

//=============================================================================
// APB操作任务
//=============================================================================

task apb_write(input [11:0] addr, input [31:0] data);
    begin
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
    end
endtask

task apb_read(input [11:0] addr, output [31:0] data);
    begin
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
    end
endtask

//=============================================================================
// 编码器配置任务
//=============================================================================

task configure_encoder;
    begin
        $display("[CONFIG] 配置LC3plus编码器...");
        
        // 设置编码参数
        frame_duration = 2'b10;    // 10ms帧
        channel_mode = 1'b0;       // 单声道
        target_bitrate = 8'd32;    // 32kbps
        sample_rate = 16'd16000;   // 16kHz
        
        // 通过APB配置
        apb_write(12'h000, 32'h00000001);      // 使能编码器
        apb_write(12'h004, {16'h0, sample_rate}); // 采样率
        apb_write(12'h008, {24'h0, target_bitrate}); // 比特率
        
        encoder_enable = 1'b1;
        
        $display("[CONFIG] 编码器配置完成");
        $display("  采样率: %d Hz", sample_rate);
        $display("  比特率: %d kbps", target_bitrate);
        $display("  帧长: 10ms");
        $display("  通道: 单声道");
    end
endtask

//=============================================================================
// 主测试流程
//=============================================================================

initial begin
    // 初始化信号
    frame_duration = 2'b10;
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
    
    audio_index = 0;
    output_index = 0;
    frame_count = 0;
    
    // 等待复位释放
    wait(rst_n);
    #1000;
    
    $display("=================================================");
    $display("LC3plus编码器基本验证测试开始");
    $display("=================================================");
    
    // 生成测试音频
    generate_test_audio;
    
    // 配置编码器
    configure_encoder;
    
    // 简单的数据传输测试
    $display("[TEST] 开始数据传输测试...");
    
    // 发送一帧测试数据
    for (audio_index = 0; audio_index < FRAME_SAMPLES; audio_index = audio_index + 1) begin
        @(posedge clk);
        s_axis_audio_tvalid = 1'b1;
        s_axis_audio_tdata = {16'h0, test_audio[audio_index]};
        s_axis_audio_tlast = (audio_index == FRAME_SAMPLES - 1);
        
        wait(s_axis_audio_tready);
    end
    
    @(posedge clk);
    s_axis_audio_tvalid = 1'b0;
    s_axis_audio_tlast = 1'b0;
    
    $display("[TEST] 音频数据发送完成");
    
    // 等待处理完成
    #10000;
    
    $display("=================================================");
    $display("LC3plus编码器基本验证测试完成");
    $display("=================================================");
    
    $finish;
end

//=============================================================================
// 状态监控
//=============================================================================

always @(posedge clk) begin
    if (encoding_active && ($time % 100000 == 0)) begin
        $display("[%0t] 编码状态: 阶段=%0d, 性能=0x%08x", 
                $time, pipeline_stage, performance_info);
    end
end

// 错误监控
always @(posedge clk) begin
    if (error_status != 32'h0) begin
        $display("[%0t] 错误状态: 0x%08x", $time, error_status);
    end
end

// 波形转储
initial begin
    if ($test$plusargs("dump")) begin
        $dumpfile("tb_encoder_clean.vcd");
        $dumpvars(0, tb_encoder_clean);
    end
end

endmodule 