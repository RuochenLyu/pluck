#!/usr/bin/env python3
"""Every candidate engine over every test image, on one labelled sheet per image.

Engines: Apple Vision (via the built pluck CLI), our BiRefNet_lite Core ML
conversion, and the four Apache-2.0 ONNX baselines fetched by fetch-models.sh.
Images: rembg's 13 official examples plus the project's own fixtures.

The sheets are the deliverable — IoU against rembg is only agreement, not truth,
so every column carries the model's name and the eyes do the judging.

Run inside the spike venv:  .venv/bin/python Scripts/qa-model-matrix.py
Outputs: qa/matrix/<engine>/<image>.png cutouts, qa/matrix/sheet/<image>.png sheets.
"""

import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
WEIGHTS = ROOT / "models" / "weights"
OUT = ROOT / "qa" / "matrix"
TILE = 300

IMAGES = sorted((ROOT / "qa" / "rembg" / "in").glob("*.jpg")) + sorted(
    p for p in (ROOT / "Tests" / "Fixtures").glob("*.jpg")
)

# name -> (weights file, input side, normalization)
ONNX_MODELS = {
    "u2net": ("u2net.onnx", 320, "imagenet"),
    "u2netp": ("u2netp.onnx", 320, "imagenet"),
    "silueta": ("silueta.onnx", 320, "imagenet"),
    "isnet": ("isnet-general-use.onnx", 1024, "half"),
}


def onnx_mask(session, side, norm, image):
    small = image.resize((side, side), Image.LANCZOS)
    arr = np.asarray(small, dtype=np.float32) / 255.0
    if norm == "imagenet":
        arr = (arr - [0.485, 0.456, 0.406]) / [0.229, 0.224, 0.225]
    else:
        arr = arr - 0.5
    arr = arr.transpose(2, 0, 1)[None].astype(np.float32)
    pred = session.run(None, {session.get_inputs()[0].name: arr})[0][0, 0]
    lo, hi = pred.min(), pred.max()
    if hi > lo:
        pred = (pred - lo) / (hi - lo)
    return Image.fromarray((pred * 255).astype(np.uint8)).resize(image.size, Image.LANCZOS)


def cutout(image, mask):
    out = image.copy()
    out.putalpha(mask)
    return out


def main():
    for sub in ["vision", *[p.stem for p in WEIGHTS.glob("*.mlpackage")], *ONNX_MODELS, "sheet"]:
        (OUT / sub).mkdir(parents=True, exist_ok=True)

    subprocess.run(["swift", "build", "--product", "pluck"], cwd=ROOT, check=True,
                   capture_output=True)
    cli = ROOT / ".build" / "debug" / "pluck"

    import coremltools as ct
    import onnxruntime as ort

    # Every converted variant joins the line-up automatically.
    coreml_models = {
        p.stem: ct.models.MLModel(
            str(p),
            # ANE cannot compile the deform-conv gather chain; see convert-birefnet.py.
            compute_units=ct.ComputeUnit.CPU_AND_GPU,
        )
        for p in sorted(WEIGHTS.glob("*.mlpackage"))
    }
    sessions = {
        name: (ort.InferenceSession(str(WEIGHTS / f), providers=["CPUExecutionProvider"]), side, norm)
        for name, (f, side, norm) in ONNX_MODELS.items()
    }

    timings = {}
    for src_path in IMAGES:
        name = src_path.stem
        image = Image.open(src_path).convert("RGB")
        tiles = [("input", src_path)]

        vision_out = OUT / "vision" / f"{name}.png"
        r = subprocess.run([cli, src_path, "-o", vision_out, "--force"],
                           cwd=ROOT, capture_output=True)
        if r.returncode == 0:
            tiles.append(("vision (Apple)", vision_out))
        else:
            # Exit 2 = no subject found. An empty magenta tile says that honestly.
            Image.new("RGBA", image.size, (0, 0, 0, 0)).save(vision_out)
            tiles.append(("vision: no subject", vision_out))

        for ml_name, ml in coreml_models.items():
            t0 = time.time()
            pred = ml.predict({"image": image.resize((1024, 1024), Image.LANCZOS)})["mask"]
            timings.setdefault(ml_name, []).append(time.time() - t0)
            mask = Image.fromarray((pred[0, 0] * 255).astype(np.uint8)).resize(image.size, Image.LANCZOS)
            p = OUT / ml_name / f"{name}.png"
            cutout(image, mask).save(p)
            tiles.append((f"{ml_name} (CoreML)", p))

        for model, (session, side, norm) in sessions.items():
            t0 = time.time()
            mask = onnx_mask(session, side, norm, image)
            timings.setdefault(model, []).append(time.time() - t0)
            p = OUT / model / f"{name}.png"
            cutout(image, mask).save(p)
            tiles.append((model, p))

        args = ["magick", "montage"]
        for label, path in tiles:
            args += ["-label", label, str(path)]
        args += ["-tile", f"{len(tiles)}x1", "-geometry", f"{TILE}x{TILE}+4+4",
                 "-background", "magenta", "-fill", "black", "-pointsize", "16",
                 str(OUT / "sheet" / f"{name}.png")]
        subprocess.run(args, check=True)
        print(f"sheet: {name}")

    print("\nwarm inference, mean over all images:")
    for model, ts in timings.items():
        print(f"  {model:14} {np.mean(ts[1:] if len(ts) > 1 else ts) * 1000:6.0f} ms")


if __name__ == "__main__":
    main()
