`timescale 1ns / 1ps

// Eight PUF cells share the same challenge and run simultaneously,
// producing an 8-bit response. Each cell owns its own 32 oscillators,
// so the 8 response bits are statistically independent measurements.

module puf_array (
    input        clk,
    input        rstc,
    input        rst_dff,
    input  [7:0] C,
    input        out_trig,
    output [7:0] R
);
    wire [3:0] sel0 = C[3:0];
    wire [3:0] sel1 = C[7:4];

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : cells
            puf_cell #(.CELL_ID(i)) cell (
                .clk(clk), .rstc(rstc), .rst_dff(rst_dff),
                .sel0(sel0), .sel1(sel1),
                .out_trig(out_trig), .R(R[i])
            );
        end
    endgenerate

endmodule