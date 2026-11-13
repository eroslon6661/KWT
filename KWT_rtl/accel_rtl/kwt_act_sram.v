`timescale 1ns/1ps
// 128 KiB: 32 x RAMSP2048X16, one synchronous port, 64 bytes per row.
// Compute operations are sequential. Read requests MUST be mutually exclusive.
// DMA uses this port only before/after all encoder layers.
module kwt_act_sram(
    input wire clk,rst_n,
    input wire ae,be,ve,
    input wire [17:0] aa,ba,va,
    output wire [63:0] ad,bd,
    output wire [511:0] vd,
    input wire ce,xe,
    input wire [17:0] ca,xa,
    input wire [255:0] cd,
    input wire [31:0] cs,
    input wire [511:0] xd,
    input wire [63:0] xs,
    output wire cr,xr,
    input wire de,dw,
    input wire [16:0] da,
    input wire [31:0] dd,
    output wire [31:0] dq
);
    wire reads=ae||be||ve;
    assign cr=rst_n&&!reads&&!xe&&!de;
    assign xr=rst_n&&!reads&&!de;
    wire cfire=ce&&cr,xfire=xe&&xr;
    wire en=rst_n&&(reads||de||cfire||xfire);
    wire we=de?dw:(cfire||xfire);
    wire [17:0] addr=ve?va:ae?aa:be?ba:de?{1'b0,da}:xfire?xa:ca;
    wire [511:0] data=de?({480'd0,dd} << {addr[5:0],3'b0}):
        xfire?xd:({256'd0,cd} << {addr[5:0],3'b0});
    wire [63:0] strb=de?(64'hf << addr[5:0]):
        xfire?xs:({32'd0,cs} << addr[5:0]);
    wire [511:0] q;
    reg [5:0] offset;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)offset<=0;
        else if(en&&!we)offset<=addr[5:0];
    wire [511:0] shifted=q >> {offset,3'b0};
    assign ad=shifted[63:0];assign bd=shifted[63:0];
    assign vd=q;assign dq=shifted[31:0];
    kwt_sram_bank #(.AW(11),.LANES(32)) u_mem(
        .clk(clk),.en(en),.we(we),.addr(addr[16:6]),
        .wdata(data),.wstrb(strb),.rdata(q));
endmodule
