


module ltc_driver_fsm #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 4
)(
    input wire i_clk, // assume for 100 MHz input clock
    input wire i_rst,
    input wire i_start,
    
    // Control Signals
    output wire o_mclk,
    output wire o_sync, // not being used
    output wire o_pre,
    input wire i_busy,
    input wire i_drl,
    
    // SPI signals
    output wire o_sdi,
    output wire o_scka,
    output wire o_rdla,
    input wire i_sdoa,

    output wire [DATA_WIDTH-1:0]o_data,
    output wire o_data_valid,
    output wire o_error

)

parameter CLK_FREQ = 100e6;

parameter t_MCLKH = 30e-9; // min = 20ns
parameter t_MCLKL = 20e-9; // min = 10ns
parameter t_CONV = 660e-9; // max = 660ns

parameter wait_MCLKH = CLK_FREQ * t_MCLKH;
parameter wait_DRL = CLK_FREQ * t_CONV;

typedef enum logic [2:0] state_t {
    STATE_IDLE,
    STATE_START,
    STATE_WAIT_DRL
    STATE_RECV_DATA,
    STATE_STOP
} state_t;
state_t state, next_state;

logic pre_drl;
logic negedge_drl;
always_ff @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        pre_drl <= 1'b0;
    end else begin
        pre_drl <= i_drl;
    end
end

assign negedge_drl = pre_drl & ~i_drl;

logic [7:0] timer_cnt, next_timer_cnt;
logic [5:0] bit_cnt, next_bit_cnt;

logic [DATA_WIDTH-1:0] read_data, next_read_data;

// DISABLE some functionalities

assign o_sync = 1'b0;
assign o_pre = 1'b0;
assign o_sdi = 1'b0;

always_ff @(posedge i_clk or posedge i_rst) begin
    if (i_rst) begin
        state <= STATE_IDLE;
        bit_cnt <= '0;
        read_data <= '0;
        o_scka <= 1'b0;
        o_data <= '0;
        o_data_valid <= 1'b0;
    end else begin
        state <= next_state;
        bit_cnt <= next_bit_cnt;
        timer_cnt <= next_timer_cnt;
        read_data <= next_read_data;
    end
end

always_ff @(posedge i_clk or posedge i_rst) begin
   if (state == STATE_RECV_DATA) begin
        o_scka <= ~o_scka;
   end
end


always_ff @(posedge i_clk or posedge i_rst) begin
    if (state == STATE_STOP) begin
        o_data <= read_data;
        o_data_valid <= 1'b1;
        o_scka <= 0;
    end
end


always_ff @(posedge i_clk or posedge i_rst) begin
    if (state == STATE_START or STATE_WAIT_DRL) begin
        next_timer_cnt <= timer_cnt + 1;
    end
end 

always_ff @(posedge i_clk or posedge i_rst) begin
    if (state == STATE_RECV_DATA) begin
        next_bit_cnt <= bit_cnt + 1;
    end
end 

always_ff @(posedge i_clk or posedge i_rst) begin
    if (state - STATE_ERROR) begin
        o_error <= 1'b1;
    end
end


always_comb begin : 

    next_mclk = 1'b0;



    case (state)
        STATE_IDLE:
            if (!i_busy) begin
                next_state = STATE_START;
            end

        STATE_START:
            next_mclk = 1'b1;
            if (counter == wait_MCLKH - 1) begin
                next_state = STATE_DATA;
                next_timer_cnt = '0;
            end

        STATE_WAIT_DRL:
            if (negedge_drl) begin
                next_state = STATE_RECV_DATA;
                next_timer_cnt = '0;
                next_bit_cnt = '0;
            end

        STATE_RECV_DATA:
            if (o_scka) begin
                next_read_data = {read_data[30:0], i_sdoa};
            end

            if (bit_cnt == '31) begin
                next_bit_cnt = '0;
                next_state = STATE_STOP;
            end

        STATE_STOP: 
            if (counter == wait_MCLKL - 1) begin
                next_state = STATE_IDLE;
            end

        STATE_ERROR:
            next_state = STATE_IDLE; 

        default:
            next_state = STATE_IDLE;

        

    endcase
    end


endmodule
