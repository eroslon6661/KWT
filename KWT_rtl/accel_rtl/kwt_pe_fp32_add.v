`timescale 1ns / 1ps
module kwt_pe_fp32_add (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] y
);
    wire a_big = a[30:0] >= b[30:0];
    wire [31:0] big_op   = a_big ? a : b;
    wire [31:0] small_op = a_big ? b : a;
    wire [7:0] eb = big_op[30:23];
    wire [7:0] es = small_op[30:23];
    wire [7:0] eb_eff = (eb == 0) ? 8'd1 : eb;
    wire [7:0] es_eff = (es == 0) ? 8'd1 : es;
    wire [26:0] big_sig   = {|eb, big_op[22:0],   3'b000};
    wire [26:0] small_sig = {|es, small_op[22:0], 3'b000};
    wire [7:0] delta = eb_eff - es_eff;
    wire [4:0] sh = (delta >= 8'd27) ? 5'd27 : delta[4:0];
    wire [26:0] shifted = small_sig >> sh;
    wire sticky = |(small_sig & ((27'd1 << sh) - 27'd1));
    wire [26:0] aligned = {shifted[26:1], shifted[0] | sticky};
    wire same_sign = a[31] == b[31];
    wire [27:0] mant_sum = same_sign
        ? ({1'b0, big_sig} + {1'b0, aligned})
        : ({1'b0, big_sig} - {1'b0, aligned});
    wire [26:0] mant0 = mant_sum[27]
        ? {mant_sum[27:2], |mant_sum[1:0]} : mant_sum[26:0];
    wire [8:0] exp0 = {1'b0, eb_eff} + {8'd0, mant_sum[27]};
    reg [4:0] leading;
    integer k;
    always @* begin
        leading = 5'd0;
        for (k = 0; k < 27; k = k + 1) begin
            if (mant0[k])
                leading = 5'd26 - k[4:0];
        end
    end
    wire [4:0] left_sh = (exp0 <= {4'd0, leading})
                       ? (exp0[4:0] - 5'd1) : leading;
    wire [26:0] norm = mant0 << left_sh;
    wire inc = norm[2] && (norm[1] || norm[0] || norm[3]);
    wire [24:0] rounded = {1'b0, norm[26:3]} + {24'd0, inc};
    wire [8:0] exp_final = exp0 - {4'd0, left_sh} + {8'd0, rounded[24]};
    wire [7:0] exp_field = (rounded[24] || rounded[23])
                         ? exp_final[7:0] : 8'd0;
    wire [22:0] frac_field = rounded[24] ? 23'd0 : rounded[22:0];
    wire a_nan = (&a[30:23]) && (|a[22:0]);
    wire b_nan = (&b[30:23]) && (|b[22:0]);
    wire a_inf = a[30:0] == 31'h7f800000;
    wire b_inf = b[30:0] == 31'h7f800000;
    always @* begin
        if (a_nan || b_nan || (a_inf && b_inf && !same_sign))
            y = 32'h7fc00000;
        else if (a_inf || b_inf)
            y = a_inf ? a : b;
        else if (mant_sum == 0)
            y = {a[31] & b[31], 31'd0};
        else if (exp_final >= 9'd255)
            y = {big_op[31], 8'hff, 23'd0};
        else
            y = {big_op[31], exp_field, frac_field};
    end
endmodule