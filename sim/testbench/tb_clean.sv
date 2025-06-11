`timescale 1ns/1ps

module tb_clean;

parameter CLK_PERIOD = 5.0;
parameter FRAME_SAMPLES = 160;
parameter TEST_FRAMES = 10;

// 系统时钟和复位
reg clk;
reg rst_n;

// LC3plus编码器接口
reg [1:0] frame_duration;
reg channel_mode;
reg [7:0] target_bitrate;
reg [15:0] sample_rate;
reg encoder_enable;

// AXI4-Stream音频输入
reg s_axis_audio_tvalid;
reg [31:0] s_axis_audio_tdata;
reg s_axis_audio_tlast;
wire s_axis_audio_tready;

// AXI4-Stream比特流输出
wire m_axis_bitstream_tvalid;
wire [7:0] m_axis_bitstream_tdata;
wire m_axis_bitstream_tlast;
wire [15:0] m_axis_bitstream_tuser;
reg m_axis_bitstream_tready;

// APB配置接口  
reg psel;
reg penable;
reg pwrite;
reg [11:0] paddr;
reg [31:0] pwdata;
wire [31:0] prdata;
wire pready;
wire pslverr;

// 系统存储器接口
wire mem_req_valid;
wire [15:0] mem_req_addr;
wire [31:0] mem_req_wdata;
wire mem_req_wen;
reg mem_req_ready;
reg [31:0] mem_req_rdata;

// 状态信号
wire encoding_active;
wire frame_processing;
wire [2:0] pipeline_stage;
wire [31:0] performance_info;
wire [31:0] error_status;
wire [31:0] debug_mdct;
wire [31:0] debug_spectral;
wire [31:0] debug_quantization;
wire [31:0] debug_entropy;
wire [31:0] debug_packing;

// 测试数据
reg [15:0] test_audio [0:FRAME_SAMPLES*TEST_FRAMES-1];
reg [7:0] output_data [0:4095];
integer audio_index;
integer output_index;
integer frame_count;

// 存储器模型
reg [31:0] memory [0:16383];

// 时钟生成
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// 复位控制
initial begin
    rst_n = 0;
    #50;
    rst_n = 1;
    $display("Reset released");
end

// 存储器模型
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

// 被测设计实例化
lc3plus_encoder_top u_dut (
    .clk(clk),
    .rst_n(rst_n),
    .frame_duration(frame_duration),
    .channel_mode(channel_mode),
    .target_bitrate(target_bitrate),
    .sample_rate(sample_rate),
    .encoder_enable(encoder_enable),
    
    .s_axis_audio_tvalid(s_axis_audio_tvalid),
    .s_axis_audio_tdata(s_axis_audio_tdata),
    .s_axis_audio_tlast(s_axis_audio_tlast),
    .s_axis_audio_tready(s_axis_audio_tready),
    
    .m_axis_bitstream_tvalid(m_axis_bitstream_tvalid),
    .m_axis_bitstream_tdata(m_axis_bitstream_tdata),
    .m_axis_bitstream_tlast(m_axis_bitstream_tlast),
    .m_axis_bitstream_tuser(m_axis_bitstream_tuser),
    .m_axis_bitstream_tready(m_axis_bitstream_tready),
    
    .pclk(clk),
    .presetn(rst_n),
    .psel(psel),
    .penable(penable),
    .pwrite(pwrite),
    .paddr(paddr),
    .pwdata(pwdata),
    .prdata(prdata),
    .pready(pready),
    .pslverr(pslverr),
    
    .mem_req_valid(mem_req_valid),
    .mem_req_addr(mem_req_addr),
    .mem_req_wdata(mem_req_wdata),
    .mem_req_wen(mem_req_wen),
    .mem_req_ready(mem_req_ready),
    .mem_req_rdata(mem_req_rdata),
    
    .encoding_active(encoding_active),
    .frame_processing(frame_processing),
    .pipeline_stage(pipeline_stage),
    .performance_info(performance_info),
    .error_status(error_status),
    .debug_mdct(debug_mdct),
    .debug_spectral(debug_spectral),
    .debug_quantization(debug_quantization),
    .debug_entropy(debug_entropy),
    .debug_packing(debug_packing)
);

// 生成测试音频
task generate_test_audio;
    integer i;
    real freq, phase, amplitude;
    begin
        $display("Generating test audio...");
        freq = 1000.0;
        amplitude = 16384.0;
        
        for (i = 0; i < FRAME_SAMPLES * TEST_FRAMES; i = i + 1) begin
            phase = 2.0 * 3.14159 * freq * i / 16000.0;
            test_audio[i] = $rtoi(amplitude * $sin(phase));
        end
        
        $display("Generated %d audio samples", FRAME_SAMPLES * TEST_FRAMES);
    end
endtask

// 配置编码器
task configure_encoder;
    begin
        $display("Configuring encoder...");
        
        frame_duration = 2'b10;
        channel_mode = 1'b0;
        target_bitrate = 8'd32;
        sample_rate = 16'd16000;
        encoder_enable = 1'b1;
        
        $display("Encoder configured");
    end
endtask

// 主测试
initial begin
    // 初始化
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
    
    // 等待复位
    wait(rst_n);
    #1000;
    
    $display("=== LC3plus Encoder Test Start ===");
    
    // 生成测试音频
    generate_test_audio;
    
    // 配置编码器
    configure_encoder;
    
    // 简单测试
    $display("Starting data transfer test...");
    
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
    
    $display("Audio data sent");
    
    // 等待处理
    #10000;
    
    $display("=== LC3plus Encoder Test Complete ===");
    
    $finish;
end

// 监控
always @(posedge clk) begin
    if (encoding_active && ($time % 100000 == 0)) begin
        $display("[%0t] Encoding status: stage=%0d, perf=0x%08x", 
                $time, pipeline_stage, performance_info);
    end
end

always @(posedge clk) begin
    if (error_status != 32'h0) begin
        $display("[%0t] Error status: 0x%08x", $time, error_status);
    end
end

initial begin
    if ($test$plusargs("dump")) begin
        $dumpfile("tb_clean.vcd");
        $dumpvars(0, tb_clean);
    end
end

endmodule 