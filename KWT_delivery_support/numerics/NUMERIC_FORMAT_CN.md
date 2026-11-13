# KWT-1 数值格式与参数镜像

本说明对应十样本 VCS 使用的 RTL（`matrix_array_8x8.v` 的 SHA-256 以 `78c846cb` 开头）。

## 数值通路

| 位置 | 数值与运算规则 |
|---|---|
| 编码器输入与层间激活 | 99 个 token，每 token 64 通道，按 token 行优先排列。FP16（1 位符号、5 位指数、10 位尾数）。低地址半字放在 32 位字的 [15:0]，高地址半字放在 [31:16]。每样本 3,168 个 32 位字 |
| 权重 | 逐矩阵对称有符号 INT8 补码，zero point 为 0，每个矩阵一个正 FP32 scale。每个 32 位字的小端 4 字节依次存放 4 个权重。矩阵按 K×N 行优先打包 |
| 权重反量化 | INT8×FP32 scale，先形成 FP32 结果，再用 FP16 存储，FP32 和 FP16 转换使用最近偶数舍入（RNE） |
| 8×8 脉动阵列 | FP16×FP16，乘积以 FP32 表示，FP32 加法按连续 8 个 K 项形成块内部分和，再按 K 块顺序累加。偏置在矩阵累加完成后以 FP32 相加 |
| VPU | Softmax 按行减最大值、近似指数、顺序求和、倒数和缩放。GELU 使用 tanh 近似。LayerNorm 在残差相加后按行作两遍归约，经过倒平方根迭代再作 gamma/beta 仿射。算术为 FP32，指定写回点舍入到 FP16 |
| 分类 | 末层 LN2 写回 99×64 个 FP16；十样本实验由服务器 Python 读取 token 0，使用原始 FP32 的 64×12 权重和 12 维偏置做分类 |

SFU 的 EXP 接受非正输入，低于 −80 时输出零；TANH 在绝对值达到 9 时饱和，在绝对值低于 \(2^{-12}\) 时直通；RECIP 和 RSQRT 采用固定初值和四次迭代。非有限值及非法域的响应以 `kwt_vpu_sfu.v` 为准。VPU 的乘法器会将 FP32 非规格化输入或下溢结果按带符号零处理。FP32→FP16 的舍入、非规格化和溢出处理见 `kwt_vpu_f2h.v`。

## 每层参数槽

槽大小为 `0xD000` 字节。以下为相对槽起点的字节偏移。未使用的字节填零。

| 偏移 | 内容 | 大小 |
|---|---|---:|
| `0x0000` | 32 位魔数 `0x4B575431`、版本 1、Q/K/V/O/FFN1/FFN2 的 6 个 FP32 scale | 32 B |
| `0x0100`、`0x1100`、`0x2100`、`0x3100` | Q、K、V、输出投影 INT8 权重 | 各 4,096 B |
| `0x4100`、`0x8100` | FFN1（64×256）、FFN2（256×64）INT8 权重 | 各 16,384 B |
| `0xC100` | 输出投影、FFN1、FFN2 的 FP32 偏置 | 1,536 B |
| `0xC700`、`0xCB00` | LN1、LN2 的 gamma[64]、beta[64]、epsilon（例为 1e−6）及保留字 | 各 520 B，间距 1,024 B |
| `0xCF00` | FP32 注意力缩放系数（例为 0.125）及保留字 | 8 B |

## 使用

以下命令在 `KWT_delivery` 目录运行。需要 Python 3，软件模型用 NumPy，ONNX 转换另需 onnx。本包以 NumPy 1.23.5 和 onnx 1.16.2 环境核验。输出目录须为新路径。

```sh
python3 05_numerics/convert_params.py 05_numerics/example_vectors packed_01_yes
python3 05_numerics/convert_params.py 05_numerics/example_vectors packed_from_onnx \
    --onnx 05_numerics/kwt1_non_stream_int8_wo.onnx
python3 05_numerics/rtl_numeric_model.py packed_01_yes \
    --compare 05_numerics/rtl_reference_01_yes
```

转换器接受原始逐层 INT8 stream 和 FP32 常量，或接受已量化、逐矩阵对称 INT8 的 KWT-1 ONNX。两种方式各生成 `input.hex` 与 `params_01.hex` 至 `params_12.hex`。示例来自 `01_yes`，两种转换方式均与 VCS 工程留档的 13 份输入/参数文件逐字节一致。直接替换历史回归用例还需相应的 FP32 参考、样本身份和哈希清单。

模型复用已有软件参考中的 K 分块和 SFU 近似运算顺序，直接读取 VCS 的 32 位镜像。验证使用相同加速器源码的本地 ModelSim 输出，`01_yes` 的 12 层共 76,032 个 LN2 FP16 数据全部逐位一致。它用 NumPy FP32 实现有效推理的算术，验证范围为有限、正常推理数据。总线握手、周期计数及算子特殊值另参见 RTL 测试工程。

如需用服务器上已保存的实际 VCS 数据比对，可将 `--compare` 指向 `03_verification/kwt_tcm_batch10/runs/batch10_pQxg9vhM/cases/01_yes`。第一个位置参数同时指向同一运行的用例目录，确保输入和镜像来自该次运行。
