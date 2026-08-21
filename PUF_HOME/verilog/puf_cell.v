`timescale 1ns / 1ps

module puf_cell #(
    parameter CELL_ID = 0   // 0–7, gives every oscillator across all cells a unique ID
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

    // OR-reduce: since only one oscillator per group is enabled at a time,
    // this passes through exactly that oscillator's output.
    wire clk0 = |osc0_out;
    wire clk1 = |osc1_out;

    reg [7:0] cnt0, cnt1;

    always @(posedge clk0 or posedge rstc)
        if (rstc) cnt0 <= 8'd0;
        else if (cnt0 < 8'd255) cnt0 <= cnt0 + 8'd1;

    always @(posedge clk1 or posedge rstc)
        if (rstc) cnt1 <= 8'd0;
        else if (cnt1 < 8'd255) cnt1 <= cnt1 + 8'd1;

    // Latch the comparison result when the driver pulses out_trig.
    always @(posedge clk or posedge rst_dff) begin
        if (rst_dff)
            R <= 1'b0;
        else if (out_trig)
            R <= (cnt0 > cnt1) ? 1'b1 : 1'b0;
    end

endmodule