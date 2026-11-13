`timescale 1ns/1ps
// 256 KiB TCM from the supplied RAMSP4096X16 macros.
// Supported configurations: 32768 x 64 (ITCM), 65536 x 32 (DTCM).
// ADDRESS is a word address. WEM is an active-high byte write mask.
// RSTN resets read-bank selection only; SRAM contents are not reset.
module kwt_tcm_4096x16 #(
    parameter WORD_WIDTH = 64,
    parameter WORD_ADDR_WIDTH = 15
)(
    input wire CLK,
    input wire RSTN,
    input wire [WORD_ADDR_WIDTH-1:0] ADDRESS,
    input wire CS,
    input wire WE,
    input wire [WORD_WIDTH/8-1:0] WEM,
    input wire [WORD_WIDTH-1:0] WDATA,
    output wire [WORD_WIDTH-1:0] RDATA
);
    localparam BANK_BITS = WORD_ADDR_WIDTH - 12;
    localparam BANKS = 1 << BANK_BITS;
    localparam LANES = WORD_WIDTH / 16;
    wire [BANK_BITS-1:0] bank = ADDRESS[WORD_ADDR_WIDTH-1:12];
    reg [BANK_BITS-1:0] read_bank;
    wire [WORD_WIDTH-1:0] bank_data [0:BANKS-1];

    always @(posedge CLK or negedge RSTN)
        if (!RSTN) read_bank <= {BANK_BITS{1'b0}};
        else if (CS && !WE) read_bank <= bank;

    genvar b, l;
    generate
        for (b=0; b<BANKS; b=b+1) begin: BANK
            for (l=0; l<LANES; l=l+1) begin: LANE
                wire selected = CS && (bank == b) &&
                    (!WE || (|WEM[2*l+:2]));
                wire [15:0] bit_mask =
                    {{8{WEM[2*l+1]}}, {8{WEM[2*l]}}};
                RAMSP4096X16 u_sram (
                    .CLK(CLK), .CEN(~selected), .GWEN(~WE),
                    .WEN(~bit_mask), .A(ADDRESS[11:0]),
                    .D(WDATA[16*l+:16]), .Q(bank_data[b][16*l+:16]),
                    .EMA(3'b010), .EMAW(2'b00), .RET1N(1'b1)
                );
            end
        end
    endgenerate
    assign RDATA = bank_data[read_bank];
endmodule
