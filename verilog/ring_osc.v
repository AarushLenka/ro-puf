`timescale 1ns / 1ps

// A single ring oscillator with an enable input.
// en=1: the 7-stage inverter chain oscillates freely.
// en=0: the leading NAND gate holds the loop at logic 1, stopping oscillation.
//
// DONT_TOUCH is on the module (not just the nets) because KEEP only stops nets
// from being deleted -- it does NOT stop Vivado from noticing that all 256
// instances are structurally identical and merging them into one. A merged
// oscillator array has no per-instance physical variation, i.e. no PUF.
// INSTANCE_ID is carried into a net name below so each instance is also
// textually distinct in the netlist.

(* DONT_TOUCH = "TRUE", ALLOW_COMBINATORIAL_LOOPS = "TRUE" *)
module ring_osc #(
    parameter INSTANCE_ID = 0  // forces synthesis to keep every instance distinct
)(
    input  en,
    input  rst,
    output op
);
    (* DONT_TOUCH = "TRUE" *) wire w1, w2, w3, w4, w5, w6, w7, wop;

    assign w1  = ~(en & w7);
    assign w2  = ~w1;
    assign w3  = ~w2;
    assign w4  = ~w3;
    assign w5  = ~w4;
    assign w6  = ~w5;
    assign w7  = ~w6;
    assign wop = ~w7;

    // Ties INSTANCE_ID into the netlist so the instances are not literally
    // interchangeable. Costs nothing: it drives no logic.
    (* DONT_TOUCH = "TRUE" *) wire [31:0] id_tag = INSTANCE_ID;

    // The raw loop is far too fast to feed a counter directly; divide by 2 first.
    clock_div_2 div (.clk(wop), .rst(rst), .q(op));

endmodule
