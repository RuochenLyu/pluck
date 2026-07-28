#!/usr/bin/env bash
# Fetch the model weights v0.3 needs, plus the baselines worth measuring against.
#
# Nothing here goes into the app bundle and nothing here goes into git — weights land in
# models/weights/, which is gitignored. The app downloads its own model on demand at
# runtime (product-plan §4.8); this script is for the maintainer's machine, so the Core ML
# conversion spike and the benchmark runs have something to work with offline.
#
# Licence is the gate, not size. Anything BRIA-derived (RMBG-1.4 OpenRAIL-M, RMBG-2.0
# CC BY-NC) is deliberately absent and must stay absent — see docs/research.md §2.2.
#
#   Scripts/fetch-models.sh            # the one model we plan to ship  (~383 MB)
#   Scripts/fetch-models.sh baselines  # + the engines we measure against (~385 MB)
#   Scripts/fetch-models.sh all
set -euo pipefail

cd "$(dirname "$0")/.."
out="models/weights"
mkdir -p "$out"
what="${1:-shipping}"

# name|url|expected MB|licence
shipping=(
  "birefnet_lite.safetensors|https://huggingface.co/ZhengPeng7/BiRefNet_lite/resolve/main/model.safetensors|169|MIT"
  "birefnet_lite.onnx|https://huggingface.co/onnx-community/BiRefNet_lite-ONNX/resolve/main/onnx/model.onnx|214|MIT"
)
# rembg's own weights, which is what the published .out.png files were made with. Having
# them locally is what makes a run over DIS-VD possible — comparing 470 images against a
# competitor needs the competitor, not screenshots of it.
baselines=(
  "u2net.onnx|https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx|168|Apache-2.0"
  "u2netp.onnx|https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx|4|Apache-2.0"
  "isnet-general-use.onnx|https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx|170|Apache-2.0"
  "silueta.onnx|https://github.com/danielgatis/rembg/releases/download/v0.0.0/silueta.onnx|42|Apache-2.0"
)

case "$what" in
  shipping)  set -- "${shipping[@]}" ;;
  baselines) set -- "${baselines[@]}" ;;
  all)       set -- "${shipping[@]}" "${baselines[@]}" ;;
  *) echo "usage: $0 [shipping|baselines|all]" >&2; exit 1 ;;
esac

# The conversion spike (Scripts/convert-birefnet.py) needs the model *code* too,
# not just weights: birefnet.py defines the architecture the safetensors load into.
if [ "$what" != "baselines" ]; then
    src="models/birefnet_lite_src"
    mkdir -p "$src"
    for f in config.json birefnet.py BiRefNet_config.py; do
        [ -s "$src/$f" ] || curl -sfL -o "$src/$f" \
            "https://huggingface.co/ZhengPeng7/BiRefNet_lite/resolve/main/$f"
    done
    ln -sf ../weights/birefnet_lite.safetensors "$src/model.safetensors"
fi

for entry in "$@"; do
    IFS='|' read -r name url mb licence <<<"$entry"
    target="$out/$name"
    if [ -s "$target" ]; then
        echo "have  $name"
        continue
    fi
    echo "==> $name  (~${mb} MB, $licence)"
    curl -fL --progress-bar -o "$target.part" "$url"
    mv "$target.part" "$target"
done

echo
echo "==> $out"
if command -v shasum >/dev/null; then
    # Recorded now so a later re-download can be shown to be the same bytes; the manifest
    # the app ships in v0.3 will carry these same digests.
    ( cd "$out" && shasum -a 256 ./*.safetensors ./*.onnx 2>/dev/null | tee SHA256SUMS )
fi
du -sh "$out"
