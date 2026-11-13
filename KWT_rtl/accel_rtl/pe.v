`timescale 1ns / 1ps
`include "kwt1_defs.vh"
module pe #(
    parameter DATA_WIDTH = 16,
    parameter ACC_WIDTH  = 32
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        step,
    input  wire        w_load,
    input  wire [15:0] w_data,
    input  wire [15:0] data_in,
    input  wire [31:0] psum_in,
    output reg  [15:0] data_out,
    output reg  [31:0] psum_out
);
    reg [15:0] weight_q;
    always @(posedge clk or posedge rst) begin
        if (rst)
            weight_q <= 16'h0000;
        else if (w_load)
            weight_q <= w_data;
    end
    wire [4:0] ea = data_in[14:10];
    wire [4:0] eb = weight_q[14:10];
    wire [10:0] ma = {|ea, data_in[9:0]};
    wire [10:0] mb = {|eb, weight_q[9:0]};
    wire [5:0] ea_eff =
        (ea == 0) ? 6'd1 : {1'b0, ea};
    wire [5:0] eb_eff =
        (eb == 0) ? 6'd1 : {1'b0, eb};
    wire a_nan = (&ea) && (|data_in[9:0]);
    wire b_nan = (&eb) && (|weight_q[9:0]);
    wire a_inf = data_in[14:0]  == 15'h7c00;
    wire b_inf = weight_q[14:0] == 15'h7c00;
    wire a_zero = data_in[14:0]  == 0;
    wire b_zero = weight_q[14:0] == 0;
    wire invalid_product =
        a_nan || b_nan ||
        (a_inf && b_zero) ||
        (b_inf && a_zero);
    reg [21:0] mag_m1;
    reg [5:0]  exp_sum_m1;
    reg sign_m1;
    reg nan_m1;
    reg inf_m1;
    reg [31:0] psum_m1;
    reg [4:0] top_bit;
    integer i;
    always @* begin
        top_bit = 0;
        for (i = 0; i < 22; i = i + 1)
            if (mag_m1[i])
                top_bit = i;
    end
    wire [21:0] norm_mag =
        mag_m1 << (5'd21 - top_bit);
    wire [7:0] prod_exp =
        8'd77 + {2'd0, exp_sum_m1} + {3'd0, top_bit};
    reg [31:0] packed_product;
    always @* begin
        if (nan_m1)
            packed_product = 32'h7fc00000;
        else if (inf_m1)
            packed_product = {sign_m1, 8'hff, 23'd0};
        else if (mag_m1 == 0)
            packed_product = {sign_m1, 31'd0};
        else
            packed_product = {
                sign_m1,
                prod_exp,
                norm_mag[20:0],
                2'b00
            };
    end
    reg  [31:0] product_m2;
    reg  [31:0] psum_m2;
    wire [31:0] sum_fp32;
    kwt_pe_fp32_add u_add (
        .a (psum_m2),
        .b (product_m2),
        .y (sum_fp32)
    );
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out   <= 0;
            psum_out   <= 0;
            mag_m1     <= 0;
            exp_sum_m1 <= 0;
            sign_m1    <= 0;
            nan_m1     <= 0;
            inf_m1     <= 0;
            psum_m1    <= 0;
            product_m2 <= 0;
            psum_m2    <= 0;
        end else if (step) begin
            data_out <= data_in;
            mag_m1     <= ma * mb;
            exp_sum_m1 <= ea_eff + eb_eff;
            sign_m1    <= data_in[15] ^ weight_q[15];
            nan_m1     <= invalid_product;
            inf_m1     <= (a_inf || b_inf) && !invalid_product;
            psum_m1    <= psum_in;
            product_m2 <= packed_product;
            psum_m2    <= psum_m1;
            psum_out <= sum_fp32;
        end
    end
endmodule