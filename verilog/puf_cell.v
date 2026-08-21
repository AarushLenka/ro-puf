`timescale 1ns / 1ps

module puf_cell #(
    parameter CELL_ID = 0   // 0-7, gives every oscillator across all cells a unique ID
)(
    input        clk,
    input        rstc,       // resets the counters
    input        rst_dff,    // resets the output latch
    input  [3:0] sel0,       // which oscillator in group 0 (from C[3:0])
    input  [3:0] sel1,       // which oscillator in group 1 (from C[7:4])
    input        out_trig,   // pulse to latch the comparison result
    output reg   R           // one response bit
);

    // ----- Group 0: 16 ring oscillators, one enabled at a time -----
    wire [15:0] osc0_out;
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g0
            ring_osc #(.INSTANCE_ID(CELL_ID*32 + i)) ro (
                .en(sel0 == i[3:0]), .rst(rstc), .op(osc0_out[i])
            );
        end
    endgenerate

    // ----- Group 1: 16 ring oscillators -----
    wire [15:0] osc1_out;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g1
            ring_osc #(.INSTANCE_ID(CELL_ID*32 + 16 + i)) ro (
                .en(sel1 == i[3:0]), .rst(rstc), .op(osc1_out[i])
            );
        end
    endgenerate

    // Select the enabled oscillator's output. An OR-reduce of all 16 would also
    // pick up the *disabled* oscillators' divider outputs: clock_div_2.q holds
    // its last value when its clock stops, so a disabled channel can sit at 1
    // and jam the OR permanently high. Masking by the select makes only the
    // chosen channel observable.
    wire [15:0] osc0_masked = osc0_out & (16'b1 << sel0);
    wire [15:0] osc1_masked = osc1_out & (16'b1 << sel1);
    wire clk0 = |osc0_masked;
    wire clk1 = |osc1_masked;

    // 16-bit so the count cannot saturate within the measurement window.
    // At 8-bit the counters cap at 255 and `cnt0 > cnt1` degenerates to 0
    // whenever both saturate.
    reg [15:0] cnt0, cnt1;

    always @(posedge clk0 or posedge rstc)
        if (rstc) cnt0 <= 16'd0;
        else      cnt0 <= cnt0 + 16'd1;

    always @(posedge clk1 or posedge rstc)
        if (rstc) cnt1 <= 16'd0;
        else      cnt1 <= cnt1 + 16'd1;

    // cnt0/cnt1 are clocked by the asynchronous oscillators, so they must be
    // brought into the `clk` domain before being compared -- sampling them
    // directly in the comparison below is a CDC violation and can latch a
    // metastable value. Two flop stages per counter.
    reg [15:0] cnt0_meta, cnt1_meta, cnt0_sys, cnt1_sys;
    always @(posedge clk) begin
        cnt0_meta <= cnt0;
        cnt1_meta <= cnt1;
        cnt0_sys  <= cnt0_meta;
        cnt1_sys  <= cnt1_meta;
    end

    // Latch the comparison result when the driver pulses out_trig.
    always @(posedge clk or posedge rst_dff) begin
        if (rst_dff)
            R <= 1'b0;
        else if (out_trig)
            R <= (cnt0_sys > cnt1_sys) ? 1'b1 : 1'b0;
    end

endmodule
