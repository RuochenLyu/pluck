#!/usr/bin/env bash
# Fetch rembg's own example images and measure how far our engine lands from theirs.
#
# rembg is the de-facto open-source baseline for background removal, and these are the
# images its README uses to show itself off — which makes them the fairest place to be
# compared, because they were not chosen by us. Its `.out.png` files are not ground truth,
# only a second opinion; a low IoU means the two engines disagree, and which one is right
# is a question for eyes, not for this script.
#
# Everything lands in qa/rembg/, which is gitignored: the images are other people's, and
# a repo is not a place to mirror them.
#
# Usage: Scripts/qa-benchmark.sh   (needs curl and ImageMagick)
set -euo pipefail

cd "$(dirname "$0")/.."
root="qa/rembg"
remote="https://raw.githubusercontent.com/danielgatis/rembg/main/examples"
names=(girl-1 girl-2 girl-3 animal-1 animal-2 animal-3 car-1 car-2 car-3
       anime-girl-1 anime-girl-2 anime-girl-3 plants-1)

command -v magick >/dev/null || { echo "needs ImageMagick: brew install imagemagick" >&2; exit 1; }

mkdir -p "$root"/{in,ref,pluck,sheet}
echo "==> fetching ${#names[@]} examples from rembg"
for n in "${names[@]}"; do
    [ -s "$root/in/$n.jpg" ]  || curl -sfL -o "$root/in/$n.jpg"  "$remote/$n.jpg"
    [ -s "$root/ref/$n.png" ] || curl -sfL -o "$root/ref/$n.png" "$remote/$n.out.png"
done

echo "==> building the CLI"
swift build --product pluck >/dev/null
cli=".build/debug/pluck"

echo "==> plucking"
for n in "${names[@]}"; do
    "$cli" "$root/in/$n.jpg" -o "$root/pluck/$n.png" --force --json >/dev/null
done

# Magenta rather than a checkerboard: a flat colour no photograph contains makes a missed
# halo obvious at a glance, which a grey grid does not.
echo "==> contact sheets (input | rembg | pluck)"
for n in "${names[@]}"; do
    magick \
        \( "$root/in/$n.jpg" -resize 320x320 \) \
        \( "$root/ref/$n.png"   -background magenta -flatten -resize 320x320 \) \
        \( "$root/pluck/$n.png" -background magenta -flatten -resize 320x320 \) \
        +append -bordercolor white -border 4 "$root/sheet/$n.png"
done

echo "==> agreement with rembg (IoU of the binarised alpha)"
for n in "${names[@]}"; do
    magick "$root/ref/$n.png"   -alpha extract -threshold 50% "$root/.a.png"
    magick "$root/pluck/$n.png" -alpha extract -threshold 50% "$root/.b.png"
    i=$(magick "$root/.a.png" "$root/.b.png" -compose Darken  -composite -format "%[fx:mean]" info:)
    u=$(magick "$root/.a.png" "$root/.b.png" -compose Lighten -composite -format "%[fx:mean]" info:)
    a=$(magick "$root/.a.png" -format "%[fx:mean]" info:)
    b=$(magick "$root/.b.png" -format "%[fx:mean]" info:)
    python3 -c "print(f'  {\"$n\":14} IoU {$i/$u*100 if $u else 0:5.1f}%   foreground rembg {$a*100:5.1f}%  pluck {$b*100:5.1f}%')"
done
rm -f "$root/.a.png" "$root/.b.png"

echo "==> sheets in $root/sheet/"
