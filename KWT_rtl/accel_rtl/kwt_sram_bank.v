`timescale 1ns/1ps
// LANES is a count of parallel 16-bit macros, not a runtime loop.
// SYNTHESIS: leave KWT_SRAM_BEHAV undefined and link the real macro cells.
// Simulation fallback follows sram.docx; it is NOT the vendor timing model.
module kwt_sram_bank #(
    parameter AW=11, parameter LANES=32,
    parameter [2:0] EMA_CFG=3'b010,
    parameter [1:0] EMAW_CFG=2'b00
)(
    input wire clk, en, we,
    input wire [AW-1:0] addr,
    input wire [LANES*16-1:0] wdata,
    input wire [LANES*2-1:0] wstrb,
    output wire [LANES*16-1:0] rdata
);
    genvar n;
    generate for(n=0;n<LANES;n=n+1)begin: G
        wire [15:0] mask={{8{wstrb[2*n+1]}},{8{wstrb[2*n]}}};
        wire enable=en && (!we || (|wstrb[2*n+:2]));
`ifdef KWT_SRAM_BEHAV
        reg [15:0] mem [0:(1<<AW)-1];
        reg [15:0] q;
        always @(posedge clk)if(enable)begin
            if(we)mem[addr]<=(mem[addr]&~mask)|(wdata[n*16+:16]&mask);
            else q<=mem[addr];
        end
        assign rdata[n*16+:16]=q;
`else
        if(AW==10)begin: S1024
            RAMSP1024X16 u(.CLK(clk),.CEN(~enable),.GWEN(~we),.WEN(~mask),
                .A(addr),.D(wdata[n*16+:16]),.Q(rdata[n*16+:16]),
                .EMA(EMA_CFG),.EMAW(EMAW_CFG),.RET1N(1'b1));
        end else if(AW==11)begin: S2048
            RAMSP2048X16 u(.CLK(clk),.CEN(~enable),.GWEN(~we),.WEN(~mask),
                .A(addr),.D(wdata[n*16+:16]),.Q(rdata[n*16+:16]),
                .EMA(EMA_CFG),.EMAW(EMAW_CFG),.RET1N(1'b1));
        end else if(AW==12)begin: S4096
            RAMSP4096X16 u(.CLK(clk),.CEN(~enable),.GWEN(~we),.WEN(~mask),
                .A(addr),.D(wdata[n*16+:16]),.Q(rdata[n*16+:16]),
                .EMA(EMA_CFG),.EMAW(EMAW_CFG),.RET1N(1'b1));
        end
`endif
    end endgenerate
endmodule
