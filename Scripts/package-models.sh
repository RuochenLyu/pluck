#!/usr/bin/env bash
#
# Packages the converted Core ML models as release assets and writes models/manifest.json.
#
# The manifest is the trust chain's middle link (product-plan §4.8): it ships inside the
# signed app and the CLI binary, and it pins each asset's URL, SHA256 and byte count. Those
# numbers must therefore describe bytes that actually exist — so they are generated here
# from the real zip rather than typed by hand.
#
#   Scripts/package-models.sh           # build zips + rewrite models/manifest.json
#   Scripts/package-models.sh --check   # hash the zips already in .build/models and
#                                       # fail if the manifest disagrees with them
#
# --check deliberately does not re-zip: ditto archives are not byte-reproducible (mtimes
# and directory order leak in), so the question worth asking is "does the manifest describe
# the asset I am about to upload", not "would a fresh zip hash the same".
#
# Inputs come from models/weights/ (gitignored; produced by Scripts/convert-birefnet.py).
# Outputs land in .build/models/ (gitignored) and are uploaded as release assets by hand.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-write}"
TAG="models-v1"
BASE_URL="https://github.com/RuochenLyu/pluck/releases/download/$TAG"
WEIGHTS="models/weights"
OUT=".build/models"
MANIFEST="models/manifest.json"

# id|bundle|display name|input side|source
MODELS=(
  "birefnet-lite|BiRefNetLite.mlpackage|BiRefNet_lite|1024|https://huggingface.co/ZhengPeng7/BiRefNet_lite"
  "birefnet-lite-matting|BiRefNetLiteMatting.mlpackage|BiRefNet_lite matting|1024|https://huggingface.co/ZhengPeng7/BiRefNet_lite-matting"
)

mkdir -p "$OUT"
entries=()

for spec in "${MODELS[@]}"; do
  IFS='|' read -r id bundle display side source <<<"$spec"
  src="$WEIGHTS/$bundle"
  zip="$OUT/$bundle.zip"

  if [[ "$MODE" == "--check" ]]; then
    if [[ ! -f "$zip" ]]; then
      echo "missing $zip — run Scripts/package-models.sh first" >&2
      exit 1
    fi
  else
    if [[ ! -d "$src" ]]; then
      echo "missing $src — run Scripts/convert-birefnet.py first" >&2
      exit 1
    fi
    # --keepParent so the archive carries the .mlpackage directory itself; ModelRegistry
    # extracts with the same tool and expects to find that name at the top level. ditto is
    # also the only packer that keeps the bundle's extended attributes intact.
    rm -f "$zip"
    ditto -c -k --keepParent "$src" "$zip"
  fi

  sha="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
  bytes="$(stat -f%z "$zip")"
  printf '%-24s %10s bytes  %s\n' "$id" "$bytes" "$sha"

  entries+=("$(cat <<JSON
    {
      "id": "$id",
      "displayName": "$display",
      "file": "$bundle",
      "url": "$BASE_URL/$bundle.zip",
      "sha256": "$sha",
      "bytes": $bytes,
      "license": "MIT",
      "source": "$source",
      "inputSide": $side
    }
JSON
)")
done

generated="$(
  printf '{\n  "version": 1,\n  "models": [\n'
  for index in "${!entries[@]}"; do
    printf '%s' "${entries[$index]}"
    if (( index < ${#entries[@]} - 1 )); then printf ',\n'; else printf '\n'; fi
  done
  printf '  ]\n}\n'
)"

if [[ "$MODE" == "--check" ]]; then
  if diff -u "$MANIFEST" <(printf '%s\n' "$generated"); then
    echo "manifest matches the packaged assets"
  else
    echo "manifest disagrees with .build/models — re-run Scripts/package-models.sh" >&2
    exit 1
  fi
else
  printf '%s\n' "$generated" >"$MANIFEST"
  echo "wrote $MANIFEST"
fi
