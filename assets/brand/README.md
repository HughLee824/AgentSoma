# AgentSoma brand assets

The current AgentSoma identity uses the Soma symbol: a head above an S-shaped
body. This directory contains the selected production assets from 2026-09-08.
Use it as the shared source for branding across the app, documentation, and web.

## Files

| File | Size | Use |
| --- | --- | --- |
| [agent-soma.svg](agent-soma.svg) | 1254 × 1254 viewBox | Vector symbol converted and supplied by the project owner |
| [soma-mark.png](soma-mark.png) | 1024 × 1024 | Transparent symbol |
| [soma-mark-256.png](soma-mark-256.png) | 256 × 256 | Small transparent symbol |
| [soma-github-icon.png](soma-github-icon.png) | 1024 × 1024 | Opaque white square for avatars and the iOS App Icon |
| [agentsoma-wordmark.svg](agentsoma-wordmark.svg) | 960 × 210 | Path-only wordmark for light backgrounds |
| [agentsoma-wordmark-dark.svg](agentsoma-wordmark-dark.svg) | 960 × 210 | Identical vector geometry with light-colored paths for dark backgrounds |
| [agentsoma-wordmark-source.svg](agentsoma-wordmark-source.svg) | 960 × 210 | Editable `Agent` + symbol + `oma` composition; requires Geist Mono |
| [agentsoma-wordmark.png](agentsoma-wordmark.png) | 960 × 210 | Original transparent raster wordmark retained as the layout reference |
| [agentsoma-lockup.png](agentsoma-lockup.png) | 1200 × 240 | Transparent separate symbol and full-name combination |
| [agentsoma-readme.png](agentsoma-readme.png) | 1200 × 300 | White-background separate symbol and full-name combination |
| `favicon-{16,32,48,64}.png` | Named pixel dimensions | White-background browser icons |
| [favicon.ico](favicon.ico) | 16, 32, 48, 64, 256 px | Multi-resolution browser icon |

## Usage and provenance

Preserve each asset's proportions and clear space. Transparent black artwork is
intended for light backgrounds. Use the white-background exports when needed.
For the integrated wordmark, 32 px display height is the recommended starting
point; supply `AgentSoma` as its accessible name.

The project READMEs use `<picture>` with `prefers-color-scheme: dark` to select
`agentsoma-wordmark-dark.svg`, falling back to `agentsoma-wordmark.svg` in light
mode. Both production SVGs contain only vector paths, using `#171717` and
`#f0f6fc` respectively. There are no embedded bitmaps, filters, or font dependencies.

The editable source uses SVG `<text>` elements for `Agent` and `oma`, with the
two paths from the project owner's `agent-soma.svg` between them. It requires
Geist Mono SemiBold to display the intended lettering. The production versions
convert the font's glyph outlines to paths, preserving the original PNG's
180 px type size, character spacing, baseline, symbol placement, and canvas.

The original symbol was generated with ImageGen and refined once. The PNG and
ICO files are the existing raster exports, preserved byte for byte. The project
owner separately converted and supplied `agent-soma.svg`; that file is also
preserved unchanged. The raster exports were not regenerated from the SVG, and
the SVG retains its supplied viewBox and positioning.

The wordmark uses Geist Mono, weight 600. The font's
[SIL Open Font License](licenses/geist-mono-OFL.txt) is retained for reference;
font binaries are not bundled here. The license text describes the font, not a
separate license grant for the AgentSoma logo.

To regenerate the editable composition and both production SVGs, run from the
repository root with Python and `fonttools[woff]` installed:

```sh
python3 scripts/export-brand-wordmark.py /path/to/geist-mono.woff2
```

The current outlines use Geist Mono version 1.701. The generator also updates
the manifest's checksums and font provenance. Review the result visually when
changing the font or symbol; the source font checksum is recorded in the manifest.

## App Icon and maintenance

The iOS build uses a copy of `soma-github-icon.png` at
[`Runner/Assets.xcassets/AppIcon.appiconset/AppIcon.png`](../../Runner/Assets.xcassets/AppIcon.appiconset/AppIcon.png).
Keep these two files identical when changing the square icon. The asset catalog
and Runner build configuration remain in `Runner/`; they are app-specific.

[`manifest.json`](manifest.json) records the shipped images and font license,
including sizes, formats, and SHA-256 checksums. Update it when replacing assets.
Old concepts, original generation files, prompts, review images, and ZIP exports
remain in the ignored local `output/` directory. Builds do not depend on it.
