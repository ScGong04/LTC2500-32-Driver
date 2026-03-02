`ifndef __CDC_SYNC_EDGE__
`define __CDC_SYNC_EDGE__

module cdc_sync_edge (
    input wire i_clk,
    input wire i_rst_n,
    input wire async_in,
    output logic sync_out
)
    logic [1:0] flops;

    always_ff @(posedge clk or negedge rst_n) begin
        if (~i_rst_n) begin
            flops <= {2{1'b0}}; // depend on the # flops needed
        end
        else begin
            flops <= {flops[0], async_in};
        end
    end

    assign sync_out = flops[1];
endmodule
`endif