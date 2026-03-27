module ltc_driver_fsm #(
    parameter int DATA_WIDTH = 32,
    parameter int ETH_DATA_WIDTH = 8,
    parameter int CLK_FREQ   = 100_000_000, // 100 M
    parameter int DF         = 64           // Down-Sampling Factor
)(
    input  wire i_clk, 
    input  wire i_rst_n,
    input  wire i_start,
    
    // Control Signals
    output logic o_mclk,
    output logic o_sync, 
    output logic o_pre,
    input  wire  i_busy,
    input  wire  i_drl,
    
    // SPI signals
    output logic o_sdi,
    output logic o_scka,
    output logic o_rdla,
    input  wire  i_sdoa,
    
    output logic [3:0] o_debug_state,

    output logic [DATA_WIDTH-1:0] o_read_data,
    output logic [ETH_DATA_WIDTH-1:0] o_eth_data,
    output logic o_eth_valid,
    output logic o_data_valid,
    output logic o_error
);

localparam int CYCLES_MCLKH = 3;  
localparam int CYCLES_MCLKL = 2;  
localparam int CYCLES_CONV  = 75; 
localparam int CYCLES_ACQ   = 35; 
localparam int SCK_DIV      = 2;

typedef enum logic [3:0] { 
    STATE_IDLE,
    STATE_START,
    STATE_WAIT_BUSY,
    STATE_ACQUIRE,     
    STATE_WAIT_DRL,
    STATE_QUIET,
    STATE_READ_DATA,
    STATE_READ_DONE,
    STATE_SEND_ETH,
    STATE_STOP,
    STATE_ERROR 
} state_t; 

state_t state, next_state;

assign o_debug_state = state;

logic [31:0] shift_reg;
logic bit_en, bit_clr;
logic delay_en, delay_clr;
logic eth_byte_en, eth_byte_clr;
logic [5:0] bit_cnt;
logic [7:0] delay_cnt;
logic [2:0] eth_byte_cnt;

logic [6:0] mclk_cnt;
logic mclk_cnt_en, mclk_cnt_clr;

logic next_mclk;
logic next_rdla;
logic next_data_valid;
logic next_error;

assign o_sync = 1'b0;
assign o_pre  = 1'b1; 
assign o_sdi  = 1'b0;

logic sck_en;
logic [3:0] sck_cnt;

logic next_eth_valid;
logic [7:0] next_eth_data;

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n) begin
        o_scka  <= 1'b0;
        sck_cnt <= '0;
    end else begin
        if (sck_en) begin
            if (sck_cnt == SCK_DIV - 1) begin
                sck_cnt <= '0;
                o_scka  <= ~o_scka;
            end else begin
                sck_cnt <= sck_cnt + 1'b1;
            end
        end
        else begin
            o_scka  <= 1'b0;
            sck_cnt <= '0;
        end
    end
end 

wire sck_posedge = sck_en && (sck_cnt == SCK_DIV - 1) && (o_scka == 1'b0);
wire sck_negedge = sck_en && (sck_cnt == SCK_DIV - 1) && (o_scka == 1'b1);

logic busy_sync, drl_sync;

cdc_sync_edge #(.INIT_VAL(1'b0)) cdc_sync_edge_inst1 (
    .i_clk(i_clk), .i_rst_n(i_rst_n), .async_in(i_busy), .sync_out(busy_sync)
);

cdc_sync_edge #(.INIT_VAL(1'b1)) cdc_sync_edge_inst2 (
    .i_clk(i_clk), .i_rst_n(i_rst_n), .async_in(i_drl), .sync_out(drl_sync)
);

logic busy_sync_d, drl_sync_d;
always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n) begin 
        busy_sync_d <= 1'b0;
        drl_sync_d  <= 1'b1;
    end else begin
        busy_sync_d <= busy_sync;
        drl_sync_d  <= drl_sync; 
    end
end

wire negedge_busy = busy_sync_d & ~busy_sync;
wire negedge_drl  = drl_sync_d  & ~drl_sync;

// ----------------------------------------------------
// Data Path Counters
// ----------------------------------------------------
always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n)          delay_cnt <= '0;
    else if (delay_clr)    delay_cnt <= '0;
    else if (delay_en)     delay_cnt <= delay_cnt + 1'b1;
end

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n)          bit_cnt <= '0;
    else if (bit_clr)      bit_cnt <= '0;
    else if (bit_en)       bit_cnt <= bit_cnt + 1'b1;
end

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n)          eth_byte_cnt <= '0;
    else if (eth_byte_clr) eth_byte_cnt <= '0;
    else if (eth_byte_en)  eth_byte_cnt <= eth_byte_cnt + 1'b1;
end

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n)          mclk_cnt <= '0;
    else if (mclk_cnt_clr) mclk_cnt <= '0;
    else if (mclk_cnt_en)  mclk_cnt <= mclk_cnt + 1'b1;
end 

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n) begin
        shift_reg <= '0;
    end else if (state == STATE_READ_DATA && sck_negedge) begin
        shift_reg <= {shift_reg[30:0], i_sdoa}; 
    end
