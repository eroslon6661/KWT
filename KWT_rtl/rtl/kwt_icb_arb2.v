// Two-master round-robin ICB arbiter, one outstanding command total.
// A grant is locked before a stalled command can change its owner.
module kwt_icb_arb2(input wire clk,rst_n,
    input wire u_cmd_valid,
    output wire u_cmd_ready,
    input wire [31:0] u_cmd_addr,
    input wire u_cmd_read,
    input wire [31:0] u_cmd_wdata,
    input wire [3:0] u_cmd_wmask,
    output wire u_rsp_valid,
    input wire u_rsp_ready,
    output wire [31:0] u_rsp_rdata,
    output wire u_rsp_err,
    input wire d_cmd_valid,
    output wire d_cmd_ready,
    input wire [31:0] d_cmd_addr,
    input wire d_cmd_read,
    input wire [31:0] d_cmd_wdata,
    input wire [3:0] d_cmd_wmask,
    output wire d_rsp_valid,
    input wire d_rsp_ready,
    output wire [31:0] d_rsp_rdata,
    output wire d_rsp_err,
    output wire s_cmd_valid,
    input wire s_cmd_ready,
    output wire [31:0] s_cmd_addr,
    output wire s_cmd_read,
    output wire [31:0] s_cmd_wdata,
    output wire [3:0] s_cmd_wmask,
    input wire s_rsp_valid,
    output wire s_rsp_ready,
    input wire [31:0] s_rsp_rdata,
    input wire s_rsp_err
);
    localparam IDLE=0,HOLD=1,RESPONSE=2;
    reg [1:0] state;
    reg owner,turn;
    wire selected=(state==HOLD)?owner:
        ((u_cmd_valid&&d_cmd_valid)?turn:!u_cmd_valid);
    assign s_cmd_valid=rst_n&&(state!=RESPONSE)&&(selected?d_cmd_valid:u_cmd_valid);
    assign u_cmd_ready=rst_n&&(state!=RESPONSE)&&!selected&&s_cmd_ready;
    assign d_cmd_ready=rst_n&&(state!=RESPONSE)&& selected&&s_cmd_ready;
    assign s_cmd_addr=selected?d_cmd_addr:u_cmd_addr;
    assign s_cmd_read=selected?d_cmd_read:u_cmd_read;
    assign s_cmd_wdata=selected?d_cmd_wdata:u_cmd_wdata;
    assign s_cmd_wmask=selected?d_cmd_wmask:u_cmd_wmask;
    assign s_rsp_ready=(state==RESPONSE)&&(owner?d_rsp_ready:u_rsp_ready);
    assign u_rsp_valid=(state==RESPONSE)&&!owner&&s_rsp_valid;
    assign d_rsp_valid=(state==RESPONSE)&& owner&&s_rsp_valid;
    assign u_rsp_rdata=s_rsp_rdata;assign d_rsp_rdata=s_rsp_rdata;
    assign u_rsp_err=s_rsp_err;assign d_rsp_err=s_rsp_err;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state<=IDLE;owner<=0;turn<=0;end
        else case(state)
            IDLE:if(s_cmd_valid)begin
                owner<=selected;state<=s_cmd_ready?RESPONSE:HOLD;
            end
            HOLD:if(s_cmd_valid&&s_cmd_ready)state<=RESPONSE;
            RESPONSE:if(s_rsp_valid&&s_rsp_ready)begin state<=IDLE;turn<=!owner;end
            default:state<=IDLE;
        endcase
    end
endmodule
