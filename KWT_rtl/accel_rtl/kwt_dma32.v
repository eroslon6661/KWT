`timescale 1ns/1ps
// Word-aligned, full-word stream DMA. One ICB transaction outstanding.
// Read: system memory -> rd_* stream. Write: wr_* stream -> system memory.
// job_read=1 for reads, 0 for writes; job_words counts 32-bit words.
// A producer must hold VALID and its payload until READY accepts it.
// No abort or timeout: accepted bus transactions must finish normally.
module kwt_dma32 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        job_valid,
    output wire        job_ready,
    input  wire        job_read,
    input  wire [31:0] job_addr,
    input  wire [23:0] job_words,
    output wire        busy,
    output reg         done,
    output reg         error,
    output reg  [2:0]  error_code,
    output wire        rd_valid,
    input  wire        rd_ready,
    output wire [31:0] rd_data,
    output wire        rd_last,
    input  wire        wr_valid,
    output wire        wr_ready,
    input  wire [31:0] wr_data,
    output wire        m_icb_cmd_valid,
    input  wire        m_icb_cmd_ready,
    output wire        m_icb_cmd_read,
    output wire [31:0] m_icb_cmd_addr,
    output wire [31:0] m_icb_cmd_wdata,
    output wire [3:0]  m_icb_cmd_wmask,
    input  wire        m_icb_rsp_valid,
    output wire        m_icb_rsp_ready,
    input  wire [31:0] m_icb_rsp_rdata,
    input  wire        m_icb_rsp_err
);
    localparam IDLE=2'd0, GET_WRITE=2'd1, ISSUE=2'd2, WAIT_RSP=2'd3;
    reg [1:0] state;
    reg direction_read;
    reg [31:0] address, write_data;
    reg [23:0] remaining;
    wire req_ready, rsp_valid, rsp_ready, rsp_err;
    wire [31:0] rsp_data;
    wire [32:0] last_address = {1'b0,job_addr} +
        {7'd0,job_words,2'b00} - 33'd4;

    assign job_ready = rst_n && (state == IDLE);
    assign busy = (state != IDLE);
    assign wr_ready = rst_n && (state == GET_WRITE);
    assign rd_valid = rst_n && (state == WAIT_RSP) &&
        direction_read && rsp_valid && !rsp_err;
    assign rd_data = rsp_data;
    assign rd_last = rd_valid && (remaining == 24'd1);
    assign rsp_ready = rst_n && (state == WAIT_RSP) &&
        (!direction_read || rsp_err || rd_ready);

    kwt_icb_master32 u_master (
        .clk(clk), .rst_n(rst_n),
        .req_valid(state == ISSUE), .req_ready(req_ready),
        .req_read(direction_read), .req_addr(address),
        .req_wdata(write_data), .req_wmask(4'b1111),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .rsp_rdata(rsp_data), .rsp_err(rsp_err),
        .m_icb_cmd_valid(m_icb_cmd_valid), .m_icb_cmd_ready(m_icb_cmd_ready),
        .m_icb_cmd_read(m_icb_cmd_read), .m_icb_cmd_addr(m_icb_cmd_addr),
        .m_icb_cmd_wdata(m_icb_cmd_wdata), .m_icb_cmd_wmask(m_icb_cmd_wmask),
        .m_icb_rsp_valid(m_icb_rsp_valid), .m_icb_rsp_ready(m_icb_rsp_ready),
        .m_icb_rsp_rdata(m_icb_rsp_rdata), .m_icb_rsp_err(m_icb_rsp_err)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; direction_read<=1'b1;
            address<=0; write_data<=0; remaining<=0;
            done<=0; error<=0; error_code<=0;
        end else begin
            done<=1'b0;
            error<=1'b0;
            case (state)
                IDLE: if (job_valid) begin
                    error_code<=3'd0;
                    if (job_addr[1:0]!=0) begin
                        error<=1'b1; error_code<=3'd1;
                    end else if (job_words==0) begin
                        error<=1'b1; error_code<=3'd2;
                    end else if (last_address[32]) begin
                        error<=1'b1; error_code<=3'd3;
                    end else begin
                        direction_read<=job_read;
                        address<=job_addr;
                        remaining<=job_words;
                        state<=job_read ? ISSUE : GET_WRITE;
                    end
                end
                GET_WRITE: if (wr_valid) begin
                    write_data<=wr_data;
                    state<=ISSUE;
                end
                ISSUE: if (req_ready) state<=WAIT_RSP;
                WAIT_RSP: if (rsp_valid && rsp_ready) begin
                    if (rsp_err) begin
                        error<=1'b1; error_code<=3'd4;
                        state<=IDLE;
                    end else if (remaining==24'd1) begin
                        done<=1'b1;
                        remaining<=0;
                        state<=IDLE;
                    end else begin
                        address<=address+32'd4;
                        remaining<=remaining-24'd1;
                        state<=direction_read ? ISSUE : GET_WRITE;
                    end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
