`timescale 1ns / 1ps

module puf_top (
    input        clk,
    input        reset_n,
    input  [7:0] challenge,   // written by Python via AXI GPIO
    input        start,       // pulsed by Python to trigger one measurement
    output [7:0] response,    // read by Python via AXI GPIO
    output       done         // Python polls this to know the result is ready
);
    wire rstc, rst_dff, out_trig;

    puf_driver driver (
        .clk(clk), .reset_n(reset_n), .start(start),
        .rstc(rstc), .rst_dff(rst_dff), .out_trig(out_trig)
    );

    puf_array array (
        .clk(clk), .rstc(rstc), .rst_dff(rst_dff),
        .C(challenge), .out_trig(out_trig), .R(response)
    );

    reg done_r;
    always @(posedge clk) done_r <= out_trig;
    assign done = done_r;

endmodule