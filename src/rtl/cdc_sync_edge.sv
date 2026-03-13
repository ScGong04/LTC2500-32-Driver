`ifndef __CDC_SYNC_EDGE__
`define __CDC_SYNC_EDGE__

module cdc_sync_edge #(
    parameter bit INIT_VAL = 1'b0 
)(
    input  wire  i_clk,
    input  wire  i_rst_n,
    input  wire  async_in,
    output logic sync_out
);
    logic [1:0] flops;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            
            flops <= {2{INIT_VAL}}; 
        end
        else begin
            flops <= {flops[0], async_in};
        end
    end

    assign sync_out = flops[1];
    
endmodule
`endif