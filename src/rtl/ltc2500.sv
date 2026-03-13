`timescale 1ns / 1ps

module ltc2500 (
    input  wire mclk,
    output logic busy,
    output logic drl,
    input  wire rdla,
    input  wire scka,
    output wire sdoa
);

    // 内部寄存器和参数
    logic [31:0] internal_data;
    logic [5:0]  bit_idx;
    logic        sdoa_reg;

    // 初始化状态
    initial begin
        busy = 1'b0;
        drl  = 1'b1; // DRL 默认是高电平
        sdoa_reg = 1'b0;
        internal_data = 32'hDEAD_BEEF; // 测试用的魔法数字 (Magic Number)
    end

    // -----------------------------------------------------------
    // 模拟 MCLK 触发与转换时间 (Behavioral Timing)
    // -----------------------------------------------------------
    always @(posedge mclk) begin
        busy <= 1'b1;
        drl  <= 1'b1;
        
        // 模拟 t_CONV 转换时间 (660ns)
        #660; 
        
        busy <= 1'b0;
        
        // 模拟滤波器出数据延迟 (加个 10ns 错开 busy 和 drl，更逼真)
        #10;
        
        // 每次转换完换个新数据，方便观察
        internal_data <= ~internal_data; 
        drl  <= 1'b0; // 告诉 FPGA：数据准备好了！
    end

    // -----------------------------------------------------------
    // 模拟 SPI 读取逻辑 (Shift Register)
    // -----------------------------------------------------------
    
    // 当 RDLA 拉低时，ADC 立刻准备好最高位 (MSB)
    always @(negedge rdla) begin
        bit_idx  = 31;
        sdoa_reg = internal_data[bit_idx];
    end

    // ADC 在 SCKA 的上升沿移出后续数据
    // (这就是为什么你的 FSM 要在下降沿采样，完美契合！)
    always @(posedge scka) begin
        if (~rdla) begin
            if (bit_idx > 0) begin
                bit_idx  = bit_idx - 1;
                sdoa_reg = internal_data[bit_idx];
            end else begin
                sdoa_reg = 1'b0; // 读完 32 bit 后输出 0
            end
        end
    end

    // -----------------------------------------------------------
    // 完美模拟引脚的三态门行为 (Hi-Z)
    // -----------------------------------------------------------
    assign sdoa = (rdla == 1'b0) ? sdoa_reg : 1'bz;

endmodule