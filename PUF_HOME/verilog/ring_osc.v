`timescale 1ns / 1ps

// A single ring oscillator with an enable input.
// en=1: the 7-stage inverter chain oscillates freely.
// en=0: the leading NAND gate holds the loop at logic 1, stopping oscillation.

module ring_osc #(
    parameter INSTANCE_ID = 0  // forces synthesis to keep every instance distinct
)(
    input  en,
    input  rst,
    output op
);
    (* KEEP = "TRUE" *) wire w1, w2, w3, w4, w5, w6, w7, wop;

    // KEEP="TRUE" stops Vivado from merging oscillators that look identical
    // on paper — if it did that, we'd lose the per-chip physical variation
    // this whole project depends on.
    assign w1  = ~(en & w7);
    assign w2  = ~w1;
    assign w3  = ~w2;
    assign w4  = ~w3;
    assign w5  = ~w4;
    assign w6  = ~w5;
    assign w7  = ~w6;
    assign wop = ~w7;

    clock_div_2 div (.clk(wop), .rst(rst), .q(op));

endmodule