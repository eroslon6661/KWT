`timescale 1ns/1ps
// 64 KiB weights in two independent banks + 8 KiB FP32 parameter RAM.
// The compute controller retains logical bias/LN addresses 0x18000..0x18e07.
// Matrix weight addresses have already been translated to bank-relative offsets.
module kwt_param_sram(
    input wire clk,rst_n,
    input wire we,re_bank,
    input wire [19:0] wa,
    output wire [63:0] wd,
    input wire pe,
    input wire [19:0] pa,
    output wire [63:0] pd,
    input wire load_en,load_bank,
    input wire [11:0] load_addr,
    input wire [63:0] load_data,
    input wire [7:0] load_strb,
    input wire p_load,
    input wire [9:0] p_index,
    input wire [31:0] p_data
);
    wire bias=we&&(wa>=20'h18000);
    wire wrd=we&&!bias;
    wire pre=pe||bias;
    wire [19:0] paddr=pe?pa:wa;
    wire [63:0] q0,q1,qp;
    reg bank_d,bias_d;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin bank_d<=0;bias_d<=0;end
        else if(we)begin bank_d<=re_bank;bias_d<=bias;end
    assign wd=bias_d?qp:(bank_d?q1:q0);
    assign pd=qp;
    kwt_sram_bank #(.AW(12),.LANES(4)) u_w0(
        .clk(clk),.en(rst_n&&((load_en&&!load_bank)||(wrd&&!re_bank))),
        .we(load_en&&!load_bank),.addr(load_en&&!load_bank?load_addr:wa[14:3]),
        .wdata(load_data),.wstrb(load_strb),.rdata(q0));
    kwt_sram_bank #(.AW(12),.LANES(4)) u_w1(
        .clk(clk),.en(rst_n&&((load_en&&load_bank)||(wrd&&re_bank))),
        .we(load_en&&load_bank),.addr(load_en&&load_bank?load_addr:wa[14:3]),
        .wdata(load_data),.wstrb(load_strb),.rdata(q1));
    kwt_sram_bank #(.AW(10),.LANES(4)) u_p(
        .clk(clk),.en(rst_n&&(p_load||pre)),.we(p_load),
        .addr(p_load?{1'b0,p_index[9:1]}:{1'b0,paddr[11:3]}),
        .wdata(p_index[0]?{p_data,32'd0}:{32'd0,p_data}),
        .wstrb(p_index[0]?8'hf0:8'h0f),.rdata(qp));
endmodule
