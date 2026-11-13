# KWT

KWT is the RTL and delivery-support repository for a speech keyword recognition accelerator built around a 12-layer Transformer encoder. The hardware combines an 8×8 processing-element array, a vector processing unit, on-chip SRAM, INT8 weight dequantization, DMA data movement, and E203/ICB system integration.

## Highlights

- 12-layer Transformer encoder execution under hardware scheduling
- INT8 weight storage and dequantization to FP16
- FP16 multiplication with FP32 partial-sum accumulation
- 8×8 systolic array with 64 processing elements
- 32-lane vector datapath and 8 special-function units
- On-chip activation, weight, and parameter SRAM wrappers
- ICB slave configuration interface, ICB master DMA interface, and completion interrupt
- E203 platform integration with shared-memory access and arbitration

## Repository layout

| Path | Description |
|---|---|
| `KWT_rtl/accel_rtl/` | Accelerator RTL, including control, DMA, SRAM, matrix-array, dequantization, and VPU modules |
| `KWT_rtl/rtl/` | E203 platform integration, ICB arbitration/address windows, and TCM wrapper |
| `KWT_delivery_support/` | Verification evidence, archived VCS projects, numerical reference material, synthesis review files, hashes, and packaging scripts |
| `KWT_delivery_support/README_CN.md` | Detailed Chinese delivery notes and reproduction requirements |
| `KWT_delivery_support/numerics/NUMERIC_FORMAT_CN.md` | Numeric formats, parameter-image layout, and reference-model usage |

## RTL hierarchy

### Accelerator top level

`kwt_accel_icb` is the accelerator integration top level. It connects:

- `kwt_icb_cfg` for register configuration and status reporting
- `kwt_run` for task launch, layer sequencing, DMA orchestration, and error handling
- `kwt_compute_local` for matrix and vector job scheduling
- `kwt_act_sram` for activation storage and writeback
- `kwt_param_sram` for weight-bank and parameter storage

The top-level interface contains an ICB slave port for software configuration, an ICB master port for memory traffic, and an `irq` output for task completion.

### Compute path

- `matrix_array_8x8` contains 64 `pe` instances for tiled matrix computation.
- `kwt_vector_fp16` provides vector arithmetic, special-function, reduction, format-conversion, and writeback paths.
- `kwt_weight_dequant` and `kwt_dequant_fp32_pack` convert packed INT8 weights and FP32 scales into the FP16 representation consumed by the matrix engine.
- `kwt_encoder_layer_ctrl_local` and `kwt_run` coordinate the per-layer and full-network execution sequences.

### SoC integration

`kwt_platform_soc` integrates the accelerator with the E203 subsystem. The platform RTL includes ICB arbitration, accelerator and shared-memory address windows, TCM support, DMA routing, and interrupt wiring.

## Numeric organization

The intended inference datapath uses:

- INT8 symmetric per-matrix weights
- FP16 activations and matrix operands
- FP32 matrix accumulation and vector arithmetic
- FP16 writeback at defined conversion points

The detailed parameter-slot layout, byte ordering, conversion rules, and reference-model commands are documented in [`KWT_delivery_support/numerics/NUMERIC_FORMAT_CN.md`](KWT_delivery_support/numerics/NUMERIC_FORMAT_CN.md).

## Verification and delivery material

`KWT_delivery_support` contains saved verification evidence and reproducibility material, including:

- archived VCS module-verification projects
- numerical example vectors and a Python reference model
- saved RTL output and comparison records
- synthesis and Formality review material
- SHA-256 manifests for delivery-file integrity checks

To verify the delivery-support files after cloning:

```sh
cd KWT_delivery_support
sha256sum -c SHA256SUMS
```

Full VCS and E203 reproduction requires the corresponding commercial simulator, RISC-V toolchain, E203 platform sources, and technology libraries described in the delivery notes.

## Version note

The archived ten-sample VCS project and the matrix-array V2 synthesis/Formality material represent different recorded implementation revisions. Use the hashes and notes in `KWT_delivery_support` to keep RTL, numerical, synthesis, and equivalence results matched to their original revision.

## License

No open-source license is included in this repository. Obtain permission from the project maintainers before redistribution or reuse.

