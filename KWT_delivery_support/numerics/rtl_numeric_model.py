#!/usr/bin/env python3
"""KWT-1 encoder arithmetic model for finite, in-range inference data.

Uses the VCS parameter slots, K=8 partial sums, VPU operation order and SFU
approximations. It models values only, using NumPy binary32 arithmetic.
"""
import argparse
from pathlib import Path

import numpy as np

from convert_params import INPUT_BYTES, MATRIX_OFFSETS, MATRIX_SHAPES, PARAM_BASE, SLOT_BYTES


def bits(word):
    return np.uint32(word).view(np.float32)


def add(a, b):
    return np.add(a, b, dtype=np.float32)


def mul(a, b):
    return np.multiply(a, b, dtype=np.float32)


def half(x):
    return x.astype(np.float16)


def row_sum(x):
    acc = np.zeros((x.shape[0], 1), np.float32)
    for col in range(x.shape[1]):
        acc = add(acc, x[:, col:col + 1])
    return acc


def gemm(x, w, bias=None):
    x, w = x.astype(np.float32), w.astype(np.float32)
    result = np.zeros((x.shape[0], w.shape[1]), np.float32)
    for block in range(0, x.shape[1], 8):
        part = np.zeros_like(result)
        for idx in range(block, min(block + 8, x.shape[1])):
            part = add(part, mul(x[:, idx:idx + 1], w[idx, :]))
        result = part if block == 0 else add(result, part)
    return result if bias is None else add(result, bias)


def exp_nonpositive(x):
    z = np.maximum(x, np.float32(-80.0))
    n = np.trunc(-mul(z, bits(0x3FB8AA3B))).astype(np.int32)
    f = add(z, mul(n.astype(np.float32), bits(0x3F317218)))
    p = np.full_like(z, bits(0x37D00D01))
    for coefficient in (0x39500D01, 0x3AB60B61, 0x3C088889, 0x3D2AAAAB,
                        0x3E2AAAAB, 0x3F000000, 0x3F800000, 0x3F800000):
        p = add(mul(p, f), bits(coefficient))
    return np.where(x < -80, np.float32(0), np.ldexp(p, -n))


def reciprocal(x):
    r = (np.uint32(0x7EF311C3) - x.view(np.uint32)).view(np.float32)
    for _ in range(4):
        r = mul(r, add(np.float32(2), -mul(x, r)))
    return r


def reciprocal_sqrt(x):
    r = (np.uint32(0x5F3759DF) - (x.view(np.uint32) >> 1)).view(np.float32)
    for _ in range(4):
        r = mul(r, add(np.float32(1.5), -mul(mul(x, mul(r, r)), np.float32(0.5))))
    return r


def tanh(x):
    magnitude = np.abs(x)
    e = exp_nonpositive(-mul(np.minimum(magnitude, np.float32(9)), np.float32(2)))
    y = add(np.float32(1), -mul(mul(e, reciprocal(add(e, np.float32(1)))), np.float32(2)))
    y = np.where(magnitude >= 9, np.float32(1), y)
    return np.where(magnitude < 2**-12, x, np.copysign(y, x))


def gelu(x):
    z = mul(mul(add(mul(mul(x, x), bits(0x3D372713)), np.float32(1)), x),
            bits(0x3F4C422A))
    return half(mul(mul(add(tanh(z), np.float32(1)), np.float32(0.5)), x))


def layer_norm(x, residual, norm):
    gamma, beta, epsilon = norm
    r = add(x, residual)
    d = add(r, -mul(row_sum(r), np.float32(1 / 64)))
    variance = mul(row_sum(mul(d, d)), np.float32(1 / 64))
    inv = reciprocal_sqrt(add(variance, epsilon))
    return half(add(mul(mul(d, inv), gamma), beta))


def read_image(path, size):
    words = path.read_text(encoding="ascii").split()
    if len(words) != size // 4 or any(len(word) != 8 for word in words):
        raise ValueError("%s: wrong 32-bit HEX length for %d bytes" % (path, size))
    return np.array([int(word, 16) for word in words], dtype="<u4").tobytes()


