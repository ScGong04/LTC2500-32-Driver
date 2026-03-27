`timescale 1ns / 1ps

module ltc2500_slave (
    input  wire mclk,
    output logic busy,
    output logic drl,
    input  wire rdla,
    input  wire scka,
    output wire sdoa
);

    logic [31:0] internal_data;
    logic [5:0]  bit_idx;
    logic        sdoa_reg;

    initial begin
        busy = 1'b0;
        drl  = 1'b1;
        sdoa_reg = 1'b0;
        internal_data = 32'hDEAD_ABCD; 
    end

    always @(posedge mclk) begin
        busy <= 1'b1;
        drl  <= 1'b1;
        
        // conversion time
        #660; 
        
        busy <= 1'b0;

        #10;
        
        internal_data <= ~internal_data; 
        drl  <= 1'b0;
    end

    always @(negedge rdla) begin
        bit_idx  = 31;
        sdoa_reg = internal_data[bit_idx];
    end

    always @(posedge scka) begin
        if (~rdla) begin
            if (bit_idx > 0) begin
                bit_idx  = bit_idx - 1;
                sdoa_reg = internal_data[bit_idx];
            end else begin
                sdoa_reg = 1'b0; 
            end
        end
    end

    assign sdoa = (rdla == 1'b0) ? sdoa_reg : 1'bz;

endmodule