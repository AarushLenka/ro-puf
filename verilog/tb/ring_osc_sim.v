`timescale 1ns / 1ps
// SIMULATION-ONLY replacement for ring_osc.v. Not for synthesis; not added to
// the Vivado project.
//
// The real ring_osc is a zero-delay combinational inverter ring. In an
// event-driven simulator that is an infinite delta-cycle loop -- it hangs
// without advancing time -- so the synthesisable module cannot be simulated
// directly. This models the same interface with an explicit period, and derives
// a slightly different period per INSTANCE_ID to stand in for the physical
// process variation the real PUF depends on.
module ring_osc #(
    parameter INSTANCE_ID = 0
)(
    input  en,
    input  rst,
    output op
);
    // 2.00-3.55 ns half-period spread across instances.
    localparam real HALF_PERIOD = 2.0 + 0.05 * (INSTANCE_ID % 32);

    reg raw = 1'b0;
    always begin
        #(HALF_PERIOD);
        raw = en ? ~raw : 1'b1;   // en=0 parks the loop high, as the NAND does
    end

    clock_div_2 div (.clk(raw), .rst(rst), .q(op));
endmodule
