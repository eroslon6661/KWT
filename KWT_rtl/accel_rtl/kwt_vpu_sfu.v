`timescale 1ns / 1ps
module kwt_vpu_sfu (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [1:0]  op,
    input  wire [31:0] x,
    output wire        busy,
    output reg         done,
    output reg  [31:0] y
);
    localparam IDLE  = 0,
               EX_T  = 1,
               EX_N  = 2,
               EX_L  = 3,
               EX_F  = 4,
               EX_M  = 5,
               EX_A  = 6,
               EX_OUT = 7,
               T_DEN = 8,
               R_M   = 9,
               R_SUB = 10,
               R_UP  = 11,
               T_M   = 12,
               T_TWO = 13,
               T_OUT = 14,
               W_SQ  = 15,
               W_X   = 16,
               W_HALF = 17,
               W_SUB = 18,
               W_UP  = 19;
    reg [4:0] st;
    reg [31:0] z, t, f, p, tmp;
    reg [31:0] base, r, evalue;
    reg [6:0] n;
    reg [3:0] degree;
    reg [2:0] iter;
    reg tan_mode;
    reg neg;
    reg [31:0] ma, mb;
    reg [31:0] aa, ab;
    reg [31:0] coef;
    wire [31:0] my, ay;
    kwt_vpu_mul um (
        .a(ma),
        .b(mb),
        .y(my)
    );
    kwt_pe_fp32_add ua (
        .a(aa),
        .b(ab),
        .y(ay)
    );
    assign busy = st != IDLE;
    wire [23:0] tmag = {1'b1, t[22:0]};
    wire [23:0] nmag =
        (t[30:23] < 127) ?
        24'd0 :
        tmag >> (150 - t[30:23]);
    wire [6:0] nz = n;
    wire [2:0] nt =
        nz[6] ? 3'd6 :
        nz[5] ? 3'd5 :
        nz[4] ? 3'd4 :
        nz[3] ? 3'd3 :
        nz[2] ? 3'd2 :
        nz[1] ? 3'd1 :
                3'd0;
    wire [23:0] nm = {17'd0, nz} << (23 - nt);
    wire [7:0] ne = 8'd127 + nt;
    wire [31:0] nf =
        (n == 0) ? 32'd0 : {1'b0, ne, nm[22:0]};
    wire signed [9:0] scaled_exp =
        $signed({2'b0, p[30:23]}) -
        $signed({3'b0, n});
    wire [31:0] ex_result =
        (scaled_exp <= 0) ?
        32'd0 :
        {1'b0, scaled_exp[7:0], p[22:0]};
    always @* begin
        case (degree)
            7: coef = 32'h39500d01; 
            6: coef = 32'h3ab60b61; 
            5: coef = 32'h3c088889; 
            4: coef = 32'h3d2aaaab; 
            3: coef = 32'h3e2aaaab; 
            2: coef = 32'h3f000000; 
            default: coef = 32'h3f800000;
        endcase
        ma = 0;
        mb = 0;
        aa = 0;
        ab = 0;
        case (st)
            EX_T: begin
                ma = z;
                mb = 32'h3fb8aa3b;
            end
            EX_L: begin
                ma = nf;
                mb = 32'h3f317218;
            end
            EX_F: begin
                aa = z;
                ab = tmp;
            end
            EX_M: begin
                ma = p;
                mb = f;
            end
            EX_A: begin
                aa = tmp;
                ab = coef;
            end
            T_DEN: begin
                aa = evalue;
                ab = 32'h3f800000;
            end
            R_M: begin
                ma = base;
                mb = r;
            end
            R_SUB: begin
                aa = 32'h40000000;
                ab = {~tmp[31], tmp[30:0]};
            end
            R_UP: begin
                ma = r;
                mb = tmp;
            end
            T_M: begin
                ma = evalue;
                mb = r;
            end
            T_TWO: begin
                ma = tmp;
                mb = 32'h40000000;
            end
            T_OUT: begin
                aa = 32'h3f800000;
                ab = {~tmp[31], tmp[30:0]};
            end
            W_SQ: begin
                ma = r;
                mb = r;
            end
            W_X: begin
                ma = base;
                mb = tmp;
            end
            W_HALF: begin
                ma = tmp;
                mb = 32'h3f000000;
            end
            W_SUB: begin
                aa = 32'h3fc00000;
                ab = {~tmp[31], tmp[30:0]};
            end
            W_UP: begin
                ma = r;
                mb = tmp;
            end
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st       <= IDLE;
            done     <= 0;
            y        <= 0;
            tan_mode <= 0;
            neg      <= 0;
        end else begin
            done <= 0;
            case (st)
                IDLE: if (start) begin
                    tan_mode <= op == 1;
                    neg      <= x[31];
                    iter     <= 0;
                    if (
                        x[30:23] == 255 ||
                        ((op == 2 || op == 3) &&
                         (x[31] || x[30:23] == 0))
                    ) begin
                        y    <= 32'h7fc00000;
                        done <= 1;
                    end else if (
                        op == 0 &&
                        x[31] &&
                        x[30:0] > 31'h42a00000
                    ) begin
                        y    <= 0;
                        done <= 1;
                    end else if (
                        op == 0 &&
                        !x[31] &&
                        x[30:0] != 0
                    ) begin
                        y    <= 32'h7fc00000;
                        done <= 1;
                    end else if (
                        op == 1 &&
                        x[30:0] >= 31'h41100000
                    ) begin
                        y    <= {x[31], 31'h3f800000};
                        done <= 1;
                    end else if (
                        op == 1 && x[30:0] == 0
                    ) begin
                        y    <= x;
                        done <= 1;
                    end else if (op == 0 || op == 1) begin
                        if (op == 1 && x[30:23] < 115) begin
                            y    <= x;
                            done <= 1;
                        end else begin
                            z <= (op == 1) ?
                                {
                                    1'b1,
                                    (x[30:23] + 8'd1),
                                    x[22:0]
                                } : x;
                            st <= EX_T;
                        end
                    end else begin
                        base <= x;
                        r <= (op == 2) ?
                            (32'h7ef311c3 - x) :
                            (32'h5f3759df - (x >> 1));
                        st <= (op == 2) ? R_M : W_SQ;
                    end
                end
                EX_T: begin
                    t  <= my;
                    st <= EX_N;
                end
                EX_N: begin
                    n  <= nmag[6:0];
                    st <= EX_L;
                end
                EX_L: begin
                    tmp <= my;
                    st  <= EX_F;
                end
                EX_F: begin
                    f      <= ay;
                    p      <= 32'h37d00d01; 
                    degree <= 7;
                    st     <= EX_M;
                end
                EX_M: begin
                    tmp <= my;
                    st  <= EX_A;
                end
                EX_A: begin
                    p <= ay;
                    if (degree == 0)
                        st <= EX_OUT;
                    else begin
                        degree <= degree - 1'b1;
                        st     <= EX_M;
                    end
                end
                EX_OUT: begin
                    if (tan_mode) begin
                        evalue <= ex_result;
                        st     <= T_DEN;
                    end else begin
                        y    <= ex_result;
                        done <= 1;
                        st   <= IDLE;
                    end
                end
                T_DEN: begin
                    base <= ay;
                    r    <= 32'h7ef311c3 - ay;
                    iter <= 0;
                    st   <= R_M;
                end
                R_M: begin
                    tmp <= my;
                    st  <= R_SUB;
                end
                R_SUB: begin
                    tmp <= ay;
                    st  <= R_UP;
                end
                R_UP: begin
                    r <= my;
                    if (iter == 3) begin
                        if (tan_mode)
                            st <= T_M;
                        else begin
                            y    <= my;
                            done <= 1;
                            st   <= IDLE;
                        end
                    end else begin
                        iter <= iter + 1'b1;
                        st   <= R_M;
                    end
                end
                T_M: begin
                    tmp <= my;
                    st  <= T_TWO;
                end
                T_TWO: begin
                    tmp <= my;
                    st  <= T_OUT;
                end
                T_OUT: begin
                    y    <= {neg, ay[30:0]};
                    done <= 1;
                    st   <= IDLE;
                end
                W_SQ: begin
                    tmp <= my;
                    st  <= W_X;
                end
                W_X: begin
                    tmp <= my;
                    st  <= W_HALF;
                end
                W_HALF: begin
                    tmp <= my;
                    st  <= W_SUB;
                end
                W_SUB: begin
                    tmp <= ay;
                    st  <= W_UP;
                end
                W_UP: begin
                    r <= my;
                    if (iter == 3) begin
                        y    <= my;
                        done <= 1;
                        st   <= IDLE;
                    end else begin
                        iter <= iter + 1'b1;
                        st   <= W_SQ;
                    end
                end
                default: st <= IDLE;
            endcase
        end
    end
endmodule
