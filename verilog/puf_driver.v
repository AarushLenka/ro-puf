`timescale 1ns / 1ps

// One measurement cycle, timed from a start pulse:
//   t=0     : rstc=1, rst_dff=1  — reset all counters and the output latch
//   t=1..48 : counters free-run, counting oscillator edges
//   t=48    : out_trig=1        — latch whichever counter is ahead
//   t=49    : idle, ready for the next start pulse

module puf_driver (
    input  clk,
    input  reset_n,     // active-low reset
    input  start,       // pulse high for 1 cycle to begin a measurement
    output rstc,
    output rst_dff,
    output out_trig
);
    reg [5:0] cnt;
    reg       running;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cnt     <= 6'd0;
            running <= 1'b0;
        end else if (start && !running) begin
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