def read_layer(path):
    data = read_image(path, SLOT_BYTES)
    if np.frombuffer(data, "<u4", count=2).tolist() != [0x4B575431, 1]:
        raise ValueError("Invalid KWT1 parameter header: %s" % path)
    scales = np.frombuffer(data, "<f4", count=6, offset=8)
    if not np.isfinite(scales).all() or np.any(scales < np.finfo(np.float32).tiny):
        raise ValueError("Invalid quantization scale: %s" % path)
    weights = []
    for index, ((inputs, outputs), offset) in enumerate(zip(MATRIX_SHAPES, MATRIX_OFFSETS)):
        q = np.frombuffer(data, np.int8, inputs * outputs, offset).reshape(inputs, outputs)
        weights.append(half(mul(q, scales[index])))

    def fp32(offset, count):
        return np.frombuffer(data, "<f4", count=count, offset=PARAM_BASE + offset)

    def norm(offset):
        return fp32(offset, 64), fp32(offset + 0x100, 64), fp32(offset + 0x200, 1)[0]

    biases = fp32(0, 64), fp32(0x100, 256), fp32(0x500, 64)
    return weights, biases, (norm(0x600), norm(0xA00)), fp32(0xE00, 1)[0]


def encoder_layer(x, params):
    (wq, wk, wv, wo, w1, w2), (bo, b1, b2), (norm1, norm2), scale = params
    q, k, v = [half(gemm(x, w)) for w in (wq, wk, wv)]
    score = mul(gemm(q, k.T), scale)
    e = exp_nonpositive(add(score, -score.max(axis=1, keepdims=True)))
    prob = half(mul(e, reciprocal(row_sum(e))))
    attn = half(gemm(prob, v))
    u = layer_norm(gemm(attn, wo, bo), x, norm1)
    ffn = gemm(gelu(gemm(u, w1, b1)), w2, b2)
    return layer_norm(ffn, u, norm2)


def run(case):
    x = np.frombuffer(read_image(case / "input.hex", INPUT_BYTES), "<f2").reshape(99, 64)
    for layer in range(1, 13):
        x = encoder_layer(x, read_layer(case / ("params_%02d.hex" % layer)))
        if not np.isfinite(x).all():
            raise ValueError("Layer %d produced a nonfinite value" % layer)
        yield layer, x


def compare(folder, layer, actual):
    path = folder / ("layer_%02d_ln2.hex" % layer)
    words = [int(token, 16) for token in path.read_text(encoding="ascii").split()]
    if len(words) != actual.size or any(word > 0xFFFF for word in words):
        raise ValueError("Invalid reference HEX: %s" % path)
    expected = np.array(words, dtype=np.uint16).reshape(actual.shape)
    matching = np.count_nonzero(actual.view(np.uint16) == expected)
    delta = np.abs(actual.astype(np.float32) - expected.view(np.float16).astype(np.float32))
    print("L%02d exact=%d/%d max_abs=%.8g" %
          (layer, matching, actual.size, np.max(delta)))
    return matching == actual.size


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", type=Path, help="Directory containing input.hex and params_01..12")
    parser.add_argument("--compare", type=Path, help="Directory of actual RTL layer_NN_ln2.hex")
    parser.add_argument("--output", type=Path, help="New directory for predicted LN2 dumps")
    args = parser.parse_args()
    if args.output:
        args.output.mkdir()
    all_match = True
    for layer, values in run(args.case):
        if args.output:
            path = args.output / ("layer_%02d_ln2.hex" % layer)
            path.write_bytes("".join("%04x\n" % i for i in values.view(np.uint16).flat).encode("ascii"))
        if args.compare:
            all_match = compare(args.compare, layer, values) and all_match
    if args.compare:
        if not all_match:
            raise SystemExit("RTL comparison: differs")
        print("RTL comparison: 12 x 6336 bit-identical FP16 elements")
    else:
        print("MODEL completed: 12 encoder layers")


if __name__ == "__main__":
    main()
