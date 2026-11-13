`timescale 1ns / 1ps
module kwt_vpu_mul (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [31:0] y
);
    wire s = a[31] ^ b[31];
    wire [47:0] p =
        {1'b1, a[22:0]} * {1'b1, b[22:0]};
    wire hi = p[47];
    wire [23:0] m = hi ? p[47:24] : p[46:23];
    wire g = hi ? p[23] : p[22];
    wire st = hi ? |p[22:0] : |p[21:0];
    wire [24:0] rounded =
        {1'b0, m} + {24'd0, (g && (st || m[0]))};
    wire signed [10:0] ex =
        $signed({3'b0, a[30:23]}) +
        $signed({3'b0, b[30:23]}) -
        11'sd127 +
        (hi ? 11'sd1 : 11'sd0);
    wire signed [10:0] er =
        ex + (rounded[24] ? 11'sd1 : 11'sd0);
    wire az = a[30:23] == 0;
    wire bz = b[30:23] == 0;
    wire ai = a[30:23] == 255;
    wire bi = b[30:23] == 255;
    wire nan =
        (ai && |a[22:0]) ||
        (bi && |b[22:0]) ||
        (ai && bz) ||
        (bi && az);
    assign y =
        nan ? 32'h7fc00000 :
        (ai || bi) ? {s, 8'hff, 23'b0} :
        (az || bz || ex <= 0) ? {s, 31'b0} :
        er >= 255 ? {s, 8'hff, 23'b0} :
        {s, er[7:0], (rounded[24] ? 23'd0 : rounded[22:0])};
endmodule