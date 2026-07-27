# Test fixture image sources

QA fixtures for the Pluck background-removal engine. Every image below is CC0 /
public domain and was verified via [Openverse](https://openverse.org) (which
surfaces the `license` field from the original provider) before download.
None of these are Unsplash- or Pexels-licensed — those licenses restrict
redistribution and are excluded per project policy (see `AGENTS.md`).

All files were downloaded with `curl -L`, validated with
`sips -g pixelWidth -g pixelHeight`, then normalized to JPEG with `sips`
(longest side capped at 2000px; only `fur-02.jpg` needed actual downscaling,
from 1536x2048 — all others were left at their native resolution to avoid
fake upscaling).

| File | Category | Source URL | Author | License | Downloaded |
|---|---|---|---|---|---|
| hair-01.jpg | Hair-detail portrait | https://stocksnap.io/photo/beautiful-woman-ALVGSSERRY | Lucas Allmann | CC0 1.0 | 2026-07-27 |
| hair-02.jpg | Hair-detail portrait | https://www.flickr.com/photos/135396164@N05/29336240643 ("Girl's head silhouette at sunset") | freestocks.org | CC0 1.0 | 2026-07-27 |
| fur-01.jpg | Furry animal | https://www.flickr.com/photos/132795455@N08/17126803327 ("Fluffy Cat Laying on a Wooden Deck") | Image Catalog | CC0 1.0 | 2026-07-27 |
| fur-02.jpg | Furry animal | https://wordpress.org/photos/photo/15269052c2/ (close-up profile of a brown fluffy-coated dog) | emq11 | CC0 1.0 | 2026-07-27 |
| glass-01.jpg | Glass / translucent object | https://www.flickr.com/photos/29507259@N02/3550422689 ("Wine glass in front of window flash") | D Coetzee | CC0 1.0 | 2026-07-27 |
| glass-02.jpg | Glass / translucent object | https://www.flickr.com/photos/132795455@N08/21911441615 ("Wine Glass with Red Wine") | Image Catalog | CC0 1.0 | 2026-07-27 |
| multi-01.jpg | Multiple subjects | https://www.flickr.com/photos/134242952@N03/20080635509 ("Years Later" — three women at a railing) | Never Edit | CC0 1.0 | 2026-07-27 |
| multi-02.jpg | Multiple subjects | https://stocksnap.io/photo/couple-park-GL9XJQTLJK ("Couple Park") | Senior Living | CC0 1.0 | 2026-07-27 |
| nosubject-01.jpg | No subject (landscape) | https://stocksnap.io/photo/rural-road-CI1WRFNDF0 ("Rural Road") | Tricia Gray | CC0 1.0 | 2026-07-27 |
| nosubject-02.jpg | No subject (landscape) | https://stocksnap.io/photo/rural-road-EIJ1CAOGVO ("Rural Road") | Sergei Gussev | CC0 1.0 | 2026-07-27 |
| product-01.jpg | Product on plain background | https://stocksnap.io/photo/juice-drinks-E30B9YV1OR ("Juice Drinks" — teapot pouring onto a mug, solid blue background) | Filip Mroz | CC0 1.0 | 2026-07-27 |
| product-02.jpg | Product on plain background | https://stocksnap.io/photo/mug-cup-MVYHPT6H7C ("Mug Cup") | Candace McDaniel | CC0 1.0 | 2026-07-27 |

## Notes

- License verification method: queried the [Openverse API](https://api.openverse.org/v1/images/)
  with `license=cc0`, which reports the `license`, `license_version`, and
  `license_url` (`https://creativecommons.org/publicdomain/zero/1.0/`) as
  declared by the origin provider (Flickr, StockSnap, WordPress Photo
  Directory). For Wikimedia Commons candidates, license was cross-checked via
  the Commons `imageinfo|extmetadata` API (`LicenseShortName` field).
- Candidates rejected over licensing ambiguity:
  - Several Wikimedia Commons portrait/painting results returned `Public
    domain` for old paintings (not photographs) or `CC BY` / `CC BY-SA`
    (attribution-required) — skipped since they don't meet the CC0 bar or
    aren't representative photographs.
  - rawpixel.com results were avoided even when tagged `cc0` by Openverse:
    rawpixel frequently re-hosts Unsplash-derived images under its own
    "public domain" labeling without a clear original-source chain, which is
    exactly the re-distribution ambiguity this fixture set is meant to avoid.
  - A Wikimedia Commons portrait of a named living person ("Danyel Smith",
    CC0) was skipped in favor of anonymous subjects, to avoid any personality-
    rights complications even though the copyright license is clear.
- All images fit comfortably under the 2MB/file and 15MB/set budget; see
  `du -sh Tests/Fixtures` (~2.7MB total for all 12 images).
