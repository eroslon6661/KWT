`timescale 1ns / 1ps
module kwt_encoder_layer_ctrl_local (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start_valid,
    output wire         start_ready,
    input  wire         params_ready,
    input  wire [19:0]  param_base,
    output wire         busy,
    output wire         done,
    output wire         error,
    output reg  [3:0]   error_code,
    output reg  [4:0]   stage_id,
    output wire         stage_done,
    output wire         gemm_valid,
    input  wire         gemm_ready,
    output reg  [255:0] gemm_job,
    input  wire         gemm_done,
    input  wire         gemm_error,
    output wire         vec_valid,
    input  wire         vec_ready,
    output reg  [195:0] vec_job,
    input  wire         vec_done,
    input  wire         vec_error
);
    localparam IDLE     = 3'd0,
               CHECK    = 3'd1,
               ISSUE    = 3'd2,
               WAIT_JOB = 3'd3,
               NEXT_JOB = 3'd4,
               FINISH   = 3'd5,
               FAULT    = 3'd6;
    reg [2:0]  state;
    reg [19:0] base_r;
    reg        is_vec;
    wire [20:0] param_end =
        {1'b0, base_r} + 21'h18e08;
    wire config_ok =
        (base_r[2:0] == 3'b000) &&
        (param_end <= 21'h100000);
    assign start_ready =
        rst_n && (state == IDLE) && params_ready;
    assign busy       = (state != IDLE);
    assign done       = (state == FINISH);
    assign error      = (state == FAULT);
    assign stage_done = (state == NEXT_JOB);
    assign gemm_valid =
        rst_n && (state == ISSUE) && !is_vec;
    assign vec_valid =
        rst_n && (state == ISSUE) && is_vec;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            base_r     <= 20'd0;
            stage_id   <= 5'd0;
            error_code <= 4'd0;
        end
        else begin
            case (state)
                IDLE: begin
                    if (start_valid && start_ready) begin
                        base_r     <= param_base;
                        stage_id   <= 5'd0;
                        error_code <= 4'd0;
                        state      <= CHECK;
                    end
                end
                CHECK: begin
                    if (config_ok) begin
                        state <= ISSUE;
                    end
                    else begin
                        error_code <= 4'd1;
                        state      <= FAULT;
                    end
                end
                ISSUE: begin
                    if ((!is_vec && gemm_ready) ||
                        ( is_vec && vec_ready)) begin
                        state <= WAIT_JOB;
                    end
                end
                WAIT_JOB: begin
                    if ((!is_vec && gemm_error) ||
                        ( is_vec && vec_error)) begin
                        error_code <= is_vec ? 4'd3 : 4'd2;
                        state      <= FAULT;
                    end
                    else if ((!is_vec && gemm_done) ||
                             ( is_vec && vec_done)) begin
                        state <= NEXT_JOB;
                    end
                end
                NEXT_JOB: begin
                    if (stage_id == 5'd16) begin
                        state <= FINISH;
                    end
                    else begin
                        stage_id <= stage_id + 5'd1;
                        state    <= ISSUE;
                    end
                end
                FINISH, FAULT: begin
                    state <= IDLE;
                end
                default: begin
                    error_code <= 4'd4;
                    state      <= FAULT;
                end
            endcase
        end
    end
    reg [17:0] ga;
    reg [17:0] gc;
    reg [19:0] gb;
    reg [19:0] gbias;
    reg [15:0] gn;
    reg [15:0] gk;
    reg [15:0] gas;
    reg [15:0] gbs;
    reg [15:0] gcs;
    reg g_bias;
    reg g_trans;
    reg g_act;
    reg [3:0] vo;
    reg [1:0] vdf;
    reg [15:0] vn;
    reg [15:0] vas;
    reg [15:0] vds;
    reg [17:0] va;
    reg [17:0] vd;
    reg [17:0] vb;
    reg [19:0] vp;
    always @* begin
        is_vec=0;
        ga=18'h00000;gb=base_r;gc=18'h10000;gbias=0;
        gn=64;gk=64;gas=128;gbs=128;gcs=256;
        g_bias=0;g_trans=0;g_act=0;
        vo=3;vdf=1;vn=64;vas=256;vds=128;
        va=18'h10000;vd=18'h04000;vb=0;vp=0;
        case(stage_id)
          0: gb=base_r;
          1: is_vec=1;
          2: gb=base_r+20'h02000;
          3: begin is_vec=1;vd=18'h08000;end
          4: gb=base_r+20'h04000;
          5: begin is_vec=1;vd=18'h0c000;end
          6: begin ga=18'h04000;gb=20'h08000;gn=99;gcs=512;g_trans=1;g_act=1;end
          7: begin is_vec=1;vo=6;vdf=3;vn=99;vd=18'h10000;vas=512;vds=512;vp=base_r+20'h18e00;end
          8: begin is_vec=1;vo=0;vn=99;vd=18'h10000;vas=512;vds=256;end
          9: begin ga=18'h10000;gb=20'h0c000;gc=18'h04000;gk=99;gas=256;g_act=1;end
          10: begin is_vec=1;va=18'h04000;vd=18'h04000;end
          11: begin ga=18'h04000;gb=base_r+20'h06000;gbias=base_r+20'h18000;g_bias=1;end
          12: begin is_vec=1;vo=9;vd=0;vp=base_r+20'h18600;end
          13: begin gb=base_r+20'h08000;gc=18'h04000;gbias=base_r+20'h18100;g_bias=1;gn=256;gbs=512;gcs=1024;end
          14: begin is_vec=1;vo=2;vn=256;va=18'h04000;vd=18'h04000;vas=1024;vds=512;end
          15: begin ga=18'h04000;gb=base_r+20'h10000;gc=18'h12000;gbias=base_r+20'h18500;g_bias=1;gk=256;gas=512;end
          16: begin is_vec=1;vo=9;va=18'h12000;vb=0;vd=0;vp=base_r+20'h18a00;end
          default: begin end
        endcase

        gemm_job = 256'd0;
        gemm_job[17:0]    = gc;
        gemm_job[37:18]   = gbias;
        gemm_job[57:38]   = gb;
        gemm_job[75:58]   = ga;
        gemm_job[91:76]   = gcs;
        gemm_job[107:92]  = gbs;
        gemm_job[123:108] = gas;
        gemm_job[139:124] = gk;
        gemm_job[155:140] = gn;
        gemm_job[171:156] = 16'd99;
        gemm_job[180] = g_bias;
        gemm_job[181] = 1'b0;       
        gemm_job[182] = g_trans;
        gemm_job[183] = g_act;
        gemm_job[185:184] = 2'd1;  
        gemm_job[187:186] = 2'd1;  
        vec_job = 196'd0;
        vec_job[19:0]  = vp;
        vec_job[37:20] = vb;
        vec_job[55:38] = vd;
        vec_job[73:56] = va;
        vec_job[121:106] = 16'd128;
        vec_job[137:122] = vds;
        vec_job[153:138] = vas;
        vec_job[169:154] = vn;
        vec_job[185:170] = 16'd99;
        vec_job[187:186] = 2'd1;   
        vec_job[189:188] = vdf;
        vec_job[191:190] = 2'd3;   
        vec_job[195:192] = vo;
    end
endmodule
