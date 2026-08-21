`timescale 1ns / 1ps

module puf_top (
    input        clk,
    input        reset_n,
    input  [7:0] challenge,   // written by Python via AXI GPIO
    input        start,       // held high by Python until done reads back 1
    output [7:0] response,    // read by Python via AXI GPIO
    output       done         // Python polls this to know the result is ready
);
    wire rstc, rst_dff, out_trig;

    puf_driver driver (
        .clk(clk), .reset_n(reset_n), .start(start),
        .rstc(rstc), .rst_dff(rst_dff), .out_trig(out_trig)
    );

    // NOTE: puf_array_xor is the XOR-hardened variant and is intentionally not
    // instantiated here -- the raw array is the baseline used for the modelling
    // attack in python/02_ml_attack.py.
    puf_array array (
        .clk(clk), .rstc(rstc), .rst_dff(rst_dff),
        .C(challenge), .out_trig(out_trig), .R(response)
    );

    // `done` is a level, not a pulse. Registering out_trig directly made done
    // high for exactly one 20 ns clock period, while software polls on a ~100 us
    // interval -- the flag was essentially never observable. It now latches on
    // out_trig and holds until the next measurement is requested, so software
    // sees it regardless of poll timing.
    //
    // start is re-synchronised here (rather than reusing the driver's copy) so
    // this flop's clear is in the same clock domain as its set. It is cleared on
    // the synchronised level, so a new measurement always drops done first.
    reg start_meta, start_sync;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            start_meta <= 1'b0;
            start_sync <= 1'b0;
        end else begin
            start_meta <= start;
            start_sync <= start_meta;
        end
    end

    reg done_r;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            done_r <= 1'b0;
        else if (out_trig)
            done_r <= 1'b1;       // set takes priority: result is valid now
        else if (!start_sync)
            done_r <= 1'b0;       // cleared once software drops start
    end

    assign done = done_r;

endmodule
