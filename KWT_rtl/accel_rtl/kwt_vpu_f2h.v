`timescale 1ns / 1ps
module kwt_vpu_f2h (
    input  wire [31:0] f,
    output reg  [15:0] h
);
    wire [7:0] e = f[30:23];
    wire [23:0] m = {1'b1, f[22:0]};
    wire sub = e < 113;
    wire [7:0] sh = sub ? 8'd126 - e : 8'd13;
    wire [23:0] keep =
        (sh < 25) ? m >> sh : 24'd0;
    wire guard =
        (sh >= 1 && sh <= 24) ?
        ((m >> (sh - 1)) & 24'd1) != 0 :
        1'b0;
    wire sticky =
        (sh > 1 && sh <= 24) ?
        |(m & ((24'd1 << (sh - 1)) - 1)) :
        1'b0;
    wire [11:0] r =
        {1'b0, keep[10:0]} +
        {11'd0, (guard && (sticky || keep[0]))};
    wire [7:0] eh =
        e - 8'd112 + (r[11] ? 8'd1 : 8'd0);
    always @* begin
        if (e == 255)
            h = {
                f[31], 5'h1f,
                (|f[22:0] ? 10'h200 : 10'd0)
            };
        else if (e == 0 || e < 102)
            h = {f[31], 15'd0};
        else if (e >= 143)
            h = {f[31], 5'h1f, 10'd0};
        else if (sub)
            h = {
                f[31],
                (r[10] ? 5'd1 : 5'd0),
                r[9:0]
            };
        else if (eh >= 31)
            h = {f[31], 5'h1f, 10'd0};
        else
            h = {
                f[31],
                eh[4:0],
                (r[11] ? 10'd0 : r[9:0])
            };
    end
endmodule
