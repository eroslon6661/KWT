`timescale 1ns / 1ps
module kwt_dequant_fp32_pack (
    input  wire [31:0] product,
    input  wire        sign,
    input  wire [7:0]  scale_exp,
    output wire [31:0] fp32
);
    wire [3:0] sh =
        product[30] ? 4'd1 :
        product[29] ? 4'd2 :
        product[28] ? 4'd3 :
        product[27] ? 4'd4 :
        product[26] ? 4'd5 :
        product[25] ? 4'd6 :
        product[24] ? 4'd7 :
        product[23] ? 4'd8 : 4'd0;
    wire [31:0] norm = product << sh;
    wire guard_bit  = norm[7];
    wire sticky_bit = |norm[6:0];
    wire increment =
        guard_bit && (sticky_bit || norm[8]);
    wire [24:0] rounded =
        {1'b0, norm[31:8]} + {24'd0, increment};
    wire [9:0] exponent =
        {2'd0, scale_exp}
        + 10'd8
        - {6'd0, sh}
        + {9'd0, rounded[24]};
    assign fp32 =
        (product == 0)
        ? {sign, 31'd0}
        : (exponent >= 10'd255)
          ? {sign, 8'hff, 23'd0}
          : {
                sign,
                exponent[7:0],
                (rounded[24] ? 23'd0 : rounded[22:0])
            };
endmodule
