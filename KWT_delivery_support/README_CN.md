# KWT-1 RTL、驱动与验证交付

| 目录 | 内容 |
|---|---|
| `01_RTL` | 服务器桌面 `last_RTL.tar.gz`，十样本 VCS RTL 文件哈希和归档核对结果 |
| `02_firmware` | E203 裸机固件，包括启动、链接、MMIO 配置、逐层调度和 PLIC IRQ17 处理 |
| `03_verification` | 十样本 VCS 工程及服务器原始运行输出，模块/SFU 验证工程，历史证据截图和十样本实验记录 |
| `04_synthesis` | 顶层 DC 和阵列 DC/Formality 的报告、脚本、网表、约束等，保留原目录层次 |
| `05_numerics` | 数值格式，软件模型，参数镜像转换脚本，输入和权重示例，以及本地核验记录 |

服务器端按 `01_RTL/source_audit.txt` 核对 `last_RTL.tar.gz`、现存十样本工程与本地 VCS 源码清单。十样本 VCS 和阵列 V2 的 `matrix_array_8x8.v` 是不同实现，综合、等价、数值结果各自对应原始版本。DC 顶层复核针对历史综合轮次，面积单位和时序范围以其报告为准。

`02_firmware/firmware` 收录裸机驱动和平台地址定义。配置从口基地址为 `0x11000000`，共享内存输入/输出缓冲区为 `0xA0000000` 和 `0xA0004000`，参数槽从 `0xA0010000` 开始。设置 `RISCV_TOOLCHAIN` 后可在 `02_firmware` 下运行 `bash build_firmware.sh build`，生成 RV32IMAC/ILP32 固件与 ITCM 镜像。包中的环境快照（若存在）记录原服务器安装路径。

`03_verification/kwt_tcm_batch10` 包含实际使用的 RTL、TB、固件、用例和比对工具。运行已有 `run_vcs.sh` 仍需要服务器的 VCS、RISC-V 工具链、E203 平台源包和工艺模型。工艺库从服务器环境取得。已保存结果见 `batch_summary.json`、各例 `numerical.json`、`execution.json` 与 `layer_*_ln2.hex`。如需复核，在解压副本中执行 `python tools/aggregate_batch.py --run runs/batch10_pQxg9vhM`，该命令会更新汇总文件。报告中的 Top-1 由末层输出经软件 FP32 分类头得到。

`dashboard.html` 是已有阵列覆盖率报告的入口。若服务器原始 URG 目录可定位且入口文件一致，整套 HTML 会放在 `03_verification/evidence/urg` 下。

解包后可在 `KWT_delivery` 目录运行 `sha256sum -c SHA256SUMS`。
