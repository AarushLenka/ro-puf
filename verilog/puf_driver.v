`timescale 1ns / 1ps

// One measurement cycle, timed from a start pulse:
//   cnt=0     : rstc=1, rst_dff=1  -- reset all counters and the output latch
//   cnt=1..47 : counters free-run, counting oscillator edges
//   cnt=48    : out_trig=1         -- latch whichever counter is ahead
//   cnt=49    : idle, ready for the next start pulse
//
// `start` is driven by AXI GPIO, which is clocked by FCLK_CLK0 -- a different
// clock domain from this module's `clk`. It is therefore synchronised through
// two flops before use. `challenge` is deliberately NOT synchronised: Python
// writes challenge and start in a single GPIO transaction, so the two flop
// stages below guarantee challenge has been stable for >= 2 cycles by the time
// start_pulse fires (standard data-stable-before-qualifier crossing).

module puf_driver (
    input  clk,
    input  reset_n,     // active-low reset
    input  start,       // held high by software until done is observed
    output rstc,
    output rst_dff,
    output out_trig
);
    reg [5:0] cnt;
    reg       running;

    // ----- CDC synchroniser + rising-edge detect on start -----
    // Edge detection is essential: software holds `start` high for the whole
    // polling loop. A level-sensitive trigger would restart the measurement
    // thousands of times, and rstc would clear the counters before they ever
    // accumulated a meaningful count.
    reg start_meta, start_sync, start_prev;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            start_meta <= 1'b0;
            start_sync <= 1'b0;
            start_prev <= 1'b0;
        end else begin
            start_meta <= start;
            start_sync <= start_meta;
            start_prev <= start_sync;
        end
    end

    wire start_pulse = start_sync & ~start_prev;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cnt     <= 6'd0;
            running <= 1'b0;
        end else if (start_pulse && !running) begin
            cnt     <= 6'd0;
            running <= 1'b1;
        end else if (running) begin
            if (cnt == 6'd49) begin
                cnt     <= 6'd0;
                running <= 1'b0;
            end else begin
                cnt <= cnt + 6'd1;
            end
        end
    end

    assign rstc     = running && (cnt == 6'd0);
    assign rst_dff  = running && (cnt == 6'd0);
    assign out_trig = running && (cnt == 6'd48);

endmodule
