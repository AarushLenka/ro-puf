`timescale 1ns / 1ps

module puf_array_xor (
    input        clk,
    input        rstc,
    input        rst_dff,
    input  [7:0] C,
    input        out_trig,
    output [7:0] R
);
    wire [3:0] sel0 = C[3:0];
    wire [3:0] sel1 = C[7:4];

    wire [7:0] raw_R;   // raw, per-cell comparison outputs (what puf_array.v exposed directly)

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : cells
            puf_cell #(.CELL_ID(i)) cell (
                .clk(clk), .rstc(rstc), .rst_dff(rst_dff),
                .sel0(sel0), .sel1(sel1),
                .out_trig(out_trig), .R(raw_R[i])
            );
        end
    endgenerate

    // Circular XOR mixing: R[i] = raw[i] XOR raw[(i+1) mod 8]
    // No output bit is now an independent single measurement — each one
    // depends on two oscillator-pair comparisons at once.
    assign R[0] = raw_R[0] ^ raw_R[1];
    assign R[1] = raw_R[1] ^ raw_R[2];
    assign R[2] = raw_R[2] ^ raw_R[3];
    assign R[3] = raw_R[3] ^ raw_R[4];
    assign R[4] = raw_R[4] ^ raw_R[5];
    assign R[5] = raw_R[5] ^ raw_R[6];
    assign R[6] = raw_R[6] ^ raw_R[7];
    assign R[7] = raw_R[7] ^ raw_R[0];

endmodule