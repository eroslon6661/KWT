`timescale 1ns / 1ps
`timescale 1ns/1ps
module kwt_weight_dequant (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [31:0] s_data,
    input  wire [3:0]  s_keep,
    input  wire        s_last,
    input  wire [31:0] s_scale,
    output wire        m_valid,
    input  wire        m_ready,
    output reg  [63:0] m_data,
    output reg  [7:0]  m_strb,
    output reg         m_last,
    output reg  [1:0]  m_error,
    output reg  [3:0]  m_overflow
);
    reg v1;
    reg v2;
    reg v3;
    wire r3 = !v3 || m_ready;
    wire r2 = !v2 || r3;
    wire r1 = !v1 || r2;
    assign s_ready = rst_n && r1;
    assign m_valid = v3;
    wire scale_ok =
        !s_scale[31] &&
        (s_scale[30:23] != 8'd0) &&
        (s_scale[30:23] != 8'hff);
    wire bad_input =
        !scale_ok || (s_keep == 4'd0);
    wire [23:0] sig = {1'b1, s_scale[22:0]};
    wire [7:0] q0 = s_data[7:0];
    wire [7:0] q1 = s_data[15:8];
    wire [7:0] q2 = s_data[23:16];
    wire [7:0] q3 = s_data[31:24];
    wire [7:0] a0 = q0[7] ? (~q0 + 8'd1) : q0;
    wire [7:0] a1 = q1[7] ? (~q1 + 8'd1) : q1;
    wire [7:0] a2 = q2[7] ? (~q2 + 8'd1) : q2;
    wire [7:0] a3 = q3[7] ? (~q3 + 8'd1) : q3;
    wire [31:0] p0 = a0 * sig;
    wire [31:0] p1 = a1 * sig;
    wire [31:0] p2 = a2 * sig;
    wire [31:0] p3 = a3 * sig;
    reg [31:0] p0_r;
    reg [31:0] p1_r;
    reg [31:0] p2_r;
    reg [31:0] p3_r;
    reg [7:0] exp_r;
    reg [3:0] sign_r;
    reg [3:0] keep1;
    reg       last1;
    reg       bad1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1     <= 1'b0;
            p0_r   <= 32'd0;
            p1_r   <= 32'd0;
            p2_r   <= 32'd0;
            p3_r   <= 32'd0;
            exp_r  <= 8'd0;
            sign_r <= 4'd0;
            keep1  <= 4'd0;
            last1  <= 1'b0;
            bad1   <= 1'b0;
        end
        else if (r1) begin
            v1 <= s_valid;
            if (s_valid) begin
                p0_r <= (s_keep[0] && !bad_input)
                        ? p0 : 32'd0;
                p1_r <= (s_keep[1] && !bad_input)
                        ? p1 : 32'd0;
                p2_r <= (s_keep[2] && !bad_input)
                        ? p2 : 32'd0;
                p3_r <= (s_keep[3] && !bad_input)
                        ? p3 : 32'd0;
                exp_r <= s_scale[30:23];
                sign_r <= {
                    q3[7], q2[7], q1[7], q0[7]
                };
                keep1 <= s_keep;
                last1 <= s_last;
                bad1  <= bad_input;
            end
        end
    end
    wire [31:0] f0;
    wire [31:0] f1;
    wire [31:0] f2;
    wire [31:0] f3;
    kwt_dequant_fp32_pack u_pack0 (
        .product   (p0_r),
        .sign      (sign_r[0]),
        .scale_exp (exp_r),
        .fp32      (f0)
    );
    kwt_dequant_fp32_pack u_pack1 (
        .product   (p1_r),
        .sign      (sign_r[1]),
        .scale_exp (exp_r),
        .fp32      (f1)
    );
    kwt_dequant_fp32_pack u_pack2 (
        .product   (p2_r),
        .sign      (sign_r[2]),
        .scale_exp (exp_r),
        .fp32      (f2)
    );
    kwt_dequant_fp32_pack u_pack3 (
        .product   (p3_r),
        .sign      (sign_r[3]),
        .scale_exp (exp_r),
        .fp32      (f3)
    );
    reg [31:0] f0_r;
    reg [31:0] f1_r;
    reg [31:0] f2_r;
    reg [31:0] f3_r;
    reg [3:0] keep2;
    reg       last2;
    reg       bad2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v2    <= 1'b0;
            f0_r  <= 32'd0;
            f1_r  <= 32'd0;
            f2_r  <= 32'd0;
            f3_r  <= 32'd0;
            keep2 <= 4'd0;
            last2 <= 1'b0;
            bad2  <= 1'b0;
        end
        else if (r2) begin
            v2 <= v1;
            if (v1) begin
                f0_r <= f0;
                f1_r <= f1;
                f2_r <= f2;
                f3_r <= f3;
                keep2 <= keep1;
                last2 <= last1;
                bad2  <= bad1;
            end
        end
    end
    wire [15:0] h0;
    wire [15:0] h1;
    wire [15:0] h2;
    wire [15:0] h3;
    kwt_vpu_f2h u_half0 (
        .f (f0_r),
        .h (h0)
    );
    kwt_vpu_f2h u_half1 (
        .f (f1_r),
        .h (h1)
    );
    kwt_vpu_f2h u_half2 (
        .f (f2_r),
        .h (h2)
    );
    kwt_vpu_f2h u_half3 (
        .f (f3_r),
        .h (h3)
    );
    wire [3:0] overflow_bits = {
        !bad2 && keep2[3] && (h3[14:10] == 5'h1f),
        !bad2 && keep2[2] && (h2[14:10] == 5'h1f),
        !bad2 && keep2[1] && (h1[14:10] == 5'h1f),
        !bad2 && keep2[0] && (h0[14:10] == 5'h1f)
    };
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v3         <= 1'b0;
            m_data     <= 64'd0;
            m_strb     <= 8'd0;
            m_last     <= 1'b0;
            m_error    <= 2'd0;
            m_overflow <= 4'd0;
        end
        else if (r3) begin
            v3 <= v2;
            if (v2) begin
                m_data <= bad2 ? 64'd0 : {
                    keep2[3] ? h3 : 16'd0,
                    keep2[2] ? h2 : 16'd0,
                    keep2[1] ? h1 : 16'd0,
                    keep2[0] ? h0 : 16'd0
                };
                m_strb <= {
                    keep2[3], keep2[3],
                    keep2[2], keep2[2],
                    keep2[1], keep2[1],
                    keep2[0], keep2[0]
                };
                m_last <= last2;
                m_error <= {
                    (|overflow_bits),
                    bad2
                };
                m_overflow <= overflow_bits;
            end
        end
    end
endmodule
