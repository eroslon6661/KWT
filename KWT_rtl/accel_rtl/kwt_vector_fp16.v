`timescale 1ns / 1ps
module kwt_vector_fp16 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         job_valid,
    output wire         job_ready,
    input  wire [195:0] job,
    output wire         job_done,
    output wire         job_error,
    output wire         v_rd_en,
    output wire [17:0]  v_rd_addr,
    input  wire [511:0] v_rd_data,
    output wire         v_wr_en,
    output wire [17:0]  v_wr_addr,
    output wire [511:0] v_wr_data,
    output wire [63:0]  v_wr_strb,
    input  wire         v_wr_ready,
    output wire         param_rd_en,
    output wire [19:0]  param_rd_addr,
    input  wire [63:0]  param_rd_data,
    output wire [191:0] m_logits_tdata,
    output wire         m_logits_tvalid,
    input  wire         m_logits_tready,
    output wire [3:0]   m_logits_tclass,
    output wire         m_logits_tlast
);
    localparam IDLE      = 0,
               CHECK     = 1,
               PR        = 2,
               PC        = 3,
               LR        = 4,
               LC        = 5,
               BEGIN_ROW = 6,
               ALU       = 7,
               SFI       = 8,
               SFW       = 9,
               RED       = 10,
               SMUL      = 11,
               SADD      = 12,
               WRITE     = 13,
               NEXT_ROW  = 14,
               LOGOUT    = 15,
               DONE      = 16,
               ERR       = 17;
    reg [4:0] st;
    reg [195:0] cfg;
    wire [3:0] op = cfg[195:192];
    wire [1:0] af = cfg[191:190];
    wire [1:0] df = cfg[189:188];
    wire [1:0] bf = cfg[187:186];
    wire [15:0] rows = cfg[185:170];
    wire [15:0] cols = cfg[169:154];
    wire [15:0] astr = cfg[153:138];
    wire [15:0] dstr = cfg[137:122];
    wire [15:0] bstr = cfg[121:106];
    wire [17:0] abase = cfg[73:56];
    wire [17:0] dbase = cfg[55:38];
    wire [17:0] bbase = cfg[37:20];
    wire [19:0] pbase = cfg[19:0];
    wire need_aux = (op == 7 || op == 9);
    wire is_ln = (op == 1 || op == 9);
    wire need_param = is_ln || op == 6;
    wire [31:0] abytes =
        ({16'd0, cols} * (af == 1 ? 2 : 4) + 63) &
        32'hffffffc0;
    wire [31:0] bbytes =
        ({16'd0, cols} * (bf == 1 ? 2 : 4) + 63) &
        32'hffffffc0;
    wire [31:0] dbytes =
        ({16'd0, cols} * (df == 1 ? 2 : 4) + 63) &
        32'hffffffc0;
    wire [31:0] aend =
        {14'd0, abase} +
        ({16'd0, rows} - 1) * astr + abytes;
    wire [31:0] bend =
        {14'd0, bbase} +
        ({16'd0, rows} - 1) * bstr + bbytes;
    wire [31:0] dend =
        {14'd0, dbase} +
        ({16'd0, rows} - 1) * dstr + dbytes;
    wire [31:0] pend =
        {12'd0, pbase} + (is_ln ? 32'd520 : 32'd8);
    wire legal =
        (op == 5) ||
        (
            (op <= 7 || op == 9) &&
            rows != 0 && rows <= 4096 &&
            cols != 0 && cols <= 256 &&
            (af == 1 || af == 3) &&
            (df == 1 || df == 3) &&
            abase[5:0] == 0 &&
            astr[5:0] == 0 &&
            astr >= abytes &&
            aend <= 32'h40000 &&
            (
                op == 4 ||
                (
                    dbase[5:0] == 0 &&
                    dstr[5:0] == 0 &&
                    dstr >= dbytes &&
                    dend <= 32'h40000
                )
            ) &&
            (
                !need_aux ||
                (
                    (bf == 1 || bf == 3) &&
                    bbase[5:0] == 0 &&
                    bstr[5:0] == 0 &&
                    bstr >= bbytes &&
                    bend <= 32'h40000
                )
            ) &&
            (!is_ln || cols == 64) &&
            (
                !need_param ||
                (pbase[2:0] == 0 && pend <= 32'h100000)
            ) &&
            (op != 4 || (rows == 1 && cols == 12))
        );
    assign job_ready = st == IDLE;
    assign job_done = st == DONE || st == ERR;
    assign job_error = st == ERR;
    reg [8191:0] xb;
    reg [8191:0] yb;
    reg [8191:0] vb;
    reg [2047:0] gamma;
    reg [2047:0] beta;
    reg [31:0] epsilon;
    reg [31:0] scale;
    reg [31:0] acc;
    reg [31:0] mean;
    reg [31:0] inv;
    reg [31:0] scalar_tmp;
    reg [15:0] row;
    reg [4:0] beat;
    reg [6:0] pi;
    reg aux_load;
    reg [2:0] block_id;
    reg [6:0] phase;
    reg [8:0] ri;
    reg [2:0] reduce_kind;
    reg [3:0] best_class;
    wire [1:0] lf = aux_load ? bf : af;
    wire [31:0] lraddr =
        (aux_load ? {14'd0, bbase} : {14'd0, abase}) +
        {16'd0, row} * (aux_load ? bstr : astr) +
        {27'd0, beat} * 64;
    wire [31:0] wraddr =
        {14'd0, dbase} +
        {16'd0, row} * dstr +
        {27'd0, beat} * 64;
    wire [5:0] load_beats =
        (cols + (lf == 1 ? 31 : 15)) >>
        (lf == 1 ? 5 : 4);
    wire [5:0] store_beats =
        (cols + (df == 1 ? 31 : 15)) >>
        (df == 1 ? 5 : 4);
    wire last_block =
        ({29'd0, block_id} + 1) * 32 >= cols;
    assign v_rd_en = st == LR;
    assign v_rd_addr = lraddr[17:0];
    assign v_wr_en = st == WRITE;
    assign v_wr_addr = wraddr[17:0];
    assign param_rd_en = st == PR;
    assign param_rd_addr = pbase + {10'd0, pi, 3'd0};
    wire [1023:0] half_load;
    wire [31:0] bad_load;
    genvar g;
    generate
        for (g = 0; g < 32; g = g + 1) begin : CONVERT
            kwt_vpu_h2f ih (
                .h(v_rd_data[16*g +: 16]),
                .f(half_load[32*g +: 32])
            );
            wire [31:0] oi =
                (df == 1) ?
                ({27'd0, beat} * 32 + g) :
                ({27'd0, beat} * 16 + g/2);
            wire [31:0] of = yb[32*oi +: 32];
            wire [15:0] oh;
            kwt_vpu_f2h ohc (
                .f(of),
                .h(oh)
            );
            assign v_wr_data[16*g +: 16] =
                (oi < cols) ?
                (
                    (df == 1) ?
                    oh :
                    ((g%2 == 0) ? of[15:0] : of[31:16])
                ) :
                16'd0;
            assign v_wr_strb[2*g +: 2] =
                {2{oi < cols}};
            wire [31:0] li =
                (lf == 1) ?
                ({27'd0, beat} * 32 + g) :
                ({27'd0, beat} * 16 + g/2);
            wire [31:0] rawf =
                v_rd_data[32*(g/2) +: 32];
            assign bad_load[g] =
                (li < cols) &&
                (
                    (lf == 1) ?
                    (&v_rd_data[16*g+10 +: 5]) :
                    (&rawf[30:23])
                );
        end
    endgenerate
    wire [1023:0] work;
    wire [1023:0] alu_y;
    wire [31:0] alu_bad;
    reg [1:0] sgroup;
    reg [7:0] got;
    reg scalar_sfu;
    reg [1:0] sfop;
    wire [7:0] sf_done;
    wire [7:0] sf_bad;
    wire [255:0] sf_y;
    wire [7:0] required =
        scalar_sfu ? 8'h01 : 8'hff;
    generate
        for (g = 0; g < 8; g = g + 1) begin : SFU
            wire [31:0] sx =
                scalar_sfu ?
                scalar_tmp :
                work[32*(sgroup*8+g) +: 32];
            wire unused_busy;
            kwt_vpu_sfu us (
                .clk(clk),
                .rst_n(rst_n),
                .start(
                    st == SFI &&
                    (!scalar_sfu || g == 0)
                ),
                .op(sfop),
                .x(sx),
                .busy(unused_busy),
                .done(sf_done[g]),
                .y(sf_y[32*g +: 32])
            );
            assign sf_bad[g] =
                sf_done[g] &&
                (!scalar_sfu || g == 0) &&
                (&sf_y[32*g+23 +: 8]);
        end
    endgenerate
    generate
        for (g = 0; g < 32; g = g + 1) begin : LANE
            reg [31:0] w;
            wire [31:0] x =
                xb[1024*block_id+32*g +: 32];
            wire [31:0] y =
                yb[1024*block_id+32*g +: 32];
            wire [31:0] ga =
                gamma[1024*block_id[0]+32*g +: 32];
            wire [31:0] be =
                beta[1024*block_id[0]+32*g +: 32];
            reg [31:0] a;
            reg [31:0] b;
            reg mul;
            reg pass;
            wire [31:0] add_y;
            wire [31:0] mul_y;
            always @* begin
                a = x;
                b = 0;
                mul = 0;
                pass = 0;
                case (phase)
                    10: begin
                        a = x; b = x; mul = 1;
                    end
                    11: begin
                        a = w; b = 32'h3d372713; mul = 1;
                    end
                    12: begin
                        a = w; b = 32'h3f800000;
                    end
                    13: begin
                        a = w; b = x; mul = 1;
                    end
                    14: begin
                        a = w; b = 32'h3f4c422a; mul = 1;
                    end
                    16: begin
                        a = w; b = 32'h3f800000;
                    end
                    17: begin
                        a = w; b = 32'h3f000000; mul = 1;
                    end
                    18: begin
                        a = w; b = x; mul = 1;
                    end
                    31: begin
                        a = x;
                        b = {~acc[31], acc[30:0]};
                    end
                    33: begin
                        a = w; pass = 1;
                    end
                    35: begin
                        a = y; b = inv; mul = 1;
                    end
                    50, 62: begin
                        a = x; b = y;
                    end
                    52: begin
                        a = x;
                        b = {~mean[31], mean[30:0]};
                    end
                    53: begin
                        a = y; b = y; mul = 1;
                    end
                    55: begin
                        a = y; b = inv; mul = 1;
                    end
                    56: begin
                        a = w; b = ga; mul = 1;
                    end
                    57: begin
                        a = w; b = be;
                    end
                    60: begin
                        a = x; pass = 1;
                    end
                    61: begin
                        a = x; b = scale; mul = 1;
                    end
                endcase
            end
            kwt_pe_fp32_add ua (
                .a(a),
                .b(b),
                .y(add_y)
            );
            kwt_vpu_mul um (
                .a(a),
                .b(b),
                .y(mul_y)
            );
            assign alu_y[32*g +: 32] =
                (block_id*32 + g < cols) ?
                (pass ? a : mul ? mul_y : add_y) :
                32'd0;
            assign alu_bad[g] =
                (&alu_y[32*g+23 +: 8]);
            assign work[32*g +: 32] = w;
            always @(posedge clk) begin
                if (st == ALU)
                    w <= alu_y[32*g +: 32];
                else if (
                    st == SFW &&
                    !scalar_sfu &&
                    sgroup == g/8 &&
                    sf_done[g%8]
                )
                    w <= sf_y[32*(g%8) +: 32];
            end
        end
    endgenerate
    wire [31:0] rv =
        (reduce_kind == 2) ? yb[32*ri +: 32] :
        (reduce_kind == 3) ? vb[32*ri +: 32] :
                             xb[32*ri +: 32];
    wire [31:0] sa =
        (st == SADD) ? scalar_tmp : acc;
    wire [31:0] sb =
        (st == SADD) ? epsilon : rv;
    wire [31:0] sy;
    wire [31:0] sm;
    wire greater;
    kwt_pe_fp32_add scalar_add (
        .a(sa),
        .b(sb),
        .y(sy)
    );
    kwt_vpu_mul scalar_mul (
        .a(acc),
        .b(32'h3c800000), 
        .y(sm)
    );
    kwt_vpu_gt scalar_gt (
        .a(rv),
        .b(acc),
        .gt(greater)
    );
    generate
        for (g = 0; g < 12; g = g + 1) begin : LOGITS
            kwt_vpu_f2h ulog (
                .f(xb[32*g +: 32]),
                .h(m_logits_tdata[16*g +: 16])
            );
        end
    endgenerate
    assign m_logits_tvalid = st == LOGOUT;
    assign m_logits_tclass = best_class;
    assign m_logits_tlast = 1'b1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st          <= IDLE;
            cfg         <= 0;
            row         <= 0;
            beat        <= 0;
            pi          <= 0;
            aux_load    <= 0;
            block_id    <= 0;
            phase       <= 0;
            ri          <= 0;
            reduce_kind <= 0;
            acc         <= 0;
            mean        <= 0;
            inv         <= 0;
            scalar_tmp  <= 0;
            best_class  <= 0;
            sgroup      <= 0;
            got         <= 0;
            scalar_sfu  <= 0;
            sfop        <= 0;
        end else begin
            case (st)
                IDLE: if (job_valid) begin
                    cfg      <= job;
                    st       <= CHECK;
                    row      <= 0;
                    beat     <= 0;
                    pi       <= 0;
                    aux_load <= 0;
                end
                CHECK: begin
                    if (!legal)
                        st <= ERR;
                    else if (op == 5)
                        st <= DONE;
                    else
                        st <= need_param ? PR : LR;
                end
                PR: st <= PC;
                PC: begin
                    if (is_ln) begin
                        if (pi < 32)
                            gamma[64*pi +: 64] <= param_rd_data;
                        else if (pi < 64)
                            beta[64*(pi-32) +: 64] <= param_rd_data;
                        else
                            epsilon <= param_rd_data[31:0];
                        if (pi == 64) begin
                            if (
                                param_rd_data[31] ||
                                param_rd_data[30:23] == 0 ||
                                param_rd_data[30:23] == 255
                            )
                                st <= ERR;
                            else
                                st <= LR;
                        end else if (
                            param_rd_data[30:23] == 255 ||
                            param_rd_data[62:55] == 255
                        ) begin
                            st <= ERR;
                        end else begin
                            pi <= pi + 1'b1;
                            st <= PR;
                        end
                    end else begin
                        scale <= param_rd_data[31:0];
                        st <=
                            (param_rd_data[30:23] == 255) ?
                            ERR : LR;
                    end
                end
                LR: st <= LC;
                LC: begin
                    if (aux_load) begin
                        if (lf == 1)
                            yb[1024*beat +: 1024] <= half_load;
                        else
                            yb[512*beat +: 512] <= v_rd_data;
                    end else begin
                        if (lf == 1)
                            xb[1024*beat +: 1024] <= half_load;
                        else
                            xb[512*beat +: 512] <= v_rd_data;
                    end
                    if (|bad_load) begin
                        st <= ERR;
                    end else if (beat + 1 == load_beats) begin
                        beat <= 0;
                        if (need_aux && !aux_load) begin
                            aux_load <= 1;
                            st <= LR;
                        end else begin
                            aux_load <= 0;
                            st <= BEGIN_ROW;
                        end
                    end else begin
                        beat <= beat + 1'b1;
                        st <= LR;
                    end
                end
                BEGIN_ROW: begin
                    block_id   <= 0;
                    ri         <= 0;
                    best_class <= 0;
                    scalar_sfu <= 0;
                    case (op)
                        0: begin
                            reduce_kind <= 0;
                            acc <= 32'hff800000;
                            st <= RED;
                        end
                        1: begin
                            reduce_kind <= 1;
                            acc <= 0;
                            st <= RED;
                        end
                        2: begin
                            phase <= 10;
                            st <= ALU;
                        end
                        3: begin
                            phase <= 60;
                            st <= ALU;
                        end
                        4: begin
                            reduce_kind <= 4;
                            acc <= 32'hff800000;
                            st <= RED;
                        end
                        6: begin
                            phase <= 61;
                            st <= ALU;
                        end
                        7: begin
                            phase <= 62;
                            st <= ALU;
                        end
                        9: begin
                            phase <= 50;
                            st <= ALU;
                        end
                        default: st <= ERR;
                    endcase
                end
                ALU: begin
                    if (|alu_bad) begin
                        st <= ERR;
                    end else begin
                        case (phase)
                            10, 11, 12, 13,
                            16, 17, 55, 56:
                                phase <= phase + 1'b1;
                            14, 31: begin
                                scalar_sfu <= 0;
                                sgroup <= 0;
                                got <= 0;
                                sfop <= (phase == 14) ? 1 : 0;
                                st <= SFI;
                            end
                            18, 35, 57, 60, 61, 62: begin
                                yb[1024*block_id +: 1024] <= alu_y;
                                if (last_block) begin
                                    beat <= 0;
                                    st <= WRITE;
                                end else begin
                                    block_id <= block_id + 1'b1;
                                    if (phase == 18)
                                        phase <= 10;
                                    else if (phase == 57)
                                        phase <= 55;
                                end
                            end
                            33: begin
                                yb[1024*block_id +: 1024] <= alu_y;
                                if (last_block) begin
                                    ri <= 0;
                                    acc <= 0;
                                    reduce_kind <= 2;
                                    st <= RED;
                                end else begin
                                    block_id <= block_id + 1'b1;
                                    phase <= 31;
                                end
                            end
                            50: begin
                                xb[1024*block_id +: 1024] <= alu_y;
                                if (last_block) begin
                                    ri <= 0;
                                    acc <= 0;
                                    reduce_kind <= 1;
                                    st <= RED;
                                end else begin
                                    block_id <= block_id + 1'b1;
                                end
                            end
                            52: begin
                                yb[1024*block_id +: 1024] <= alu_y;
                                phase <= 53;
                            end
                            53: begin
                                vb[1024*block_id +: 1024] <= alu_y;
                                if (last_block) begin
                                    ri <= 0;
                                    acc <= 0;
                                    reduce_kind <= 3;
                                    st <= RED;
                                end else begin
                                    block_id <= block_id + 1'b1;
                                    phase <= 52;
                                end
                            end
                            default: st <= ERR;
                        endcase
                    end
                end
                SFI: begin
                    got <= 0;
                    st <= SFW;
                end
                SFW: begin
                    if (|sf_bad) begin
                        st <= ERR;
                    end else begin
                        got <= got | sf_done;
                        if (scalar_sfu && sf_done[0])
                            inv <= sf_y[31:0];
                        if (((got | sf_done) & required) == required) begin
                            if (scalar_sfu) begin
                                block_id <= 0;
                                phase <= (sfop == 2) ? 35 : 55;
                                st <= ALU;
                            end else if (sgroup == 3) begin
                                phase <= (sfop == 1) ? 16 : 33;
                                st <= ALU;
                            end else begin
                                sgroup <= sgroup + 1'b1;
                                st <= SFI;
                            end
                        end
                    end
                end
                RED: begin
                    if (
                        reduce_kind != 0 &&
                        reduce_kind != 4 &&
                        sy[30:23] == 255
                    ) begin
                        st <= ERR;
                    end else begin
                        if (reduce_kind == 0 || reduce_kind == 4) begin
                            if (greater) begin
                                acc <= rv;
                                best_class <= ri[3:0];
                            end
                        end else begin
                            acc <= sy;
                        end
                        if (ri + 1 == cols) begin
                            block_id <= 0;
                            case (reduce_kind)
                                0: begin
                                    phase <= 31;
                                    st <= ALU;
                                end
                                1, 3: st <= SMUL;
                                2: begin
                                    scalar_tmp <= sy;
                                    scalar_sfu <= 1;
                                    sfop <= 2;
                                    st <= SFI;
                                end
                                4: st <= LOGOUT;
                            endcase
                        end else begin
                            ri <= ri + 1'b1;
                        end
                    end
                end
                SMUL: begin
                    if (reduce_kind == 1) begin
                        mean <= sm;
                        phase <= 52;
                        st <= ALU;
                    end else begin
                        scalar_tmp <= sm;
                        st <= SADD;
                    end
                end
                SADD: begin
                    if (sy[30:23] == 255) begin
                        st <= ERR;
                    end else begin
                        scalar_tmp <= sy;
                        scalar_sfu <= 1;
                        sfop <= 3;
                        st <= SFI;
                    end
                end
                WRITE: if (v_wr_ready) begin
                    if (beat + 1 == store_beats)
                        st <= NEXT_ROW;
                    else
                        beat <= beat + 1'b1;
                end
                NEXT_ROW: begin
                    if (row + 1 == rows) begin
                        st <= DONE;
                    end else begin
                        row <= row + 1'b1;
                        beat <= 0;
                        aux_load <= 0;
                        st <= LR;
                    end
                end
                LOGOUT: if (m_logits_tready)
                    st <= DONE;
                DONE, ERR:
                    st <= IDLE;
                default:
                    st <= ERR;
            endcase
        end
    end
endmodule
