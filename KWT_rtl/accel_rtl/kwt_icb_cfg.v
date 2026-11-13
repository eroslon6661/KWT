`timescale 1ns/1ps
// 32-bit ICB configuration slave. One registered response slot.
// External SoC address decode must select this peripheral's 4-KiB window.
// All register accesses use word-aligned addresses; WMASK supports byte writes.
// READ=1: read. READ=0: write. Errors return one response with RSP_ERR=1.
// Config writes and START are rejected while busy or START is pending.
// CFG_VALID is supplied by the run controller's configuration validator.
module kwt_icb_cfg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        s_icb_cmd_valid,
    output wire        s_icb_cmd_ready,
    input  wire [31:0] s_icb_cmd_addr,
    input  wire        s_icb_cmd_read,
    input  wire [31:0] s_icb_cmd_wdata,
    input  wire [3:0]  s_icb_cmd_wmask,
    output reg         s_icb_rsp_valid,
    input  wire        s_icb_rsp_ready,
    output reg  [31:0] s_icb_rsp_rdata,
    output reg         s_icb_rsp_err,
    input  wire        run_busy,
    input  wire        run_done,
    input  wire        run_error,
    input  wire [7:0]  run_error_code,
    input  wire [3:0]  run_layer,
    input  wire [4:0]  run_stage,
    input  wire [31:0] run_cycles,
    input  wire        cfg_valid,
    output reg         start_pulse,
    output reg  [31:0] cfg_input_base,
    output reg  [31:0] cfg_output_base,
    output reg  [31:0] cfg_param_base,
    output reg  [31:0] cfg_layer_stride,
    output reg  [31:0] cfg_layer_count,
    output wire        irq
);
    // 000 ID (RO)      004 CONTROL: bit0 START (W1P)
    // 008 STATUS: bit0 BUSY (RO), bit1 DONE / bit2 ERROR (W1C)
    // 00c IRQ_ENABLE: bit0
    // 010 INPUT_BASE   014 OUTPUT_BASE   018 PARAM_BASE
    // 01c LAYER_STRIDE 020 LAYER_COUNT (run controller checks 1..12)
    // 024 ERROR_CODE (RO)
    // 028 PROGRESS (RO): layer[3:0] (zero based), stage[12:8]
    // 02c RUN_CYCLES (RO)
    reg done_sticky, error_sticky, irq_enable;
    reg [7:0] error_code;
    reg [31:0] read_value;
    reg known, writable, config_reg;
    wire [11:0] offset = s_icb_cmd_addr[11:0];
    wire locked = run_busy || start_pulse;
    wire [31:0] write_mask = {
        {8{s_icb_cmd_wmask[3]}}, {8{s_icb_cmd_wmask[2]}},
        {8{s_icb_cmd_wmask[1]}}, {8{s_icb_cmd_wmask[0]}}
    };
    wire start_request = !s_icb_cmd_read && offset==12'h004 &&
        s_icb_cmd_wmask[0] && s_icb_cmd_wdata[0];
    wire access_error = !known || (offset[1:0]!=0) ||
        (!s_icb_cmd_read && !writable) ||
        (!s_icb_cmd_read && config_reg && locked) ||
        (start_request && (locked || !cfg_valid));
    assign s_icb_cmd_ready = rst_n && (!s_icb_rsp_valid || s_icb_rsp_ready);
    assign irq = irq_enable && (done_sticky || error_sticky);

    always @* begin
        read_value=32'd0;known=1'b1;writable=1'b0;config_reg=1'b0;
        case (offset)
            12'h000: read_value=32'h4b575431;
            12'h004: writable=1'b1;
            12'h008: begin
                read_value={29'd0,error_sticky,done_sticky,locked};
                writable=1'b1;
            end
            12'h00c: begin read_value={31'd0,irq_enable};writable=1'b1;end
            12'h010: begin read_value=cfg_input_base;writable=1'b1;config_reg=1'b1;end
            12'h014: begin read_value=cfg_output_base;writable=1'b1;config_reg=1'b1;end
            12'h018: begin read_value=cfg_param_base;writable=1'b1;config_reg=1'b1;end
            12'h01c: begin read_value=cfg_layer_stride;writable=1'b1;config_reg=1'b1;end
            12'h020: begin read_value=cfg_layer_count;writable=1'b1;config_reg=1'b1;end
            12'h024: read_value={24'd0,error_code};
            12'h028: read_value={19'd0,run_stage,4'd0,run_layer};
            12'h02c: read_value=run_cycles;
            default: known=1'b0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_icb_rsp_valid<=0;s_icb_rsp_rdata<=0;s_icb_rsp_err<=0;
            start_pulse<=0;
            cfg_input_base<=0;cfg_output_base<=0;cfg_param_base<=0;
            cfg_layer_stride<=0;cfg_layer_count<=32'd12;
            done_sticky<=0;error_sticky<=0;error_code<=0;irq_enable<=0;
        end else begin
            start_pulse<=1'b0;
            if (s_icb_cmd_ready) begin
                s_icb_rsp_valid<=s_icb_cmd_valid;
                if (s_icb_cmd_valid) begin
                    s_icb_rsp_err<=access_error;
                    s_icb_rsp_rdata<=(!access_error && s_icb_cmd_read) ? read_value : 32'd0;
                    if (!access_error && !s_icb_cmd_read) begin
                        case (offset)
                            12'h004: if (start_request) begin
                                start_pulse<=1'b1;
                                done_sticky<=0;error_sticky<=0;error_code<=0;
                            end
                            12'h008: if (s_icb_cmd_wmask[0]) begin
                                if (s_icb_cmd_wdata[1]) done_sticky<=0;
                                if (s_icb_cmd_wdata[2]) begin error_sticky<=0;error_code<=0;end
                            end
                            12'h00c: if (s_icb_cmd_wmask[0]) irq_enable<=s_icb_cmd_wdata[0];
                            12'h010: cfg_input_base<=(cfg_input_base & ~write_mask) | (s_icb_cmd_wdata & write_mask);
                            12'h014: cfg_output_base<=(cfg_output_base & ~write_mask) | (s_icb_cmd_wdata & write_mask);
                            12'h018: cfg_param_base<=(cfg_param_base & ~write_mask) | (s_icb_cmd_wdata & write_mask);
                            12'h01c: cfg_layer_stride<=(cfg_layer_stride & ~write_mask) | (s_icb_cmd_wdata & write_mask);
                            12'h020: cfg_layer_count<=(cfg_layer_count & ~write_mask) | (s_icb_cmd_wdata & write_mask);
                            default: begin end
                        endcase
                    end
                end
            end
            // A new event wins over a simultaneous software W1C.
            if (run_done) done_sticky<=1'b1;
            if (run_error) begin error_sticky<=1'b1;error_code<=run_error_code;end
        end
    end
endmodule
