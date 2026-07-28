#!/usr/bin/env python3
"""BiRefNet_lite -> Core ML conversion spike.

The one question this answers: can the model our v0.3 plan hangs on actually be
turned into an .mlpackage, and at what size and speed? (roadmap.md lists this as
the biggest open risk — no pre-made Core ML build of BiRefNet exists.)

The known obstacle is `torchvision.ops.deform_conv2d` inside the decoder's
ASPPDeformable blocks: Core ML has no such op. The workaround is a pure-PyTorch
re-implementation (bilinear sampling written out by hand), swapped in before
tracing. It is O(K·H·W) in memory rather than a fused kernel, which is fine for
a single 1024x1024 pass at inference.

Run inside the spike venv:  .venv/bin/python Scripts/convert-birefnet.py
Inputs:  models/birefnet_lite_src/  (HF code files + symlinked local weights)
Outputs: models/weights/BiRefNetLite.mlpackage, plus a parity report on stdout.
"""

import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

ROOT = Path(__file__).resolve().parent.parent
# Defaults are the lite model; any sibling variant converts the same way:
#   .venv/bin/python Scripts/convert-birefnet.py birefnet_general_src BiRefNetGeneral
SRC = ROOT / "models" / (sys.argv[1] if len(sys.argv) > 1 else "birefnet_lite_src")
OUT = ROOT / "models" / "weights" / f"{sys.argv[2] if len(sys.argv) > 2 else 'BiRefNetLite'}.mlpackage"
SIDE = 1024  # the family's training resolution


