`timescale 1ns / 1ps
// Self-checking regression for the driver/top handshake fixes.
// Deliberately drives `start` the way python/01_collect_crps.py does: assert it
// and hold it high while polling, then drop it after done is seen.
module tb_puf_check;

    reg clk = 0, reset_n = 0, start = 0;
    reg [7:0] challenge = 8'h00;
    wire [7:0] response;
    wire done;

    always #10 clk = ~clk;   // 50 MHz, matches FCLK_CLK0

    puf_top dut (
        .clk(clk), .reset_n(reset_n), .challenge(challenge),
        .start(start), .response(response), .done(done)
    );

    integer done_high_cycles;
    integer rstc_pulses;
    integer errors = 0;

    // Count rstc assertions to prove the driver does not re-trigger while
    // start is held high.
    always @(posedge clk) if (dut.rstc) rstc_pulses = rstc_pulses + 1;
    always @(posedge clk) if (done)     done_high_cycles = done_high_cycles + 1;

    task do_measurement(input [7:0] c);
        integer polls;
        begin
            done_high_cycles = 0;
            rstc_pulses      = 0;
            challenge        = c;
            polls            = 0;

            start = 1'b1;                       // assert and HOLD, as software does
            while (!done && polls < 2000) begin // poll, like the Python loop
                @(posedge clk);
                polls = polls + 1;
            end

            if (!done) begin
                $display("FAIL [c=%0d]: done never asserted within %0d cycles", c, polls);
                errors = errors + 1;
            end

            // done must still be high several cycles later -- it is a level, not
            // a 1-cycle pulse that software could miss.
            repeat (20) @(posedge clk);
            if (!done) begin
                $display("FAIL [c=%0d]: done did not HOLD (pulse, not level)", c);
                errors = errors + 1;
            end

            // Exactly one measurement must have run despite start being held.
            if (rstc_pulses != 1) begin
                $display("FAIL [c=%0d]: driver re-triggered - rstc asserted %0d times, expected 1",
                         c, rstc_pulses);
                errors = errors + 1;
            end

            start = 1'b0;                       // software clears start
            repeat (5) @(posedge clk);
            if (done) begin
                $display("FAIL [c=%0d]: done did not clear after start dropped", c);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset_n = 1'b1;

        // done must be low out of reset (not X) -- catches the missing-reset bug.
        if (done !== 1'b0) begin
            $display("FAIL: done is %b out of reset, expected 0", done);
            errors = errors + 1;
        end

        do_measurement(8'h00);
        do_measurement(8'h5A);
        do_measurement(8'hFF);

        if (errors == 0) $display("PASS: all handshake checks OK");
        else             $display("%0d FAILURE(S)", errors);
        $finish;
    end

    initial begin
        #500000;
        $display("FAIL: global timeout");
        $finish;
    end
endmodule
