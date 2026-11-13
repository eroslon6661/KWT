// One outstanding ICB command. Invalid addresses receive a registered error.
// The hit bit is retained until response handshake; response data never depend
// on the next command address. No arithmetic or model-data changes are made.
module kwt_icb_window #(
    parameter [31:0] BASE = 32'h11000000,
    parameter [31:0] MASK = 32'hfffff000
)(
    input wire clk, rst_n,
    input wire i_cmd_valid, output wire i_cmd_ready,
    input wire [31:0] i_cmd_addr, input wire i_cmd_read,
    input wire [31:0] i_cmd_wdata, input wire [3:0] i_cmd_wmask,
    output wire i_rsp_valid, input wire i_rsp_ready,
    output wire [31:0] i_rsp_rdata, output wire i_rsp_err,
    output wire o_cmd_valid, input wire o_cmd_ready,
    output wire [31:0] o_cmd_addr, output wire o_cmd_read,
    output wire [31:0] o_cmd_wdata, output wire [3:0] o_cmd_wmask,
    input wire o_rsp_valid, output wire o_rsp_ready,
    input wire [31:0] o_rsp_rdata, input wire o_rsp_err,
    output wire invalid_access
);
    reg busy, selected;
    wire hit = (i_cmd_addr & MASK) == BASE;
    assign i_cmd_ready = rst_n && !busy && (!hit || o_cmd_ready);
    assign o_cmd_valid = rst_n && !busy && hit && i_cmd_valid;
    assign o_cmd_addr = i_cmd_addr;
    assign o_cmd_read = i_cmd_read;
    assign o_cmd_wdata = i_cmd_wdata;
    assign o_cmd_wmask = i_cmd_wmask;
    assign i_rsp_valid = rst_n && busy && (!selected || o_rsp_valid);
    assign i_rsp_rdata = selected ? o_rsp_rdata : 32'b0;
    assign i_rsp_err = !selected || o_rsp_err;
    assign o_rsp_ready = rst_n && busy && selected && i_rsp_ready;
    assign invalid_access = i_cmd_valid && i_cmd_ready && !hit;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin busy <= 1'b0; selected <= 1'b0; end
        else if (i_cmd_valid && i_cmd_ready) begin busy <= 1'b1; selected <= hit; end
        else if (i_rsp_valid && i_rsp_ready) busy <= 1'b0;
    end
endmodule
