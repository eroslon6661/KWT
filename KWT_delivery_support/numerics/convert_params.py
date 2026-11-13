#!/usr/bin/env python3
"""Pack the archived INT8 matrix streams and FP32 constants for the VCS RTL."""
import argparse
import re
import struct
from pathlib import Path

INPUT_BYTES = 99 * 64 * 2
SLOT_BYTES = 0xD000
PARAM_BASE = 0xC100
PARAM_BYTES = 0xE08
MATRIX_OFFSETS = (0x0100, 0x1100, 0x2100, 0x3100, 0x4100, 0x8100)
MATRIX_SHAPES = ((64, 64),) * 4 + ((64, 256), (256, 64))


def read_sparse_bytes(path, origin, size):
    data = bytearray(size)
    seen = set()
    addr = None
    for token in path.read_text(encoding="ascii").split():
        if token.startswith("@"):
            addr = int(token[1:], 16) - origin
            continue
        if addr is None or not 0 <= addr < size or addr in seen or len(token) != 2:
            raise ValueError("Invalid or duplicate byte in %s: %s" % (path, token))
        data[addr] = int(token, 16)
        seen.add(addr)
        addr += 1
    if not seen:
        raise ValueError("Empty input: %s" % path)
    return data


def pack_layer(folder):
    path = folder / "weights_int8.hex"
    beats = [int(token, 16) for token in path.read_text(encoding="ascii").split()]
    if len(beats) != 12288:
        raise ValueError("%s: expected 12288 packed INT8 words" % path)
    slot = bytearray(SLOT_BYTES)
    cursor = 0
    scales = []
    for (inputs, outputs), offset in zip(MATRIX_SHAPES, MATRIX_OFFSETS):
        words = inputs * outputs // 4
        scale = (beats[cursor] >> 32) & 0xFFFFFFFF
        if scale & 0x80000000 or (scale >> 23) in (0, 255):
            raise ValueError("%s: invalid positive normal FP32 scale" % path)
        scales.append(scale)
        for index, beat in enumerate(beats[cursor:cursor + words]):
            flags = 15 | (int(index == words - 1) << 4)
            if beat >> 64 != flags or ((beat >> 32) & 0xFFFFFFFF) != scale:
                raise ValueError("%s: inconsistent scale/keep/last at beat %d" %
                                 (path, cursor + index))
            struct.pack_into("<I", slot, offset + 4 * index, beat & 0xFFFFFFFF)
        cursor += words
    struct.pack_into("<8I", slot, 0, 0x4B575431, 1, *scales)
    slot[PARAM_BASE:PARAM_BASE + PARAM_BYTES] = read_sparse_bytes(
        folder / "params_fp32.hex", 0x18000, PARAM_BYTES)
    return slot


def pack_onnx(path):
    import numpy as np
    import onnx
    from onnx import numpy_helper

    graph = onnx.load(str(path)).graph
    tensors = {tensor.name: numpy_helper.to_array(tensor) for tensor in graph.initializer}
    for layer in range(12):
        prefix = "kws_transformer/transformer_block" + ("_%d" % layer if layer else "") + "/"
        dequant = [node for node in graph.node
                   if node.op_type == "DequantizeLinear" and node.output[0].startswith(prefix)]
        dequant.sort(key=lambda node: int(re.search(r"/dense_(\d+)/", node.output[0])[1]))
        if len(dequant) != 6:
            raise ValueError("Layer %d: expected six DequantizeLinear matrices" % (layer + 1))
        slot = bytearray(SLOT_BYTES)
        scales = []
        for role, (node, shape, offset) in enumerate(zip(dequant, MATRIX_SHAPES, MATRIX_OFFSETS)):
            q, scale = (tensors[name] for name in node.input[:2])
            zero = tensors[node.input[2]] if len(node.input) > 2 and node.input[2] else 0
            if (q.dtype != np.int8 or q.T.shape != shape or scale.dtype != np.float32
                    or scale.size != 1 or not np.isfinite(scale).all()
                    or float(scale.item()) < np.finfo(np.float32).tiny or np.any(zero != 0)):
                raise ValueError("Unsupported quantization or matrix shape: " + node.output[0])
            scales.append(float(scale.item()))
            slot[offset:offset + q.size] = q.T.tobytes(order="C")
            if role >= 3:
                name = node.output[0].split("/Tensordot/")[0] + "/bias"
                bias = tensors[name]
                if bias.shape != (shape[1],) or bias.dtype != np.float32 or not np.isfinite(bias).all():
                    raise ValueError("Invalid FP32 bias: " + name)
                start = PARAM_BASE + (0, 0x100, 0x500)[role - 3]
                slot[start:start + bias.nbytes] = bias.astype("<f4").tobytes()
        struct.pack_into("<I I 6f", slot, 0, 0x4B575431, 1, *scales)
        norm_names = sorted(name for name in tensors if name.startswith(prefix) and name.endswith("/gamma"))
        if len(norm_names) != 2:
            raise ValueError("Layer %d: expected two LayerNorms" % (layer + 1))
        for offset, name in zip((0x600, 0xA00), norm_names):
            gamma, beta = tensors[name], tensors[name[:-5] + "beta"]
            if any(x.shape != (64,) or x.dtype != np.float32 or not np.isfinite(x).all()
                   for x in (gamma, beta)):
                raise ValueError("Invalid LayerNorm parameters: " + name)
            struct.pack_into("<128f f I", slot, PARAM_BASE + offset, *gamma, *beta, 1e-6, 0)
        struct.pack_into("<f I", slot, PARAM_BASE + 0xE00, 0.125, 0)
        yield slot


def word_hex(data):
    return "".join("%08x\n" % word for (word,) in struct.iter_unpack("<I", data))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vectors", type=Path, help="Directory containing input.hex and layer_01..12")
    parser.add_argument("output", type=Path, help="New output directory")
    parser.add_argument("--onnx", type=Path, help="Read parameters directly from a weight-only INT8 KWT-1 ONNX")
    args = parser.parse_args()
    input_data = read_sparse_bytes(args.vectors / "input.hex", 0, INPUT_BYTES)
    layers = (list(pack_onnx(args.onnx)) if args.onnx else
              [pack_layer(args.vectors / ("layer_%02d" % i)) for i in range(1, 13)])
    args.output.mkdir()
    (args.output / "input.hex").write_bytes(word_hex(input_data).encode("ascii"))
    for i, layer in enumerate(layers, 1):
        (args.output / ("params_%02d.hex" % i)).write_bytes(word_hex(layer).encode("ascii"))
    print("PACKED input_words=3168 parameter_slots=12 words_per_slot=13312")


if __name__ == "__main__":
    main()