end

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n) begin 
        o_eth_data  <= '0;
        o_eth_valid <= 1'b0;
    end else begin
        o_eth_data  <= next_eth_data;
        o_eth_valid <= next_eth_valid;
    end
end

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n) begin
        state        <= STATE_IDLE;
        o_mclk       <= 1'b0;
        o_rdla       <= 1'b1;
        o_data_valid <= 1'b0;
        o_error      <= 1'b0;
    end else begin
        state        <= next_state;
        o_mclk       <= next_mclk;
        o_rdla       <= next_rdla;
        o_data_valid <= next_data_valid;
        o_error      <= next_error;
    end
end

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (~i_rst_n) begin
        o_read_data <= '0;
    end else if (state == STATE_READ_DONE) begin
        o_read_data <= shift_reg;
    end
end

always_comb begin
    next_state      = state;
    next_mclk       = o_mclk;
    next_rdla       = o_rdla;
    next_data_valid = 1'b0;
    next_eth_valid  = 1'b0;
    next_eth_data   = o_eth_data;
    next_error      = o_error;

    sck_en       = 1'b0;
    delay_en     = 1'b0;
    delay_clr    = 1'b0;
    bit_en       = 1'b0;
    bit_clr      = 1'b0;
    eth_byte_en  = 1'b0;
    eth_byte_clr = 1'b0;
    mclk_cnt_en  = 1'b0;
    mclk_cnt_clr = 1'b0;

    case (state)
        STATE_IDLE: begin
            next_mclk = 1'b0;
            next_rdla = 1'b1;
            delay_clr = 1'b1;
            bit_clr   = 1'b1;
            mclk_cnt_clr = 1'b1; 
            
            if (i_start) begin
                next_state = STATE_START;
                next_error = 1'b0;
            end
        end

        STATE_START: begin
            next_mclk = 1'b1;
            delay_en  = 1'b1;
            if (delay_cnt == CYCLES_MCLKH - 1) begin 
                next_state = STATE_WAIT_BUSY;
                next_mclk  = 1'b0;
                delay_clr  = 1'b1;
            end
        end
        
        STATE_WAIT_BUSY: begin
            delay_en = 1'b1;
            if (negedge_busy) begin
                mclk_cnt_en = 1'b1;
                delay_clr   = 1'b1;
                
              
                if (mclk_cnt == DF - 1) begin
                    next_state = STATE_WAIT_DRL; // Sent 64 MCLK
                end else begin
                    next_state = STATE_ACQUIRE; 
                end
            end
            else if (delay_cnt == CYCLES_CONV) begin 
                next_error = 1'b1;
                next_state = STATE_ERROR;
            end
        end

        STATE_ACQUIRE: begin
            delay_en = 1'b1;
            if (delay_cnt >= CYCLES_ACQ - 1) begin
                next_state = STATE_START;
                delay_clr  = 1'b1;
            end
        end

        STATE_WAIT_DRL: begin
            if (~drl_sync) begin
                next_state = STATE_QUIET;
                delay_clr  = 1'b1;
            end
        end

        STATE_QUIET: begin
            next_rdla = 1'b0;
            delay_en  = 1'b1;
            if (delay_cnt >= CYCLES_MCLKL - 1) begin
                next_state = STATE_READ_DATA;
                delay_clr  = 1'b1;
            end
        end

        STATE_READ_DATA: begin
            next_rdla = 1'b0; 
            sck_en    = 1'b1;
            bit_en    = sck_negedge; 

            if (bit_cnt == 6'd32) begin
                next_state = STATE_READ_DONE;
                sck_en     = 1'b0;
                delay_clr  = 1'b1;
            end
        end

        STATE_READ_DONE: begin
            next_data_valid = 1'b1;
            eth_byte_clr    = 1'b1;
            next_state      = STATE_SEND_ETH;
        end
        
        STATE_SEND_ETH: begin
            eth_byte_en = 1'b1;
            
            next_eth_valid = ~eth_byte_cnt[0];

            case(eth_byte_cnt[2:1])
                2'b00: next_eth_data = shift_reg[31:24]; // count = 0, 1
                2'b01: next_eth_data = shift_reg[23:16]; // count = 2, 3
                2'b10: next_eth_data = shift_reg[15:8];  // count = 4, 5
                2'b11: next_eth_data = shift_reg[7:0];   // count = 6, 7
                default: next_eth_data = '0;
            endcase 

            if (eth_byte_cnt == 3'd7) begin
                eth_byte_en = 1'b0;
                next_state = STATE_STOP;
                eth_byte_clr = 1'b1;
            end
        end

        STATE_STOP: begin
            delay_en = 1'b1;       
            if (delay_cnt >= CYCLES_MCLKL - 1) begin
                next_state      = STATE_IDLE;
                delay_clr       = 1'b1;
            end    
        end

        STATE_ERROR: begin
            next_state = STATE_IDLE; 
        end

        default: next_state = STATE_IDLE;
    endcase
end

endmodule