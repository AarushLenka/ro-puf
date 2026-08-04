`timescale 1ns / 1ps

module clock_div_2 (
    input  clk,
    input  rst,
    output reg q
);
    // Flips the output on every rising edge — exactly divides frequency by 2.
    always @(posedge clk or posedge rst) begin
        if (rst)
            q <= 0;
        else
            q <= ~q;
    end
endmodule