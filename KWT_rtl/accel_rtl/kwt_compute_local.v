`timescale 1ns / 1ps
module kwt_compute_local (
    input wire [1:0] slot_valid,
    input wire [2:0] tag0,tag1,
    output reg active_bank,
    output wire release_valid,release_bank,
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start_valid,
    output wire         start_ready,
    input  wire         params_ready,
    input  wire [19:0]  param_base,
    output wire         busy,
    output wire         done,
    output wire         error,
    output wire [3:0]   error_code,
    output wire [4:0]   stage_id,
    output wire         stage_done,
    output wire         a_rd_en,
    output wire [17:0]  a_rd_addr,
    input  wire [63:0]  a_rd_data,
    output wire         b_act_rd_en,
    output wire [17:0]  b_act_rd_addr,
    input  wire [63:0]  b_act_rd_data,
    output wire         wgt_rd_en,
    output wire [19:0]  wgt_rd_addr,
    input  wire [63:0]  wgt_rd_data,
    output wire         c_wr_en,
    output wire [17:0]  c_wr_addr,
    output wire [255:0] c_wr_data,
    output wire [31:0]  c_wr_strb,
    input  wire         c_wr_ready,
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
    input  wire [63:0]  param_rd_data
);
    wire g_valid;
    wire g_ready;
    wire g_done;
    wire g_error;
    wire v_valid;
    wire v_ready;
    wire v_done;
    wire v_error;
    wire [255:0] g_job;
    wire [255:0] ctrl_job;
    wire ctrl_valid,array_ready;
    reg static_job;
    reg [2:0] need_role;
    always @* case(stage_id)
        0:need_role=0;2:need_role=1;4:need_role=2;
        11:need_role=3;13:need_role=4;default:need_role=5;
    endcase
    wire available=ctrl_job[183] ||
        (slot_valid[need_role[0]] && (need_role[0]?tag1:tag0)==need_role);
    assign g_valid=ctrl_valid&&available;
    assign g_ready=array_ready&&available;
    assign g_job={ctrl_job[255:58],ctrl_job[183]?ctrl_job[57:38]:20'd0,ctrl_job[37:0]};
    assign release_valid=g_done&&static_job;
    assign release_bank=active_bank;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin active_bank<=0;static_job<=0;end
        else if(g_valid&&array_ready)begin
            active_bank<=need_role[0];static_job<=!g_job[183];
        end
    wire [195:0] v_job;
    kwt_encoder_layer_ctrl_local u_ctrl (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_valid  (start_valid),
        .start_ready  (start_ready),
        .params_ready (params_ready),
        .param_base   (param_base),
        .busy         (busy),
        .done         (done),
        .error        (error),
        .error_code   (error_code),
        .stage_id     (stage_id),
        .stage_done   (stage_done),
        .gemm_valid(ctrl_valid),
        .gemm_ready   (g_ready),
        .gemm_job(ctrl_job),
        .gemm_done    (g_done),
        .gemm_error   (g_error),
        .vec_valid    (v_valid),
        .vec_ready    (v_ready),
        .vec_job      (v_job),
        .vec_done     (v_done),
        .vec_error    (v_error)
    );
    matrix_array_8x8 u_array (
        .clk           (clk),
        .rst_n         (rst_n),
        .job_valid     (g_valid),
        .job_ready(array_ready),
        .job           (g_job),
        .job_done      (g_done),
        .job_error     (g_error),
        .a_rd_en       (a_rd_en),
        .a_rd_addr     (a_rd_addr),
        .a_rd_data     (a_rd_data),
        .b_act_rd_en   (b_act_rd_en),
        .b_act_rd_addr (b_act_rd_addr),
        .b_act_rd_data (b_act_rd_data),
        .wgt_rd_en     (wgt_rd_en),
        .wgt_rd_addr   (wgt_rd_addr),
        .wgt_rd_data   (wgt_rd_data),
        .c_wr_en       (c_wr_en),
        .c_wr_addr     (c_wr_addr),
        .c_wr_data     (c_wr_data),
        .c_wr_strb     (c_wr_strb),
        .c_wr_ready    (c_wr_ready)
    );
    kwt_vector_fp16 u_vpu (
        .clk            (clk),
        .rst_n          (rst_n),
        .job_valid      (v_valid),
        .job_ready      (v_ready),
        .job            (v_job),
        .job_done       (v_done),
        .job_error      (v_error),
        .v_rd_en        (v_rd_en),
        .v_rd_addr      (v_rd_addr),
        .v_rd_data      (v_rd_data),
        .v_wr_en        (v_wr_en),
        .v_wr_addr      (v_wr_addr),
        .v_wr_data      (v_wr_data),
        .v_wr_strb      (v_wr_strb),
        .v_wr_ready     (v_wr_ready),
        .param_rd_en    (param_rd_en),
        .param_rd_addr  (param_rd_addr),
        .param_rd_data  (param_rd_data),
        .m_logits_tdata (),
        .m_logits_tvalid(),
        .m_logits_tready(1'b1),
        .m_logits_tclass(),
        .m_logits_tlast ()
    );
endmodule
