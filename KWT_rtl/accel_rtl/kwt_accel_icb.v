`timescale 1ns/1ps
module kwt_accel_icb(
    input wire clk,rst_n,
    input wire s_icb_cmd_valid,output wire s_icb_cmd_ready,
    input wire [31:0] s_icb_cmd_addr,s_icb_cmd_wdata,
    input wire s_icb_cmd_read,input wire [3:0] s_icb_cmd_wmask,
    output wire s_icb_rsp_valid,input wire s_icb_rsp_ready,
    output wire [31:0] s_icb_rsp_rdata,output wire s_icb_rsp_err,
    output wire m_icb_cmd_valid,input wire m_icb_cmd_ready,
    output wire [31:0] m_icb_cmd_addr,m_icb_cmd_wdata,
    output wire m_icb_cmd_read,output wire [3:0] m_icb_cmd_wmask,
    input wire m_icb_rsp_valid,output wire m_icb_rsp_ready,
    input wire [31:0] m_icb_rsp_rdata,input wire m_icb_rsp_err,
    output wire irq
);
    wire start,busy,done,error,cfg_ok,core_rst,ls,lr,ld,le,cbusy,stage_done;
    wire [31:0] ib,ob,pb,stride,count,cycles;
    wire [7:0] error_code;wire [3:0] layer,lec;wire [4:0] stage;
    wire [1:0] valid;wire [2:0] tag0,tag1;wire release_valid,release_bank,active_bank;
    wire ae,be,we,ce,ve,xe,pe,cr,xr;
    wire [17:0] aa,ba,ca,va,xa;wire [19:0] wa,pa;
    wire [63:0] ad,bd,wd,pd;wire [255:0] cd;wire [31:0] cs;
    wire [511:0] vd,xd;wire [63:0] xs;
    wire de,dw,wl,wb,pl;wire [16:0] da;wire [31:0] dd,dq,pld;
    wire [11:0] wla;wire [63:0] wld;wire [7:0] wls;wire [9:0] pli;
    kwt_icb_cfg u_cfg(
        .clk(clk),.rst_n(rst_n),.s_icb_cmd_valid(s_icb_cmd_valid),.s_icb_cmd_ready(s_icb_cmd_ready),
        .s_icb_cmd_addr(s_icb_cmd_addr),.s_icb_cmd_read(s_icb_cmd_read),
        .s_icb_cmd_wdata(s_icb_cmd_wdata),.s_icb_cmd_wmask(s_icb_cmd_wmask),
        .s_icb_rsp_valid(s_icb_rsp_valid),.s_icb_rsp_ready(s_icb_rsp_ready),
        .s_icb_rsp_rdata(s_icb_rsp_rdata),.s_icb_rsp_err(s_icb_rsp_err),
        .run_busy(busy),.run_done(done),.run_error(error),.run_error_code(error_code),
        .run_layer(layer),.run_stage(stage),.run_cycles(cycles),.cfg_valid(cfg_ok),
        .start_pulse(start),.cfg_input_base(ib),.cfg_output_base(ob),
        .cfg_param_base(pb),.cfg_layer_stride(stride),.cfg_layer_count(count),.irq(irq));
    kwt_run u_run(
        .clk(clk),.rst_n(rst_n),.start(start),.input_base(ib),.output_base(ob),
        .param_base(pb),.layer_stride(stride),.layer_count(count),.cfg_valid(cfg_ok),
        .busy(busy),.done(done),.error(error),.error_code(error_code),.layer(layer),.cycles(cycles),
        .compute_rst_n(core_rst),.layer_start(ls),.layer_ready(lr),.layer_done(ld),
        .layer_error(le),.layer_error_code(lec),.release_valid(release_valid),.release_bank(release_bank),
        .slot_valid(valid),.tag0(tag0),.tag1(tag1),
        .act_en(de),.act_write(dw),.act_addr(da),.act_data(dd),.act_q(dq),
        .weight_load(wl),.weight_bank(wb),.weight_addr(wla),.weight_data(wld),.weight_strb(wls),
        .param_load(pl),.param_index(pli),.param_data(pld),
        .m_icb_cmd_valid(m_icb_cmd_valid),.m_icb_cmd_ready(m_icb_cmd_ready),
        .m_icb_cmd_addr(m_icb_cmd_addr),.m_icb_cmd_read(m_icb_cmd_read),
        .m_icb_cmd_wdata(m_icb_cmd_wdata),.m_icb_cmd_wmask(m_icb_cmd_wmask),
        .m_icb_rsp_valid(m_icb_rsp_valid),.m_icb_rsp_ready(m_icb_rsp_ready),
        .m_icb_rsp_rdata(m_icb_rsp_rdata),.m_icb_rsp_err(m_icb_rsp_err));
    kwt_compute_local u_core(
        .clk(clk),.rst_n(core_rst),.start_valid(ls),.start_ready(lr),.params_ready(1'b1),.param_base(20'd0),
        .busy(cbusy),.done(ld),.error(le),.error_code(lec),.stage_id(stage),.stage_done(stage_done),
        .slot_valid(valid),.tag0(tag0),.tag1(tag1),.active_bank(active_bank),
        .release_valid(release_valid),.release_bank(release_bank),
        .a_rd_en(ae),.a_rd_addr(aa),.a_rd_data(ad),.b_act_rd_en(be),.b_act_rd_addr(ba),.b_act_rd_data(bd),
        .wgt_rd_en(we),.wgt_rd_addr(wa),.wgt_rd_data(wd),
        .c_wr_en(ce),.c_wr_addr(ca),.c_wr_data(cd),.c_wr_strb(cs),.c_wr_ready(cr),
        .v_rd_en(ve),.v_rd_addr(va),.v_rd_data(vd),
        .v_wr_en(xe),.v_wr_addr(xa),.v_wr_data(xd),.v_wr_strb(xs),.v_wr_ready(xr),
        .param_rd_en(pe),.param_rd_addr(pa),.param_rd_data(pd));
    kwt_act_sram u_act(
        .clk(clk),.rst_n(rst_n),.ae(ae),.be(be),.ve(ve),.aa(aa),.ba(ba),.va(va),.ad(ad),.bd(bd),.vd(vd),
        .ce(ce),.xe(xe),.ca(ca),.xa(xa),.cd(cd),.cs(cs),.xd(xd),.xs(xs),.cr(cr),.xr(xr),
        .de(de),.dw(dw),.da(da),.dd(dd),.dq(dq));
    kwt_param_sram u_params(
        .clk(clk),.rst_n(rst_n),.we(we),.re_bank(active_bank),.wa(wa),.wd(wd),.pe(pe),.pa(pa),.pd(pd),
        .load_en(wl),.load_bank(wb),.load_addr(wla),.load_data(wld),.load_strb(wls),
        .p_load(pl),.p_index(pli),.p_data(pld));
endmodule
