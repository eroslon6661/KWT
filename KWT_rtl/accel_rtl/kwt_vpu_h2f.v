`timescale 1ns / 1ps
module kwt_vpu_h2f (
    input  wire [15:0] h,
    output wire [31:0] f
);
    wire [15:0] s0 = {h[9:0], 6'b0};
    wire z8 = !(|s0[15:8]);
    wire [15:0] s1 = z8 ? s0 << 8 : s0;
    wire z4 = !(|s1[15:12]);
    wire [15:0] s2 = z4 ? s1 << 4 : s1;
    wire z2 = !(|s2[15:14]);
    wire [15:0] s3 = z2 ? s2 << 2 : s2;
    wire z1 = !s3[15];
    wire [15:0] sn = z1 ? s3 << 1 : s3;
    wire [3:0] lz = {z8, z4, z2, z1};
    wire [7:0] en = 8'd112 + {3'b0, h[14:10]};
    wire [7:0] es = 8'd112 - {4'b0, lz};
    assign f =
        (h[14:10] == 31) ?
            {h[15], 8'hff, h[9:0], 13'b0} :
        (h[14:10] != 0) ?
            {h[15], en, h[9:0], 13'b0} :
        (h[9:0] == 0) ?
            {h[15], 31'b0} :
            {h[15], es, sn[14:0], 8'b0};
endmodule
