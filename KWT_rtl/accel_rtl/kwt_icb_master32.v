`timescale 1ns/1ps
// One outstanding, in-order 32-bit ICB transaction bridge.
// No automatic address increment, burst, abort, or bus timeout.
// Reset must be coordinated with the interconnect / target.
module kwt_icb_master32 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire        req_read,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wmask,
    output wire        rsp_valid,
    input  wire        rsp_ready,
    output reg  [31:0] rsp_rdata,
    output reg         rsp_err,
    output wire        m_icb_cmd_valid,
    input  wire        m_icb_cmd_ready,
    output reg         m_icb_cmd_read,
    output reg  [31:0] m_icb_cmd_addr,
    output reg  [31:0] m_icb_cmd_wdata,
    output reg  [3:0]  m_icb_cmd_wmask,
    input  wire        m_icb_rsp_valid,
    output wire        m_icb_rsp_ready,
    input  wire [31:0] m_icb_rsp_rdata,
    input  wire        m_icb_rsp_err
);
    localparam IDLE=2'd0, CMD=2'd1, WAIT_RSP=2'd2, RESP=2'd3;
    reg [1:0] state;
    assign req_ready = rst_n && (state == IDLE);
    assign rsp_valid = rst_n && (state == RESP);
    assign m_icb_cmd_valid = rst_n && (state == CMD);
    // Accept a zero-latency response only with an accepted command.
    assign m_icb_rsp_ready = rst_n &&
        ((state == WAIT_RSP) || ((state == CMD) && m_icb_cmd_ready));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            m_icb_cmd_read <= 1'b1;
            m_icb_cmd_addr <= 32'd0;
            m_icb_cmd_wdata <= 32'd0;
            m_icb_cmd_wmask <= 4'd0;
            rsp_rdata <= 32'd0;
            rsp_err <= 1'b0;
        end else begin
            case (state)
                IDLE: if (req_valid) begin
                    m_icb_cmd_read <= req_read;
                    m_icb_cmd_addr <= req_addr;
                    m_icb_cmd_wdata <= req_wdata;
                    m_icb_cmd_wmask <= req_wmask;
                    state <= CMD;
                end
                CMD: if (m_icb_cmd_ready) begin
                    if (m_icb_rsp_valid) begin
                        rsp_rdata <= m_icb_rsp_rdata;
                        rsp_err <= m_icb_rsp_err;
                        state <= RESP;
                    end else state <= WAIT_RSP;
                end
                WAIT_RSP: if (m_icb_rsp_valid) begin
                    rsp_rdata <= m_icb_rsp_rdata;
                    rsp_err <= m_icb_rsp_err;
                    state <= RESP;
                end
                RESP: if (rsp_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
