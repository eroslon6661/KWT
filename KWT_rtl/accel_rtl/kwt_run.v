`timescale 1ns/1ps
// One input DMA, hardware layer loop, matrix prefetch, one output DMA.
// Layer image: 32-byte header, INT8 matrices at 0100/1100/2100/3100/4100/8100,
// FP32 bias/LN/attention-scale bytes at c100..cf07. Minimum stride d000.
module kwt_run(
    input wire clk,rst_n,start,
    input wire [31:0] input_base,output_base,param_base,layer_stride,layer_count,
    output wire cfg_valid,busy,
    output reg done,error,
    output reg [7:0] error_code,
    output reg [3:0] layer,
    output reg [31:0] cycles,
    output wire compute_rst_n,layer_start,
    input wire layer_ready,layer_done,layer_error,
    input wire [3:0] layer_error_code,
    input wire release_valid,release_bank,
    output reg [1:0] slot_valid,
    output reg [2:0] tag0,tag1,
    output wire act_en,act_write,
    output wire [16:0] act_addr,
    output wire [31:0] act_data,
    input wire [31:0] act_q,
    output wire weight_load,weight_bank,
    output wire [11:0] weight_addr,
    output wire [63:0] weight_data,
    output wire [7:0] weight_strb,
    output wire param_load,
    output wire [9:0] param_index,
    output wire [31:0] param_data,
    output wire m_icb_cmd_valid,input wire m_icb_cmd_ready,
    output wire m_icb_cmd_read,output wire [31:0] m_icb_cmd_addr,m_icb_cmd_wdata,
    output wire [3:0] m_icb_cmd_wmask,
    input wire m_icb_rsp_valid,output wire m_icb_rsp_ready,
    input wire [31:0] m_icb_rsp_rdata,input wire m_icb_rsp_err
);
    localparam IDLE=0,IN_REQ=1,IN_DATA=2,H_REQ=3,H_DATA=4,P_REQ=5,P_DATA=6,
        LAUNCH=7,FIND=8,W_REQ=9,W_DATA=10,W_DRAIN=11,L_WAIT=12,
        OUT_REQ=13,OUT_DATA=14,ABORT=15;
    reg [3:0] state;
    reg failed,core_finished,header_bad,dq_bad,dq_last_seen;
    reg [31:0] ip,op,pp,stride;
    reg [3:0] count;
    reg [2:0] role;
    reg [11:0] word_index,w_index;
    reg [2:0] header_index;
    reg [31:0] scale0,scale1,scale2,scale3,scale4,scale5;
    reg [1:0] out_state;
    reg [31:0] out_word;
    wire [32:0] in_end={1'b0,input_base}+33'h3180;
    wire [32:0] out_end={1'b0,output_base}+33'h3180;
    wire [35:0] p_end={4'd0,param_base}+
        {4'd0,layer_stride}*({32'd0,layer_count[3:0]}-36'd1)+36'hcf08;
    assign cfg_valid=layer_count>=1 && layer_count<=12 && layer_stride>=32'hd000 &&
        !(|{input_base[1:0],output_base[1:0],param_base[1:0],layer_stride[1:0]}) &&
        in_end<=33'h100000000 && out_end<=33'h100000000 && p_end<=36'h100000000;
    assign busy=state!=IDLE;
    assign compute_rst_n=rst_n&&!failed;
    assign layer_start=state==LAUNCH;

    reg [15:0] matrix_offset;
    always @* case(role)
        0:matrix_offset=16'h0100;1:matrix_offset=16'h1100;
        2:matrix_offset=16'h2100;3:matrix_offset=16'h3100;
        4:matrix_offset=16'h4100;default:matrix_offset=16'h8100;
    endcase
    wire [31:0] scale=role==0?scale0:role==1?scale1:role==2?scale2:
        role==3?scale3:role==4?scale4:scale5;
    wire djv=state==IN_REQ||state==H_REQ||state==P_REQ||state==W_REQ||state==OUT_REQ;
    wire [31:0] dja=state==IN_REQ?ip:state==OUT_REQ?op:state==P_REQ?pp+32'hc100:
        state==W_REQ?pp+{16'd0,matrix_offset}:pp;
    wire [23:0] djw=(state==IN_REQ||state==OUT_REQ)?24'd3168:
        state==H_REQ?24'd8:state==P_REQ?24'd898:role<4?24'd1024:24'd4096;
    wire djr,dbusy,ddone,derr,drv,drr,drl,dwr;
    wire [2:0] dec;
    wire [31:0] drd;
    kwt_dma32 u_dma(
        .clk(clk),.rst_n(rst_n),.job_valid(djv),.job_ready(djr),
        .job_read(state!=OUT_REQ),.job_addr(dja),.job_words(djw),
        .busy(dbusy),.done(ddone),.error(derr),.error_code(dec),
        .rd_valid(drv),.rd_ready(drr),.rd_data(drd),.rd_last(drl),
        .wr_valid(state==OUT_DATA&&out_state==2),.wr_ready(dwr),.wr_data(out_word),
        .m_icb_cmd_valid(m_icb_cmd_valid),.m_icb_cmd_ready(m_icb_cmd_ready),
        .m_icb_cmd_read(m_icb_cmd_read),.m_icb_cmd_addr(m_icb_cmd_addr),
        .m_icb_cmd_wdata(m_icb_cmd_wdata),.m_icb_cmd_wmask(m_icb_cmd_wmask),
        .m_icb_rsp_valid(m_icb_rsp_valid),.m_icb_rsp_ready(m_icb_rsp_ready),
        .m_icb_rsp_rdata(m_icb_rsp_rdata),.m_icb_rsp_err(m_icb_rsp_err));

    wire dq_sr,dq_mv,dq_last;
    wire [1:0] dq_err;
    assign drr=(state==W_DATA)?dq_sr:1'b1;
    kwt_weight_dequant u_dq(
        .clk(clk),.rst_n(compute_rst_n),.s_valid(drv&&state==W_DATA),.s_ready(dq_sr),
        .s_data(drd),.s_scale(scale),.s_keep(4'hf),.s_last(drl),
        .m_valid(dq_mv),.m_ready(1'b1),.m_data(weight_data),.m_strb(weight_strb),
        .m_last(dq_last),.m_error(dq_err),.m_overflow());
    assign weight_load=dq_mv&&!dq_bad&&!(|dq_err)&&!failed;
    assign weight_bank=role[0];assign weight_addr=w_index;
    assign param_load=state==P_DATA&&drv&&drr;
    assign param_index=word_index[9:0];assign param_data=drd;
    assign act_en=(state==IN_DATA&&drv&&drr)||(state==OUT_DATA&&out_state==0);
    assign act_write=state==IN_DATA;
    assign act_addr={3'd0,word_index,2'b00};assign act_data=drd;

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;failed<=0;done<=0;error<=0;error_code<=0;layer<=0;cycles<=0;
            ip<=0;op<=0;pp<=0;stride<=0;count<=0;role<=0;slot_valid<=0;tag0<=0;tag1<=0;
            word_index<=0;w_index<=0;header_index<=0;out_state<=0;out_word<=0;
            scale0<=0;scale1<=0;scale2<=0;scale3<=0;scale4<=0;scale5<=0;
            core_finished<=0;header_bad<=0;dq_bad<=0;dq_last_seen<=0;
        end else begin
            done<=0;error<=0;
            if(busy)cycles<=cycles+1;
            if(layer_done)core_finished<=1;
            if(release_valid)slot_valid[release_bank]<=0;
            if(dq_mv)begin
                w_index<=w_index+1;
                if(dq_last)dq_last_seen<=1;
                if(|dq_err)dq_bad<=1;
            end
            case(state)
                IDLE:if(start)begin
                    failed<=0;error_code<=0;cycles<=0;layer<=0;slot_valid<=0;core_finished<=0;
                    ip<=input_base;op<=output_base;pp<=param_base;stride<=layer_stride;count<=layer_count[3:0];
                    word_index<=0;
                    if(cfg_valid)state<=IN_REQ;
                    else begin failed<=1;error_code<=8'h01;state<=ABORT;end
                end
                IN_REQ:if(djr)state<=IN_DATA;
                IN_DATA:begin
                    if(drv&&drr)word_index<=word_index+1;
                    if(ddone)begin header_index<=0;header_bad<=0;state<=H_REQ;end
                end
                H_REQ:if(djr)state<=H_DATA;
                H_DATA:begin
                    if(drv&&drr)begin
                        header_index<=header_index+1;
                        case(header_index)
                            0:if(drd!=32'h4b575431)header_bad<=1;
                            1:if(drd!=32'd1)header_bad<=1;
                            2:scale0<=drd;3:scale1<=drd;4:scale2<=drd;
                            5:scale3<=drd;6:scale4<=drd;7:scale5<=drd;
                        endcase
                    end
                    if(ddone)begin
                        if(header_bad)begin failed<=1;error_code<=8'h20;state<=ABORT;end
                        else begin word_index<=0;state<=P_REQ;end
                    end
                end
                P_REQ:if(djr)state<=P_DATA;
                P_DATA:begin
                    if(drv&&drr)word_index<=word_index+1;
                    if(ddone)begin role<=0;core_finished<=0;state<=LAUNCH;end
                end
                LAUNCH:if(layer_ready)state<=FIND;
                FIND:begin
                    if(role==6)state<=L_WAIT;
                    else if(!slot_valid[role[0]])begin
                        w_index<=0;dq_bad<=0;dq_last_seen<=0;state<=W_REQ;
                    end
                end
                W_REQ:if(djr)state<=W_DATA;
                W_DATA:if(ddone)state<=W_DRAIN;
                W_DRAIN:if(dq_last_seen)begin
                    if(dq_bad)begin failed<=1;error_code<=8'h30;state<=ABORT;end
                    else begin
                        slot_valid[role[0]]<=1;
                        if(role[0])tag1<=role;else tag0<=role;
                        role<=role+1;state<=FIND;
                    end
                end
                L_WAIT:if(core_finished)begin
                    if(layer+1<count)begin
                        layer<=layer+1;pp<=pp+stride;slot_valid<=0;
                        header_index<=0;header_bad<=0;state<=H_REQ;
                    end else begin word_index<=0;out_state<=0;state<=OUT_REQ;end
                end
                OUT_REQ:if(djr)state<=OUT_DATA;
                OUT_DATA:begin
                    case(out_state)
                        0:out_state<=1;
                        1:begin out_word<=act_q;out_state<=2;end
                        2:if(dwr)begin
                            if(word_index==3167)out_state<=3;
                            else begin word_index<=word_index+1;out_state<=0;end
                        end
                    endcase
                    if(ddone)begin done<=1;state<=IDLE;end
                end
                ABORT:if(!dbusy)begin error<=1;state<=IDLE;slot_valid<=0;end
                default:begin failed<=1;error_code<=8'h7f;state<=ABORT;end
            endcase
            // Preserve the first failure. Reset compute only; NEVER cancel an ICB command.
            // During ABORT, the DMA continues draining its accepted read job.
            if(busy&&state!=ABORT&&(derr||layer_error))begin
                failed<=1;state<=ABORT;
                error_code<=derr?{5'b00010,dec}:{4'h4,layer_error_code};
            end
        end
    end
endmodule
