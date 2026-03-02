


module ltc_driver_fsm #(
    parameter DATA_WIDTH = 32,
    parameter CLK_FREQ = 100e6 // 100 MHz
)(
    input wire i_clk, // assume for 100 MHz input clock
    input wire i_rst_n,
    input wire i_start,
    
    // Control Signals
    output logic o_mclk,
    output logic o_sync, // not being used
    output logic o_pre,
    input wire i_busy,
    input wire i_drl,
    
    // SPI signals
    output logic o_sdi,
    output logic o_scka,
    output logic o_rdla,
    input wire i_sdoa,

    output logic [DATA_WIDTH-1:0] o_read_data,
    output logic o_data_valid,
    output logic o_error
);

localparam int CYCLES_MCLKH = 3; 
localparam int CYCLES_MCLKL = 2; 
localparam int CYCLES_CONV = 66; 
localparam int SCK_DIV = 2;

typedef enum logic [2:0] {
    STATE_IDLE,
    STATE_START,
    STATE_WAIT_BUSY,
    STATE_WAIT_DRL,
    STATE_QUIET,
    STATE_READ_DATA,
    STATE_STOP
} state_t; 

state_t state, next_state;

logic [31:0] shift_reg, next_shift_reg;
logic bit_en;
logic bit_clr;
logic delay_en;
logic delay_clr;
logic [5:0] bit_cnt;
logic [7:0] delay_cnt;

logic next_mclk;
logic next_rdla;
logic next_data_valid;
logic next_error;

// DISABLE some functionalities
assign o_sync = 1'b0;
assign o_pre = 1'b0;
assign o_sdi = 1'b0;


// SCKA generator

logic sck_en;
logic [3:0] sck_cnt;

always_ff @(posedge i_clk or posedge i_rst_n) begin
    if (~i_rst_n) begin
        o_scka <= 1'b0;
        sck_cnt <= '0;
    end 
    else begin
        if (sck_en) begin
            if (sck_cnt == SCK_DIV - 1) begin
                sck_counter <= '0;
                o_scka <= ~o_scka;
            end 
            else begin
                sck_cnt <= sck_cnt + 1'b1;
            end
        else begin
            o_scka <= 1'b0;
            sck_cnt <= '0;
        end
    end
end 

wire sck_posedge = sck_en && (sck_counter == SCK_DIV - 1) && (o_scka == 1'b0);
wire sck_negedge = sck_en && (sck_counter == SCK_DIV - 1) && (o_scka == 1'b1);

cdc_sync_edge cdc_sync_edge_inst1 (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .async_in(i_busy),
    .sync_out(busy_sync)
);


cdc_sync_edge cdc_sync_edge_inst2 (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .async_in(i_drl),
    .sync_out(drl_sync)
);

logic busy_sync_d, drl_sync_d;
logic negedge_drl, negedge_drl;

always_ff @(posedge i_clk or posedge i_rst_n) begin
    if (i_rst) begin
        busy_sync <= 1'b0;
        drl_sync_d <= 1'b0;
    end else begin
        busy_sync_d <= busy_sync;
        drl_sync_d <= drl_sync; 
    end
end

assign negedge_busy = busy_sync_d & ~busy_sync;
assign negedge_drl = drl_sync_d & ~drl_sync;

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n)
        delay_cnt <= '0;
    else if (delay_clr)
        delay_cnt <= '0;
    else if (delay_en)
        delay_cnt <= delay_cnt + 1'b1;
end


always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n)
        bit_cnt <= '0;
    else if (bit_clr)
        bit_cnt <= '0;
    else if (bit_en)
        bit_cnt <= bit_cnt + 1'b1;
end

always_ff @(posedge i_clk or posedge i_rst_n) begin
    if (i_rst) begin
        state <= STATE_IDLE;
        shift_reg <= '0;
        bit_cnt <= '0;
        delay_cnt <= '0;
        o_mclk <= 1'b0;
        o_rdla <= 1'b1;
        o_data_valid <= 1'b0;
        o_error <= 1'b0;
    end else begin
        state <= next_state;
        shift_reg <= next_shift_reg;
        o_mclk <= next_mclk;
        o_rdla <= next_rdla;
        o_data_valid <= next_data_valid;
        o_error <= next_error;
    end
end

always_comb begin : 
    next_state = state;
    next_shift_reg = shift_reg;
    next_bit_cnt = bit_cnt;
    next_delay_cnt = delay_cnt;

    next_mclk = o_mclk;
    next_rdla = o_rdla;
    next_data_valid = 1'b0;
    next_error = o_error;

    sck_en = 1'b0;

    delay_en = 1'b0;
    delay_clr = 1'b0;
    bit_en = 1'b0;
    bit_clr = 1'b0;

    case (state)
        STATE_IDLE: begin
            next_mclk = 1'b0;
            next_rdla = 1'b1;
            if (i_start) begin
                next_state = STATE_START;
                next_error = '0;
            end
        end

        STATE_START: begin
            next_mclk = 1'b1;
            delay_en = 1'b1;
            if (counter == CYCLES_MCLKH - 1) begin
                next_state = STATE_WAIT_BUSY;
                next_mclk = 1'b0;
                delay_clr = 1'b1;
            end
        end
        
        STATE_WAIT_BUSY: begin
            delay_en = 1'b1;
            if (negedge_busy) begin
                next_state = STATE_WAIT_DRL;
                delay_clr = 1'b1;
            end
            else if (delay_cnt == CYCLES_CONV) begin 
                next_error = 1'b1;
                next_state = STATE_IDLE;
            end
        end

        STATE_WAIT_DRL: begin
            if (negedge_drl) begin
                next_state = STATE_QUIET;
                delay_clr = 1'b1;
            end
        end

        STATE_QUIET: begin
            next_rdla = 1'b0;
            delay_en = 1'b1;
            if (delay_cnt >= CYCLES_MCLKL - 1) begin
                next_state = STATE_READ_DATA;
                delay_clr = 1'b1;
            end
        end

        STATE_READ_DATA: begin
            o_rdla = 1'b0;
            sck_en = 1'b1;

            bit_en = sck_negedege;

            if (bit_cnt == 6'32) begin
                next_state = STATE_STOP;
                sck_en = 1'b0;
                delay_clr = 1'b1;
            end
            else begin
                next_shift_reg[31-bit_cnt] = i_sdoa;
            end
        end

        STATE_STOP: begin
            delay_en = 1'b1;       
            if (delay_cnt >= CYCLES_MCLKL - 1) begin
                o_data_data = shift_reg;
                o_data_valid = 1'b1;
                next_state = STATE_IDLE;
                delay_clr = 1'b1;
            end    
        
        end

        STATE_ERROR: begin
            next_state = STATE_IDLE; 
        end

        default:
            next_state = STATE_IDLE;
    endcase
    end


endmodule
