`timescale 1ns / 1ps

module tb_ltc2500_driver;

    // 测试台信号定义
    logic clk;
    logic rst_n;
    logic start;
    
    // ADC 接口信号
    wire mclk;
    wire sync;
    wire pre;
    wire busy;
    wire drl;
    wire sdi;
    wire scka;
    wire rdla;
    wire sdoa;
    
    // FPGA 用户接口信号
    wire [31:0] read_data;
    wire        data_valid;
    wire        error;

    // -----------------------------------------------------------
    // 1. 产生 100MHz 主时钟 (周期 10ns)
    // -----------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 每 5ns 翻转一次
    end

    // -----------------------------------------------------------
    // 2. 例化你的驱动模块 (DUT - Device Under Test)
    // -----------------------------------------------------------
    ltc_driver_fsm #(
        .DATA_WIDTH(32),
        .CLK_FREQ(100_000_000)
    ) uut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_start(start),
        .o_mclk(mclk),
        .o_sync(sync),
        .o_pre(pre),
        .i_busy(busy),
        .i_drl(drl),
        .o_sdi(sdi),
        .o_scka(scka),
        .o_rdla(rdla),
        .i_sdoa(sdoa),
        .o_read_data(read_data),
        .o_data_valid(data_valid),
        .o_error(error)
    );

    // -----------------------------------------------------------
    // 3. 例化 ADC 行为模型
    // -----------------------------------------------------------
    ltc2500 adc_inst (
        .mclk(mclk),
        .busy(busy),
        .drl(drl),
        .rdla(rdla),
        .scka(scka),
        .sdoa(sdoa)
    );

    // -----------------------------------------------------------
    // 4. 编写测试激励 (Test Scenario)
    // -----------------------------------------------------------
    initial begin
        // 初始化信号
        rst_n = 0;
        start = 0;
        
        // 等待 100ns 后释放复位
        #100;
        rst_n = 1;
        $display("[%0t] System Reset Released.", $time);
        
        // 等待系统稳定
        #50;
        
        // 第一次触发采样
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        $display("[%0t] First Conversion Started...", $time);
        
        // 等待第一次读取完成 (监听 valid 信号)
        @(posedge data_valid);
        $display("[%0t] First Data Read: 32'h%h", $time, read_data);
        
//        // 闲置一段时间
//        #500;
        
//        // 第二次触发采样
//        @(posedge clk);
//        start = 1;
//        @(posedge clk);
//        start = 0;
//        $display("[%0t] Second Conversion Started...", $time);
        
//        // 等待第二次读取完成
//        @(posedge data_valid);
//        $display("[%0t] Second Data Read: 32'h%h", $time, read_data);
        
        // 结束仿真
        #200;
        $display("[%0t] Simulation Finished Successfully!", $time);
        $finish;
    end

    // 生成波形文件 (给 Vivado 或 ModelSim 用)
    initial begin
        $dumpfile("ltc2500_sim.vcd");
        $dumpvars(0, tb_ltc2500_driver);
    end

endmodule