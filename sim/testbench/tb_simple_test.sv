`timescale 1ns/1ps

//=============================================================================
// LC3plus编码器简化测试平台
// 
// 功能：快速验证2.5ms帧长，10ms编码数据
// 配置：AHB-Lite接口，APB配置，详细日志
// 作者：Audio Codec Design Team
// 版本：v1.0
//=============================================================================

module tb_simple_test;

//=============================================================================
// 参数定义
//=============================================================================

// 时钟和时序参数
parameter CLK_PERIOD = 10;          // 100MHz时钟 (10ns周期)
parameter APB_CLK_PERIOD = 20;      // 50MHz APB时钟 (20ns周期)

// 音频参数
parameter SAMPLE_RATE = 48000;      // 48kHz采样率
parameter FRAME_LENGTH_MS = 2.5;    // 2.5ms帧长
parameter TEST_DURATION_MS = 10;    // 10ms测试时长
parameter SAMPLES_PER_FRAME = 120;  // 48kHz * 2.5ms = 120样本
parameter TOTAL_FRAMES = 4;         // 10ms / 2.5ms = 4帧
parameter TOTAL_SAMPLES = 480;      // 120 * 4 = 480样本

// 编码配置
parameter TARGET_BITRATE = 64;      // 64kbps目标码率
parameter CHANNEL_MODE = 0;         // 单声道模式

//=============================================================================
// 信号声明
//=============================================================================

// 系统时钟和复位
reg                clk;
reg                rst_n;
reg                pclk;
reg                presetn;

// DUT端口信号
reg  [1:0]         frame_duration;
reg                channel_mode;
reg  [7:0]         target_bitrate;
reg  [15:0]        sample_rate;
reg                encoder_enable;

// AXI4-Stream音频输入
reg                s_axis_audio_tvalid;
reg  [31:0]        s_axis_audio_tdata;
reg                s_axis_audio_tlast;
wire               s_axis_audio_tready;

// AXI4-Stream比特流输出
wire               m_axis_bitstream_tvalid;
wire [7:0]         m_axis_bitstream_tdata;
wire               m_axis_bitstream_tlast;
wire [15:0]        m_axis_bitstream_tuser;
reg                m_axis_bitstream_tready;

// APB配置接口
reg                psel;
reg                penable;
reg                pwrite;
reg  [11:0]        paddr;
reg  [31:0]        pwdata;
wire [31:0]        prdata;
wire               pready;
wire               pslverr;

// 系统存储器接口（简化）
wire               mem_req_valid;
wire [15:0]        mem_req_addr;
wire [31:0]        mem_req_wdata;
wire               mem_req_wen;
reg                mem_req_ready;
reg  [31:0]        mem_req_rdata;

// 系统状态
wire               encoding_active;
wire               frame_processing;
wire [2:0]         pipeline_stage;
wire [31:0]        performance_info;
wire [31:0]        error_status;

// 调试信号
wire [31:0]        debug_mdct;
wire [31:0]        debug_spectral;
wire [31:0]        debug_quantization;
wire [31:0]        debug_entropy;
wire [31:0]        debug_packing;

//=============================================================================
// 测试控制变量
//=============================================================================

integer            sample_count;
integer            frame_count;
integer            cycle_count;
integer            bitstream_bytes;
reg  [15:0]        test_audio [0:TOTAL_SAMPLES-1];
reg                test_running;
reg                apb_config_done;

//=============================================================================
// DUT实例化
//=============================================================================

lc3plus_encoder_top #(
    .BUS_TYPE("AHB3"),
    .MAX_SAMPLE_RATE(48000),
    .MAX_CHANNELS(1),
    .BUFFER_DEPTH(256),
    .PRECISION_MODE("HIGH"),
    .POWER_OPT("BALANCED"),
    .PIPELINE_STAGES(6),
    .MEMORY_TYPE("SINGLE"),
    .DEBUG_ENABLE(1)
) u_dut (
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
    
    .pclk(pclk),
    .presetn(presetn),
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

//=============================================================================
// 时钟生成
//=============================================================================

initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

initial begin
    pclk = 0;
    forever #(APB_CLK_PERIOD/2) pclk = ~pclk;
end

//=============================================================================
// 复位序列
//=============================================================================

initial begin
    rst_n = 0;
    presetn = 0;
    #(CLK_PERIOD * 10);
    rst_n = 1;
    presetn = 1;
    $display("[%t] 系统复位释放", $time);
end

//=============================================================================
// 存储器模拟
//=============================================================================

// 简化的存储器响应
always @(posedge clk) begin
    if (!rst_n) begin
        mem_req_ready <= 1'b0;
        mem_req_rdata <= 32'h0;
    end else begin
        mem_req_ready <= mem_req_valid; // 简单的立即响应
        if (mem_req_valid && !mem_req_wen) begin
            // 读操作 - 返回简单的测试数据
            mem_req_rdata <= {16'h1234, mem_req_addr};
        end else begin
            mem_req_rdata <= 32'h0;
        end
    end
end

//=============================================================================
// 测试音频数据生成
//=============================================================================

initial begin
    integer i;
    real phase, amplitude;
    
    $display("[%t] 生成测试音频数据...", $time);
    
    // 生成1kHz正弦波测试音频
    for (i = 0; i < TOTAL_SAMPLES; i = i + 1) begin
        phase = 2.0 * 3.14159 * 1000.0 * i / SAMPLE_RATE;
        amplitude = 16383.0 * $sin(phase); // 16位有符号数的幅度
        test_audio[i] = amplitude;
    end
    
    $display("[%t] 测试音频数据生成完成: %d样本", $time, TOTAL_SAMPLES);
end

//=============================================================================
// APB配置任务
//=============================================================================

task apb_write(input [11:0] addr, input [31:0] data);
begin
    @(posedge pclk);
    psel = 1'b1;
    pwrite = 1'b1;
    paddr = addr;
    pwdata = data;
    
    @(posedge pclk);
    penable = 1'b1;
    
    wait(pready);
    @(posedge pclk);
    psel = 1'b0;
    penable = 1'b0;
    pwrite = 1'b0;
    
    $display("[%t] APB写: 地址=0x%03x, 数据=0x%08x", $time, addr, data);
end
endtask

task apb_read(input [11:0] addr, output [31:0] data);
begin
    @(posedge pclk);
    psel = 1'b1;
    pwrite = 1'b0;
    paddr = addr;
    
    @(posedge pclk);
    penable = 1'b1;
    
    wait(pready);
    data = prdata;
    @(posedge pclk);
    psel = 1'b0;
    penable = 1'b0;
    
    $display("[%t] APB读: 地址=0x%03x, 数据=0x%08x", $time, addr, data);
end
endtask

//=============================================================================
// APB配置序列
//=============================================================================

initial begin
    reg [31:0] read_data;
    
    // 初始化APB信号
    psel = 1'b0;
    penable = 1'b0;
    pwrite = 1'b0;
    paddr = 12'h000;
    pwdata = 32'h0;
    apb_config_done = 1'b0;
    
    // 等待复位释放
    wait(presetn);
    #(APB_CLK_PERIOD * 5);
    
    $display("[%t] ========== 开始APB配置 ==========", $time);
    
    // 读取版本信息
    apb_read(12'h01C, read_data);
    $display("[%t] 版本信息: 0x%08x", $time, read_data);
    
    // 配置控制寄存器 - 使能编码器
    apb_write(12'h000, 32'h0000_0001);
    
    // 配置参数寄存器
    // [31:16] 采样率: 48000 = 0xBB80
    // [15:8]  码率: 64 = 0x40
    // [7:4]   帧长: 2.5ms = 0x0 (00: 2.5ms, 01: 5ms, 10: 10ms)
    // [3:0]   通道: 单声道 = 0x0
    apb_write(12'h004, 32'hBB80_4000);
    
    // 读回配置确认
    apb_read(12'h000, read_data);
    $display("[%t] 控制寄存器确认: 0x%08x", $time, read_data);
    
    apb_read(12'h004, read_data);
    $display("[%t] 配置寄存器确认: 0x%08x", $time, read_data);
    
    apb_config_done = 1'b1;
    $display("[%t] ========== APB配置完成 ==========", $time);
end

//=============================================================================
// 主测试序列
//=============================================================================

initial begin
    // 初始化测试信号
    frame_duration = 2'b00;      // 2.5ms
    channel_mode = 1'b0;         // 单声道
    target_bitrate = 8'd64;      // 64kbps
    sample_rate = 16'd48000;     // 48kHz
    encoder_enable = 1'b0;
    
    s_axis_audio_tvalid = 1'b0;
    s_axis_audio_tdata = 32'h0;
    s_axis_audio_tlast = 1'b0;
    m_axis_bitstream_tready = 1'b1;
    
    sample_count = 0;
    frame_count = 0;
    cycle_count = 0;
    bitstream_bytes = 0;
    test_running = 1'b0;
    
    // 等待APB配置完成
    wait(apb_config_done);
    #(CLK_PERIOD * 10);
    
    $display("[%t] ========== 开始音频编码测试 ==========", $time);
    
    // 使能编码器
    encoder_enable = 1'b1;
    test_running = 1'b1;
    
    // 发送音频数据
    fork
        send_audio_data();
        receive_bitstream();
        monitor_status();
    join_any
    
    // 测试完成
    #(CLK_PERIOD * 1000);
    
    $display("[%t] ========== 测试完成 ==========", $time);
    $display("总样本数: %d", sample_count);
    $display("总帧数: %d", frame_count);
    $display("输出字节数: %d", bitstream_bytes);
    $display("总周期数: %d", cycle_count);
    
    $finish;
end

//=============================================================================
// 音频数据发送任务
//=============================================================================

task send_audio_data();
begin
    integer i, samples_in_frame;
    
    for (i = 0; i < TOTAL_SAMPLES; i = i + 1) begin
        // 等待ready信号
        wait(s_axis_audio_tready);
        
        @(posedge clk);
        s_axis_audio_tvalid = 1'b1;
        s_axis_audio_tdata = {16'h0, test_audio[i]};
        
        // 计算是否为帧末尾
        samples_in_frame = (i % SAMPLES_PER_FRAME);
        if (samples_in_frame == (SAMPLES_PER_FRAME - 1)) begin
            s_axis_audio_tlast = 1'b1;
            frame_count = frame_count + 1;
            $display("[%t] 帧 %d 发送完成 (样本 %d)", $time, frame_count, i+1);
        end else begin
            s_axis_audio_tlast = 1'b0;
        end
        
        @(posedge clk);
        s_axis_audio_tvalid = 1'b0;
        s_axis_audio_tlast = 1'b0;
        
        sample_count = sample_count + 1;
        
        // 每10个样本打印一次进度
        if ((i % 10) == 0) begin
            $display("[%t] 发送样本 %d: 0x%04x", $time, i, test_audio[i]);
        end
    end
    
    $display("[%t] 所有音频数据发送完成", $time);
end
endtask

//=============================================================================
// 比特流接收任务
//=============================================================================

task receive_bitstream();
begin
    integer byte_count;
    byte_count = 0;
    
    while (test_running) begin
        @(posedge clk);
        if (m_axis_bitstream_tvalid && m_axis_bitstream_tready) begin
            byte_count = byte_count + 1;
            bitstream_bytes = bitstream_bytes + 1;
            
            $display("[%t] 接收比特流字节 %d: 0x%02x %s", 
                     $time, byte_count, m_axis_bitstream_tdata,
                     m_axis_bitstream_tlast ? "(帧结束)" : "");
            
            if (m_axis_bitstream_tlast) begin
                $display("[%t] 比特流帧完成，帧大小: %d字节", $time, m_axis_bitstream_tuser);
                byte_count = 0;
            end
        end
    end
end
endtask

//=============================================================================
// 状态监控任务
//=============================================================================

task monitor_status();
begin
    while (test_running) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
        
        // 每1000个周期打印一次状态
        if ((cycle_count % 1000) == 0) begin
            $display("[%t] 状态监控:", $time);
            $display("  编码活跃: %b", encoding_active);
            $display("  帧处理中: %b", frame_processing);
            $display("  流水线阶段: %d", pipeline_stage);
            $display("  性能信息: 0x%08x", performance_info);
            $display("  错误状态: 0x%08x", error_status);
            
            if (error_status != 32'h0) begin
                $display("[%t] 警告: 检测到错误状态!", $time);
            end
        end
    end
end
endtask

//=============================================================================
// 仿真控制
//=============================================================================

initial begin
    // 最大仿真时间限制
    #(CLK_PERIOD * 100000);
    $display("[%t] 仿真时间超时，强制结束", $time);
    $finish;
end

// 波形文件
initial begin
    $dumpfile("tb_simple_test.vcd");
    $dumpvars(0, tb_simple_test);
end

endmodule 