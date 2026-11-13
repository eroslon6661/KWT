`timescale 1ns / 1ps
`include "kwt1_defs.vh"
module matrix_array_8x8 #(
    parameter LAT_DIV = 1
)(
    input wire clk,
    input wire rst_n,
    input wire job_valid,
    output wire job_ready,
    output wire job_done,
    output wire job_error,
    input wire [`GEMM_JOB_W-1:0] job,
    output wire a_rd_en,
    output wire [`ACT_ADDR_W-1:0] a_rd_addr,
    input wire [63:0] a_rd_data,
    output wire b_act_rd_en,
    output wire [`ACT_ADDR_W-1:0] b_act_rd_addr,
    input wire [63:0] b_act_rd_data,
    output wire wgt_rd_en,
    output wire [`WGT_ADDR_W-1:0] wgt_rd_addr,
    input wire [63:0] wgt_rd_data,
    output wire c_wr_en,
    output wire [`ACT_ADDR_W-1:0] c_wr_addr,
    output wire [255:0] c_wr_data,
    output wire [31:0] c_wr_strb,
    input wire c_wr_ready
);
    localparam V = 3;
    localparam H = 1;
    localparam FIRST = 8 * V;
    localparam IDLE     = 0,
               CHECK    = 1,
               B_REQ    = 2,
               B_CAP    = 3,
               A_REQ    = 4,
               A_CAP    = 5,
               STEP     = 6,
               GET_C    = 7,
               ADD_BIAS = 8,
               WRITE_C  = 9,
               DONE     = 10,
               ERR      = 11;
    reg [3:0] state;
    reg [255:0] cfg;
    wire [15:0] m_len = cfg[171:156];
    wire [15:0] n_len = cfg[155:140];
    wire [15:0] k_len = cfg[139:124];
    wire [15:0] as_b = cfg[123:108];
    wire [15:0] bs_b = cfg[107:92];
    wire [15:0] cs_b = cfg[91:76];
    wire [17:0] a_base = cfg[75:58];
    wire [17:0] c_base = cfg[17:0];
    wire [19:0] b_base    = cfg[57:38];
    wire [19:0] bias_base = cfg[37:18];
    wire b_from_act = cfg[183];
    wire trans_b    = cfg[182];
    wire use_bias   = cfg[180];
    wire [31:0] a_bytes =
        ({16'd0, k_len} * 2 + 7) & 32'hfffffff8;
    wire [31:0] b_cols =
        trans_b ? {16'd0, k_len} : {16'd0, n_len};
    wire [31:0] b_rows =
        trans_b ? {16'd0, n_len} : {16'd0, k_len};
    wire [31:0] b_bytes =
        (b_cols * 2 + 7) & 32'hfffffff8;
    wire [31:0] c_bytes =
        ({16'd0, n_len} * 4 + 31) & 32'hffffffe0;
    wire [31:0] bias_bytes =
        ({16'd0, n_len} * 4 + 7) & 32'hfffffff8;
    wire [31:0] a_end =
        {14'd0, a_base} +
        ({16'd0, m_len} - 1) * as_b + a_bytes;
    wire [31:0] b_end =
        {12'd0, b_base} + (b_rows - 1) * bs_b + b_bytes;
    wire [31:0] c_end =
        {14'd0, c_base} +
        ({16'd0, m_len} - 1) * cs_b + c_bytes;
    wire [31:0] bias_end =
        {12'd0, bias_base} + bias_bytes;
    wire job_ok =
        (m_len != 0 && m_len <= 4096) &&
        (n_len != 0 && n_len <= 4096) &&
        (k_len != 0 && k_len <= 4096) &&
        cfg[187:186] == `FMT_FP16 &&
        cfg[185:184] == `FMT_FP16 &&
        !cfg[181] &&
        a_base[2:0] == 0 &&
        b_base[2:0] == 0 &&
        c_base[4:0] == 0 &&
        as_b[2:0] == 0 &&
        bs_b[2:0] == 0 &&
        cs_b[4:0] == 0 &&
        as_b >= a_bytes &&
        bs_b >= b_bytes &&
        cs_b >= c_bytes &&
        a_end <= 32'h40000 &&
        c_end <= 32'h40000 &&
        b_end <= (b_from_act ? 32'h40000 : 32'h100000) &&
        (!use_bias ||
            (bias_base[2:0] == 0 && bias_end <= 32'h100000));
    assign job_ready = (state == IDLE);
    assign job_done  = (state == DONE || state == ERR);
    assign job_error = (state == ERR);
    reg [15:0] m0;
    reg [15:0] n0;
    reg [15:0] k0;
    reg [6:0] tick;
    reg [4:0] out_row;
    reg [3:0] load_i;
    reg reading_bias;
    reg a_high;
    reg [127:0] a_vec;
    wire [15:0] m_left = m_len - m0;
    wire [6:0] rows =
        (m_left > 32) ? 7'd32 : m_left[6:0];
    wire step = (state == STEP);
    wire [31:0] load_outer = {29'd0, load_i[3:1]};
    wire [31:0] load_inner =
        load_i[0] ? 32'd4 : 32'd0;
    wire [31:0] b_address = reading_bias
        ? {12'd0, bias_base} +
          {16'd0, n0} * 4 +
          {28'd0, load_i} * 8
        : {12'd0, b_base} +
          (trans_b
            ? ({16'd0, n0} + load_outer) * bs_b +
              ({16'd0, k0} + load_inner) * 2
            : ({16'd0, k0} + load_outer) * bs_b +
              ({16'd0, n0} + load_inner) * 2);
    wire b_needed = reading_bias
        ? (n0 + {28'd0, load_i} * 2 < n_len)
        : trans_b
            ? ((n0 + load_outer < n_len) &&
               (k0 + load_inner < k_len))
            : ((k0 + load_outer < k_len) &&
               (n0 + load_inner < n_len));
    wire [63:0] b_word = b_needed
        ? ((b_from_act && !reading_bias)
            ? b_act_rd_data : wgt_rd_data)
        : 64'd0;
    assign b_act_rd_en =
        (state == B_REQ) &&
        b_needed &&
        b_from_act &&
        !reading_bias;
    assign b_act_rd_addr = b_address[17:0];
    assign wgt_rd_en =
        (state == B_REQ) &&
        b_needed &&
        (!b_from_act || reading_bias);
    assign wgt_rd_addr = b_address[19:0];
    wire [31:0] a_address =
        {14'd0, a_base} +
        ({16'd0, m0} + {25'd0, tick}) * as_b +
        {16'd0, k0} * 2 +
        (a_high ? 32'd8 : 32'd0);
    wire a_needed =
        (!a_high || k0 + 32'd4 < k_len);
    assign a_rd_en =
        (state == A_REQ) && a_needed;
    assign a_rd_addr = a_address[17:0];
    wire [15:0] east  [0:63];
    wire [31:0] south [0:63];
    genvar r, j;
    generate
        for (r = 0; r < 8; r = r + 1) begin : ROW
            wire [15:0] sample =
                (tick < rows && k0 + r < k_len)
                ? a_vec[16*r +: 16]
                : 16'd0;
            wire [15:0] row_in;
            if (r == 0) begin : DIRECT
                assign row_in = sample;
            end else begin : SKEW
                reg [15:0] pipe [0:r*V-1];
                integer i;
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        for (i = 0; i < r*V; i = i + 1)
                            pipe[i] <= 0;
                    end else if (step) begin
                        pipe[0] <= sample;
                        for (i = 1; i < r*V; i = i + 1)
                            pipe[i] <= pipe[i-1];
                    end
                end
                assign row_in = pipe[r*V-1];
            end
            for (j = 0; j < 8; j = j + 1) begin : COL
                localparam P = 8*r + j;
                wire [15:0] x;
                wire [31:0] p;
                if (j == 0)
                    assign x = row_in;
                else
                    assign x = east[P-1];
                if (r == 0)
                    assign p = 32'd0;
                else
                    assign p = south[P-8];
                wire load_pe =
                    (state == B_CAP) &&
                    !reading_bias &&
                    (trans_b
                        ? (load_i[3:1] == j &&
                           load_i[0] == r/4)
                        : (load_i[3:1] == r &&
                           load_i[0] == j/4));
                wire [15:0] w_half = trans_b
                    ? b_word[16*(r%4) +: 16]
                    : b_word[16*(j%4) +: 16];
                wire w_valid =
                    (k0 + r < k_len && n0 + j < n_len);
                pe u_pe (
                    .clk      (clk),
                    .rst      (~rst_n),
                    .step     (step),
                    .w_load   (load_pe),
                    .w_data   (w_valid ? w_half : 16'd0),
                    .data_in  (x),
                    .psum_in  (p),
                    .data_out (east[P]),
                    .psum_out (south[P])
                );
            end
        end
    endgenerate
    assign c_wr_en = (state == WRITE_C);
    wire [31:0] c_address =
        {14'd0, c_base} +
        ({16'd0, m0} + {27'd0, out_row}) * cs_b +
        {16'd0, n0} * 4;
    assign c_wr_addr = c_address[17:0];
    generate
        for (j = 0; j < 8; j = j + 1) begin : OUT_COL
            localparam START = FIRST + j*H;
            wire hit =
                step &&
                tick >= START &&
                tick < rows + START;
            wire [4:0] wr_row = tick - START;
            reg [31:0] bank [0:31];
            reg [31:0] bias_q;
            reg [31:0] result_q;
            wire [31:0] bottom = south[56+j];
            wire [4:0] rd_row =
                step ? wr_row : out_row;
            wire [31:0] acc = bank[rd_row];
            wire [31:0] sum;
            kwt_pe_fp32_add u_add (
                .a ((state == ADD_BIAS) ? result_q : acc),
                .b ((state == ADD_BIAS) ? bias_q : bottom),
                .y (sum)
            );
            always @(posedge clk) begin
                if (hit)
                    bank[wr_row] <=
                        (k0 == 0) ? bottom : sum;
                if (state == B_CAP &&
                    reading_bias &&
                    load_i == j/2)
                    bias_q <= b_word[32*(j%2) +: 32];
                if (state == GET_C)
                    result_q <= acc;
                if (state == ADD_BIAS)
                    result_q <= sum;
            end
            wire lane_valid = (n0 + j < n_len);
            assign c_wr_data[32*j +: 32] =
                lane_valid ? result_q : 32'd0;
            assign c_wr_strb[4*j +: 4] =
                {4{lane_valid}};
        end
    endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            cfg          <= 0;
            m0           <= 0;
            n0           <= 0;
            k0           <= 0;
            tick         <= 0;
            out_row      <= 0;
            load_i       <= 0;
            reading_bias <= 0;
            a_high       <= 0;
            a_vec        <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (job_valid) begin
                        cfg          <= job;
                        m0           <= 0;
                        n0           <= 0;
                        k0           <= 0;
                        tick         <= 0;
                        out_row      <= 0;
                        load_i       <= 0;
                        reading_bias <= 0;
                        a_high       <= 0;
                        state        <= CHECK;
                    end
                end
                CHECK: begin
                    state <= job_ok ? B_REQ : ERR;
                end
                B_REQ: begin
                    state <= B_CAP;
                end
                B_CAP: begin
                    if (load_i ==
                        (reading_bias ? 4'd3 : 4'd15)) begin
                        load_i       <= 0;
                        tick         <= 0;
                        a_high       <= 0;
                        state <= reading_bias ? GET_C : A_REQ;
                        reading_bias <= 0;
                    end else begin
                        load_i <= load_i + 1'b1;
                        state  <= B_REQ;
                    end
                end
                A_REQ: begin
                    state <= A_CAP;
                end
                A_CAP: begin
                    if (!a_high) begin
                        a_vec[63:0] <= a_rd_data;
                        a_high      <= 1;
                        state       <= A_REQ;
                    end else begin
                        a_vec[127:64] <=
                            a_needed ? a_rd_data : 64'd0;
                        a_high <= 0;
                        state  <= STEP;
                    end
                end
                STEP: begin
                    if (tick == rows - 1 + FIRST + 7*H) begin
                        tick   <= 0;
                        load_i <= 0;
                        if (k0 + 32'd8 < k_len) begin
                            k0    <= k0 + 16'd8;
                            state <= B_REQ;
                        end else begin
                            out_row      <= 0;
                            reading_bias <= use_bias;
                            state <= use_bias ? B_REQ : GET_C;
                        end
                    end else begin
                        tick <= tick + 1'b1;
                        if (tick + 7'd1 < rows)
                            state <= A_REQ;
                    end
                end
                GET_C: begin
                    state <= use_bias ? ADD_BIAS : WRITE_C;
                end
                ADD_BIAS: begin
                    state <= WRITE_C;
                end
                WRITE_C: begin
                    if (c_wr_ready) begin
                        if ({2'd0, out_row} + 7'd1 < rows) begin
                            out_row <= out_row + 1'b1;
                            state   <= GET_C;
                        end else begin
                            k0      <= 0;
                            load_i  <= 0;
                            out_row <= 0;
                            if (m0 + 32'd32 < m_len) begin
                                m0    <= m0 + 16'd32;
                                state <= B_REQ;
                            end else if (n0 + 32'd8 < n_len) begin
                                m0    <= 0;
                                n0    <= n0 + 16'd8;
                                state <= B_REQ;
                            end else begin
                                state <= DONE;
                            end
                        end
                    end
                end
                DONE, ERR: begin
                    state <= IDLE;
                end
                default: begin
                    state <= ERR;
                end
            endcase
        end
    end
endmodule
