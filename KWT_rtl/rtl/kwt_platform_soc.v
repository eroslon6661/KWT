// Main-domain platform integration for functional verification and RTL review.
// Preserves real CPU/PPI/MEM/CLINT/PLIC/peripheral logic. AON/debug are inactive.
// ITCM simulation preload is a TB operation; no boot ROM/Flash/pad-ring claim.
// External SysMem target: A0000000..A007FFFF. Its implementation is external.
`include "e203_defines.v"
module kwt_platform_soc(
    input wire clk, rst_n, test_mode,
    output wire irq, cpu_irq, bus_clk, bus_rst_n,
    output wire [31:0] inspect_pc,
    output wire unexpected_bus,
    // External functional loader; shares the platform MEM fabric with CPU/DMA.
    input wire l_cmd_valid,
    output wire l_cmd_ready,
    input wire [31:0] l_cmd_addr,
    input wire l_cmd_read,
    input wire [31:0] l_cmd_wdata,
    input wire [3:0] l_cmd_wmask,
    output wire l_rsp_valid,
    input wire l_rsp_ready,
    output wire [31:0] l_rsp_rdata,
    output wire l_rsp_err,
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
wire p_cmd_valid;
wire p_cmd_ready;
wire [31:0] p_cmd_addr;
wire p_cmd_read;
wire [31:0] p_cmd_wdata;
wire [3:0] p_cmd_wmask;
wire p_rsp_valid;
wire p_rsp_ready;
wire [31:0] p_rsp_rdata;
wire p_rsp_err;
wire m_cmd_valid;
wire m_cmd_ready;
wire [31:0] m_cmd_addr;
wire m_cmd_read;
wire [31:0] m_cmd_wdata;
wire [3:0] m_cmd_wmask;
wire m_rsp_valid;
wire m_rsp_ready;
wire [31:0] m_rsp_rdata;
wire m_rsp_err;
wire a_cmd_valid;
wire a_cmd_ready;
wire [31:0] a_cmd_addr;
wire a_cmd_read;
wire [31:0] a_cmd_wdata;
wire [3:0] a_cmd_wmask;
wire a_rsp_valid;
wire a_rsp_ready;
wire [31:0] a_rsp_rdata;
wire a_rsp_err;
wire d_cmd_valid;
wire d_cmd_ready;
wire [31:0] d_cmd_addr;
wire d_cmd_read;
wire [31:0] d_cmd_wdata;
wire [3:0] d_cmd_wmask;
wire d_rsp_valid;
wire d_rsp_ready;
wire [31:0] d_rsp_rdata;
wire d_rsp_err;
wire x_cmd_valid, x_cmd_ready, x_cmd_read;
wire [31:0] x_cmd_addr, x_cmd_wdata;
wire [3:0] x_cmd_wmask;
wire x_rsp_valid, x_rsp_ready, x_rsp_err;
wire [31:0] x_rsp_rdata;
wire invalid_cfg, invalid_ram;
wire aon_valid, dm_valid, fio_valid;
wire aon_ready, dm_ready, fio_ready;
wire fio_rsp_ready, aon_rsp_ready, dm_rsp_ready;
assign aon_ready = aon_rsp_ready;
assign dm_ready = dm_rsp_ready;
assign fio_ready = fio_rsp_ready;
assign unexpected_bus = invalid_cfg || invalid_ram || aon_valid || dm_valid || fio_valid;
kwt_accel_icb u_accel(
    .clk(bus_clk), .rst_n(bus_rst_n), .irq(irq),
    .s_icb_cmd_valid(a_cmd_valid),
    .s_icb_cmd_ready(a_cmd_ready),
    .s_icb_cmd_addr(a_cmd_addr),
    .s_icb_cmd_read(a_cmd_read),
    .s_icb_cmd_wdata(a_cmd_wdata),
    .s_icb_cmd_wmask(a_cmd_wmask),
    .s_icb_rsp_valid(a_rsp_valid),
    .s_icb_rsp_ready(a_rsp_ready),
    .s_icb_rsp_rdata(a_rsp_rdata),
    .s_icb_rsp_err(a_rsp_err),
    .m_icb_cmd_valid(d_cmd_valid),
    .m_icb_cmd_ready(d_cmd_ready),
    .m_icb_cmd_addr(d_cmd_addr),
    .m_icb_cmd_read(d_cmd_read),
    .m_icb_cmd_wdata(d_cmd_wdata),
    .m_icb_cmd_wmask(d_cmd_wmask),
    .m_icb_rsp_valid(d_rsp_valid),
    .m_icb_rsp_ready(d_rsp_ready),
    .m_icb_rsp_rdata(d_rsp_rdata),
    .m_icb_rsp_err(d_rsp_err)
);
// Keep d_* as the accelerator's own interface for independent DMA monitoring.
// The arbiter locks the owner through backpressure and response completion.
kwt_icb_arb2 u_loader_dma_arb(
    .clk(bus_clk), .rst_n(bus_rst_n),
    .u_cmd_valid(l_cmd_valid), .u_cmd_ready(l_cmd_ready),
    .u_cmd_addr(l_cmd_addr), .u_cmd_read(l_cmd_read),
    .u_cmd_wdata(l_cmd_wdata), .u_cmd_wmask(l_cmd_wmask),
    .u_rsp_valid(l_rsp_valid), .u_rsp_ready(l_rsp_ready),
    .u_rsp_rdata(l_rsp_rdata), .u_rsp_err(l_rsp_err),
    .d_cmd_valid(d_cmd_valid), .d_cmd_ready(d_cmd_ready),
    .d_cmd_addr(d_cmd_addr), .d_cmd_read(d_cmd_read),
    .d_cmd_wdata(d_cmd_wdata), .d_cmd_wmask(d_cmd_wmask),
    .d_rsp_valid(d_rsp_valid), .d_rsp_ready(d_rsp_ready),
    .d_rsp_rdata(d_rsp_rdata), .d_rsp_err(d_rsp_err),
    .s_cmd_valid(x_cmd_valid), .s_cmd_ready(x_cmd_ready),
    .s_cmd_addr(x_cmd_addr), .s_cmd_read(x_cmd_read),
    .s_cmd_wdata(x_cmd_wdata), .s_cmd_wmask(x_cmd_wmask),
    .s_rsp_valid(x_rsp_valid), .s_rsp_ready(x_rsp_ready),
    .s_rsp_rdata(x_rsp_rdata), .s_rsp_err(x_rsp_err)
);
kwt_icb_window #(.BASE(32'h11000000),.MASK(32'hfffff000)) u_cfg_window(
    .clk(bus_clk),.rst_n(bus_rst_n),.invalid_access(invalid_cfg),
    .i_cmd_valid(p_cmd_valid),
    .i_cmd_ready(p_cmd_ready),
    .i_cmd_addr(p_cmd_addr),
    .i_cmd_read(p_cmd_read),
    .i_cmd_wdata(p_cmd_wdata),
    .i_cmd_wmask(p_cmd_wmask),
    .i_rsp_valid(p_rsp_valid),
    .i_rsp_ready(p_rsp_ready),
    .i_rsp_rdata(p_rsp_rdata),
    .i_rsp_err(p_rsp_err),
    .o_cmd_valid(a_cmd_valid),
    .o_cmd_ready(a_cmd_ready),
    .o_cmd_addr(a_cmd_addr),
    .o_cmd_read(a_cmd_read),
    .o_cmd_wdata(a_cmd_wdata),
    .o_cmd_wmask(a_cmd_wmask),
    .o_rsp_valid(a_rsp_valid),
    .o_rsp_ready(a_rsp_ready),
    .o_rsp_rdata(a_rsp_rdata),
    .o_rsp_err(a_rsp_err)
);
kwt_icb_window #(.BASE(32'ha0000000),.MASK(32'hfff80000)) u_ram_window(
    .clk(bus_clk),.rst_n(bus_rst_n),.invalid_access(invalid_ram),
    .i_cmd_valid(m_cmd_valid),
    .i_cmd_ready(m_cmd_ready),
    .i_cmd_addr(m_cmd_addr),
    .i_cmd_read(m_cmd_read),
    .i_cmd_wdata(m_cmd_wdata),
    .i_cmd_wmask(m_cmd_wmask),
    .i_rsp_valid(m_rsp_valid),
    .i_rsp_ready(m_rsp_ready),
    .i_rsp_rdata(m_rsp_rdata),
    .i_rsp_err(m_rsp_err),
    .o_cmd_valid(s_cmd_valid),
    .o_cmd_ready(s_cmd_ready),
    .o_cmd_addr(s_cmd_addr),
    .o_cmd_read(s_cmd_read),
    .o_cmd_wdata(s_cmd_wdata),
    .o_cmd_wmask(s_cmd_wmask),
    .o_rsp_valid(s_rsp_valid),
    .o_rsp_ready(s_rsp_ready),
    .o_rsp_rdata(s_rsp_rdata),
    .o_rsp_err(s_rsp_err)
);
e203_subsys_main u_main(
    .kwt_irq(irq),
    .kwt_bus_rst_n(bus_rst_n),
    .kwt_inspect_pc(inspect_pc),
    .kwt_cpu_irq(cpu_irq),
    .kwt_dma_cmd_valid(x_cmd_valid),
    .kwt_dma_cmd_ready(x_cmd_ready),
    .kwt_dma_cmd_addr(x_cmd_addr),
    .kwt_dma_cmd_read(x_cmd_read),
    .kwt_dma_cmd_wdata(x_cmd_wdata),
    .kwt_dma_cmd_wmask(x_cmd_wmask),
    .kwt_dma_rsp_valid(x_rsp_valid),
    .kwt_dma_rsp_ready(x_rsp_ready),
    .kwt_dma_rsp_rdata(x_rsp_rdata),
    .kwt_dma_rsp_err(x_rsp_err),
    .core_csr_clk(),
    .hfxoscen(),
    .inspect_pc_29b(),
    .inspect_dbg_irq(),
    .inspect_mode(1'b0),
    .inspect_por_rst(1'b0),
    .inspect_32k_clk(1'b0),
    .inspect_jtag_clk(1'b0),
    .pc_rtvec(32'h80000000),
    .cmt_dpc(),
    .cmt_dpc_ena(),
    .cmt_dcause(),
    .cmt_dcause_ena(),
    .dbg_irq_a(1'b0),
    .dbg_irq_r(),
    .wr_dcsr_ena(),
    .wr_dpc_ena(),
    .wr_dscratch_ena(),
    .wr_csr_nxt(),
    .dcsr_r({((32-1)-(0)+1){1'b0}}),
    .dpc_r({((`E203_PC_SIZE-1)-(0)+1){1'b0}}),
    .dscratch_r({((32-1)-(0)+1){1'b0}}),
    .dbg_mode(1'b0),
    .dbg_halt_r(1'b0),
    .dbg_step_r(1'b0),
    .dbg_ebreakm_r(1'b0),
    .dbg_stopcycle(1'b0),
    .core_mhartid(1'b0),
    .aon_wdg_irq_a(1'b0),
    .aon_rtc_irq_a(1'b0),
    .aon_rtcToggle_a(1'b0),
    .aon_icb_cmd_valid(aon_valid),
    .aon_icb_cmd_ready(aon_ready),
    .aon_icb_cmd_addr(),
    .aon_icb_cmd_read(),
    .aon_icb_cmd_wdata(),
    .aon_icb_rsp_valid(aon_valid),
    .aon_icb_rsp_ready(aon_rsp_ready),
    .aon_icb_rsp_err(1'b1),
    .aon_icb_rsp_rdata(32'b0),
    .dm_icb_cmd_valid(dm_valid),
    .dm_icb_cmd_ready(dm_ready),
    .dm_icb_cmd_addr(),
    .dm_icb_cmd_read(),
    .dm_icb_cmd_wdata(),
    .dm_icb_rsp_valid(dm_valid),
    .dm_icb_rsp_ready(dm_rsp_ready),
    .dm_icb_rsp_rdata(32'b0),
    .io_pads_gpioA_i_ival({((32-1)-(0)+1){1'b0}}),
    .io_pads_gpioA_o_oval(),
    .io_pads_gpioA_o_oe(),
    .io_pads_gpioB_i_ival({((32-1)-(0)+1){1'b0}}),
    .io_pads_gpioB_o_oval(),
    .io_pads_gpioB_o_oe(),
    .io_pads_qspi0_sck_i_ival(1'b0),
    .io_pads_qspi0_sck_o_oval(),
    .io_pads_qspi0_sck_o_oe(),
    .io_pads_qspi0_dq_0_i_ival(1'b0),
    .io_pads_qspi0_dq_0_o_oval(),
    .io_pads_qspi0_dq_0_o_oe(),
    .io_pads_qspi0_dq_1_i_ival(1'b0),
    .io_pads_qspi0_dq_1_o_oval(),
    .io_pads_qspi0_dq_1_o_oe(),
    .io_pads_qspi0_dq_2_i_ival(1'b0),
    .io_pads_qspi0_dq_2_o_oval(),
    .io_pads_qspi0_dq_2_o_oe(),
    .io_pads_qspi0_dq_3_i_ival(1'b0),
    .io_pads_qspi0_dq_3_o_oval(),
    .io_pads_qspi0_dq_3_o_oe(),
    .io_pads_qspi0_cs_0_i_ival(1'b0),
    .io_pads_qspi0_cs_0_o_oval(),
    .io_pads_qspi0_cs_0_o_oe(),
    .ext2itcm_icb_cmd_valid(1'b0),
    .ext2itcm_icb_cmd_ready(),
    .ext2itcm_icb_cmd_addr({((`E203_ITCM_ADDR_WIDTH-1)-(0)+1){1'b0}}),
    .ext2itcm_icb_cmd_read(1'b0),
    .ext2itcm_icb_cmd_wdata({((`E203_XLEN-1)-(0)+1){1'b0}}),
    .ext2itcm_icb_cmd_wmask({((`E203_XLEN/8-1)-(0)+1){1'b0}}),
    .ext2itcm_icb_rsp_valid(),
    .ext2itcm_icb_rsp_ready(1'b0),
    .ext2itcm_icb_rsp_err(),
    .ext2itcm_icb_rsp_rdata(),
    .ext2dtcm_icb_cmd_valid(1'b0),
    .ext2dtcm_icb_cmd_ready(),
    .ext2dtcm_icb_cmd_addr({((`E203_DTCM_ADDR_WIDTH-1)-(0)+1){1'b0}}),
    .ext2dtcm_icb_cmd_read(1'b0),
    .ext2dtcm_icb_cmd_wdata({((`E203_XLEN-1)-(0)+1){1'b0}}),
    .ext2dtcm_icb_cmd_wmask({((`E203_XLEN/8-1)-(0)+1){1'b0}}),
    .ext2dtcm_icb_rsp_valid(),
    .ext2dtcm_icb_rsp_ready(1'b0),
    .ext2dtcm_icb_rsp_err(),
    .ext2dtcm_icb_rsp_rdata(),
    .sysper_icb_cmd_valid(p_cmd_valid),
    .sysper_icb_cmd_ready(p_cmd_ready),
    .sysper_icb_cmd_addr(p_cmd_addr),
    .sysper_icb_cmd_read(p_cmd_read),
    .sysper_icb_cmd_wdata(p_cmd_wdata),
    .sysper_icb_cmd_wmask(p_cmd_wmask),
    .sysper_icb_rsp_valid(p_rsp_valid),
    .sysper_icb_rsp_ready(p_rsp_ready),
    .sysper_icb_rsp_err(p_rsp_err),
    .sysper_icb_rsp_rdata(p_rsp_rdata),
    .sysfio_icb_cmd_valid(fio_valid),
    .sysfio_icb_cmd_ready(fio_ready),
    .sysfio_icb_cmd_addr(),
    .sysfio_icb_cmd_read(),
    .sysfio_icb_cmd_wdata(),
    .sysfio_icb_cmd_wmask(),
    .sysfio_icb_rsp_valid(fio_valid),
    .sysfio_icb_rsp_ready(fio_rsp_ready),
    .sysfio_icb_rsp_err(1'b1),
    .sysfio_icb_rsp_rdata(32'b0),
    .sysmem_icb_cmd_valid(m_cmd_valid),
    .sysmem_icb_cmd_ready(m_cmd_ready),
    .sysmem_icb_cmd_addr(m_cmd_addr),
    .sysmem_icb_cmd_read(m_cmd_read),
    .sysmem_icb_cmd_wdata(m_cmd_wdata),
    .sysmem_icb_cmd_wmask(m_cmd_wmask),
    .sysmem_icb_rsp_valid(m_rsp_valid),
    .sysmem_icb_rsp_ready(m_rsp_ready),
    .sysmem_icb_rsp_err(m_rsp_err),
    .sysmem_icb_rsp_rdata(m_rsp_rdata),
    .test_mode(test_mode),
    .ls_clk(1'b0),
    .corerst(!rst_n),
    .hfclkrst(!rst_n),
    .hfextclk(clk),
    .hfclk(bus_clk)
);
endmodule