def deform_conv2d_traceable(input, offset, weight, bias=None, stride=(1, 1),
                            padding=(0, 0), dilation=(1, 1), mask=None):
    """torchvision.ops.deform_conv2d in plain tensor ops, so coremltools can see it.

    Deformable convolution is just: for each output position and each kernel tap,
    sample the input at (regular grid + learned offset) with bilinear interpolation,
    then do an ordinary weighted sum. Written that way — explicit gather + lerp —
    every op is one Core ML supports.
    """
    def pair(v):
        return (v, v) if isinstance(v, int) else tuple(v)

    n, c_in, h_in, w_in = input.shape
    c_out, c_in_g, kh, kw = weight.shape
    sh, sw = pair(stride)
    ph, pw = pair(padding)
    dh, dw = pair(dilation)
    groups = c_in // c_in_g
    h_out = (h_in + 2 * ph - dh * (kh - 1) - 1) // sh + 1
    w_out = (w_in + 2 * pw - dw * (kw - 1) - 1) // sw + 1
    # offset: (n, 2*offset_groups*kh*kw, h_out, w_out), pairs are (dy, dx)
    offset_groups = offset.shape[1] // (2 * kh * kw)

    x = F.pad(input, (pw, pw, ph, ph))
    h_pad, w_pad = h_in + 2 * ph, w_in + 2 * pw

    # Base sampling grid per kernel tap, in padded coordinates.
    base_y = torch.arange(h_out, dtype=input.dtype) * sh
    base_x = torch.arange(w_out, dtype=input.dtype) * sw
    grid_y, grid_x = torch.meshgrid(base_y, base_x, indexing="ij")  # (h_out, w_out)

    # Keep offset/mask in their native channel layout: any reshape that separates
    # (group, tap, coord) into their own axes lands at rank 6, and Core ML stops
    # at rank 5. Channel arithmetic costs nothing and stays within rank 4.
    channels_per_og = c_in // offset_groups

    columns = []
    for k in range(kh * kw):
        ky, kx = k // kw, k % kw
        tap_y = grid_y + ky * dh  # (h_out, w_out)
        tap_x = grid_x + kx * dw
        per_og = []
        for og in range(offset_groups):
            base = og * 2 * kh * kw + 2 * k
            y = tap_y + offset[:, base]  # (n, h_out, w_out)
            x_ = tap_x + offset[:, base + 1]
            y0 = torch.floor(y)
            x0 = torch.floor(x_)
            wy = (y - y0).unsqueeze(1)
            wx = (x_ - x0).unsqueeze(1)

            def gather(yy, xx):
                yy = yy.clamp(0, h_pad - 1)
                xx = xx.clamp(0, w_pad - 1)
                idx = (yy * w_pad + xx).long().reshape(n, 1, -1)
                idx = idx.expand(n, channels_per_og, idx.shape[2])
                src = x[:, og * channels_per_og:(og + 1) * channels_per_og]
                return torch.gather(src.reshape(n, channels_per_og, -1), 2, idx) \
                    .reshape(n, channels_per_og, h_out, w_out)

            # Zero out taps that sampled outside the image (torchvision zero-pads).
            valid = ((y > -1) & (y < h_pad) & (x_ > -1) & (x_ < w_pad)) \
                .unsqueeze(1).to(input.dtype)
            v = (gather(y0, x0) * (1 - wy) * (1 - wx)
                 + gather(y0, x0 + 1) * (1 - wy) * wx
                 + gather(y0 + 1, x0) * wy * (1 - wx)
                 + gather(y0 + 1, x0 + 1) * wy * wx) * valid
            if mask is not None:
                # Broadcast over the group's channels; repeat_interleave is off
                # the table (coremltools lowers it to a tile with fp32 reps).
                v = v * mask[:, og * kh * kw + k].unsqueeze(1)
            per_og.append(v)
        columns.append(torch.cat(per_og, dim=1))  # (n, c_in, h_out, w_out)

    stacked = torch.stack(columns, dim=2)  # (n, c_in, kh*kw, h_out, w_out)
    stacked = stacked.reshape(n, groups, c_in_g * kh * kw, h_out * w_out)
    w = weight.reshape(groups, c_out // groups, c_in_g * kh * kw)
    out = torch.einsum("ngkp,gok->ngop", stacked, w) \
        .reshape(n, c_out, h_out, w_out)
    if bias is not None:
        out = out + bias.reshape(1, -1, 1, 1)
    return out


def check_parity_against_torchvision():
    """The rewrite must match torchvision before it is allowed near the trace."""
    import torchvision.ops
    torch.manual_seed(0)
    x = torch.randn(1, 8, 13, 17)
    w = torch.randn(6, 8, 3, 3)
    b = torch.randn(6)
    off = torch.randn(1, 2 * 3 * 3, 13, 17) * 2
    m = torch.rand(1, 3 * 3, 13, 17)
    want = torchvision.ops.deform_conv2d(x, off, w, b, padding=(1, 1), mask=m)
    got = deform_conv2d_traceable(x, off, w, b, padding=(1, 1), mask=m)
    err = (want - got).abs().max().item()
    print(f"deform_conv2d rewrite vs torchvision: max abs err {err:.2e}")
    assert err < 1e-4, "rewrite disagrees with torchvision; do not trace with it"


class Wrapper(torch.nn.Module):
    """Image in, sigmoid mask out — the only surface PluckKit will ever see."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, image):
        # BiRefNet returns a list of scaled logits; the last one is full-resolution.
        return torch.sigmoid(self.model(image)[-1])


def main():
    check_parity_against_torchvision()

    import torchvision.ops
    torchvision.ops.deform_conv2d = deform_conv2d_traceable
    # birefnet.py imports the symbol directly, so patch the module too, after load.

    from transformers import AutoModelForImageSegmentation
    print("loading model…")
    model = AutoModelForImageSegmentation.from_pretrained(
        str(SRC), trust_remote_code=True, local_files_only=True
    )
    # Some variants ship fp16 state dicts; trace in fp32 and let the converter
    # decide precision (it writes fp16 into the mlpackage anyway).
    model.float().eval()

    # transformers loads birefnet.py as a dynamic module under its own name;
    # it imported deform_conv2d by value, so the patch must land on that module.
    for mod_name, mod in list(sys.modules.items()):
        if mod_name.endswith("birefnet") and hasattr(mod, "deform_conv2d"):
            mod.deform_conv2d = deform_conv2d_traceable
            print(f"patched deform_conv2d in {mod_name}")

    example = torch.rand(1, 3, SIDE, SIDE)
    with torch.no_grad():
        torch_out = Wrapper(model)(example)
        print(f"eager output: {tuple(torch_out.shape)}, "
              f"range [{torch_out.min():.3f}, {torch_out.max():.3f}]")
        print("tracing…")
        traced = torch.jit.trace(Wrapper(model), example)

    import coremltools as ct
    from coremltools.converters.mil.frontend.torch import ops as _torch_ops

    # Swin computes padded extents as `torch.ceil(torch.tensor(H)/window)*window`,
    # which traces to a shape-(1,) constant; coremltools' aten::Int handler only
    # accepts 0-dim. Every such value is static here (fixed 1024 input), so
    # unwrapping single-element arrays before the cast is lossless.
    _orig_cast = _torch_ops._cast

    def _cast_unwrapping(context, node, dtype, dtype_name):
        x = context[node.inputs[0]]
        val = getattr(x, "val", None)
        if val is not None and getattr(val, "shape", None) == (1,):
            from coremltools.converters.mil import mil
            from coremltools.converters.mil.mil import Builder as mb
            res = mb.const(val=dtype(val[0]), name=node.name)
            context.add(res, torch_name=node.name)
            return
        _orig_cast(context, node, dtype, dtype_name)

    _torch_ops._cast = _cast_unwrapping

    print("converting…")
    # ImageNet normalization folded into the input layer: the app hands Core ML a
    # plain CGImage and nothing in Swift ever needs to know the mean/std numbers.
    scale = 1 / (0.226 * 255.0)
    bias = [-0.485 / 0.229, -0.456 / 0.224, -0.406 / 0.225]
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=example.shape,
                             scale=scale, bias=bias)],
        outputs=[ct.TensorType(name="mask")],
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT16,
        # ct.convert loads the finished model once with default compute units,
        # and ANE hangs (not fails — hangs) compiling the deform gather chain
        # on the larger variants. Pin the load to the units we can actually use.
        compute_units=ct.ComputeUnit.CPU_AND_GPU,
    )
    mlmodel.save(str(OUT))
    size_mb = sum(f.stat().st_size for f in OUT.rglob("*") if f.is_file()) / 1e6
    print(f"saved {OUT.name}: {size_mb:.1f} MB")

    print("verifying Core ML vs eager torch on the same input…")
    # ANE refuses to compile the deform gather chain ("ANECCompile() FAILED"), so
    # the model must be loaded CPU+GPU. PluckKit must pass the same compute units.
    mlmodel = ct.models.MLModel(str(OUT), compute_units=ct.ComputeUnit.CPU_AND_GPU)
    from PIL import Image
    img = Image.fromarray((example[0].permute(1, 2, 0).numpy() * 255).astype(np.uint8))
    # Undo the folded normalization for the comparison: feed torch the normalized
    # tensor Core ML will compute internally from the raw image.
    norm = (example - torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1)) \
        / torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)
    with torch.no_grad():
        want = Wrapper(model)(norm).numpy()
    t0 = time.time()
    got = mlmodel.predict({"image": img})["mask"]
    dt = time.time() - t0
    mae = float(np.abs(want - got).mean())
    print(f"Core ML predict: {dt * 1000:.0f} ms   MAE vs torch fp32: {mae:.4f}")


if __name__ == "__main__":
    main()
