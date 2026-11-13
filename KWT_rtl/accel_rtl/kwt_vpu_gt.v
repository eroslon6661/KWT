`timescale 1ns / 1ps
module kwt_vpu_gt (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire        gt
);
    wire both_zero =
        (a[30:0] == 0) && (b[30:0] == 0);
    assign gt =
        !both_zero &&
        ((a[31] != b[31]) ?
            !a[31] :
            a[31] ?
                (a[30:0] < b[30:0]) :
                (a[30:0] > b[30:0]));
endmodule
