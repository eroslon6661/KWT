`ifndef KWT1_DEFS_VH

`define KWT1_DEFS_VH

`define D_MODEL                 64

`define MLP_DIM                 256

`define NUM_LAYERS              12

`define NUM_HEADS                1

`define NUM_CLASSES             12

`define NUM_TOKENS              99

`define ARRAY_ROWS               8

`define ARRAY_COLS               8

`define KWT_ARRAY_ACT_WIDTH       16

`define KWT_ARRAY_WEIGHT_WIDTH    16

`define KWT_ARRAY_PSUM_WIDTH      32

`define KWT_ARRAY_OUT_WIDTH       32

`define KWT_ARRAY_PE_H_LAT         1

`define KWT_ARRAY_PE_V_LAT         3

`define ACT_ADDR_W              18

`define WGT_ADDR_W              20

`define ACT_TOKENS_A       18'h00000

`define ACT_FFN_HID        18'h04000

`define ACT_FFN_GELU       18'h20000

`define ACT_FFN_OUT        18'h30000

`define WGT_LAYER_STRIDE   20'h10000

`define WGT_FFN1_W_OFS     20'h04100

`define WGT_FFN1_B_OFS     20'h08100

`define WGT_FFN2_W_OFS     20'h08500

`define WGT_FFN2_B_OFS     20'h0C500

`define FMT_INT8            2'd0

`define FMT_FP16            2'd1

`define FMT_INT32           2'd2

`define FMT_FP32            2'd3

`define GEMM_PATCH          4'd0

`define GEMM_QKV            4'd1

`define GEMM_QK             4'd2

`define GEMM_AV             4'd3

`define GEMM_PROJ           4'd4

`define GEMM_FFN1           4'd5

`define GEMM_FFN2           4'd6

`define GEMM_HEAD           4'd7

`define GEMM_JOB_W                 256

`define GEMM_C_BASE_LSB              0

`define GEMM_C_BASE_MSB             17

`define GEMM_BIAS_BASE_LSB          18

`define GEMM_BIAS_BASE_MSB          37

`define GEMM_B_BASE_LSB             38

`define GEMM_B_BASE_MSB             57

`define GEMM_A_BASE_LSB             58

`define GEMM_A_BASE_MSB             75

`define GEMM_C_STRIDE_LSB           76

`define GEMM_C_STRIDE_MSB           91

`define GEMM_B_STRIDE_LSB           92

`define GEMM_B_STRIDE_MSB          107

`define GEMM_A_STRIDE_LSB          108

`define GEMM_A_STRIDE_MSB          123

`define GEMM_K_LSB                124

`define GEMM_K_MSB                139

`define GEMM_N_LSB                140

`define GEMM_N_MSB                155

`define GEMM_M_LSB                156

`define GEMM_M_MSB                171

`define GEMM_USE_BIAS_BIT         180

`define GEMM_OUT_INT32_BIT        181

`define GEMM_TRANSPOSE_B_BIT      182

`define GEMM_B_FROM_ACT_BIT       183

`define GEMM_B_FMT_LSB            184

`define GEMM_B_FMT_MSB            185

`define GEMM_A_FMT_LSB            186

`define GEMM_A_FMT_MSB            187

`define GEMM_KIND_LSB             188

`define GEMM_KIND_MSB             191

`define KWT_GEMM_W_SCALE_LSB      192

`define KWT_GEMM_W_SCALE_MSB      223

`endif