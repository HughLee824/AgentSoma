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
| [agentsoma-wordmark.png](agentsoma-wordmark.png) | 960 × 210 | Transparent wordmark with the Soma symbol replacing the S |
| [agentsoma-wordmark-dark.svg](agentsoma-wordmark-dark.svg) | 960 × 210 | Light-colored rendering of the same wordmark for dark backgrounds |
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
`agentsoma-wordmark-dark.svg`, falling back to the original PNG in light mode.
The dark asset is a self-contained SVG wrapper embedding that exact PNG, with a
color filter that maps its RGB channels to `#f0f6fc` and preserves its alpha.
It is not a vector tracing or a regenerated logo. If the source wordmark changes,
update the embedded PNG and its source checksum in the dark wrapper and manifest.

The original symbol was generated with ImageGen and refined once. The PNG and
ICO files are the existing raster exports, preserved byte for byte. The project
owner separately converted and supplied `agent-soma.svg`; that file is also
preserved unchanged. The raster exports were not regenerated from the SVG, and
the SVG retains its supplied viewBox and positioning.

The wordmark uses Geist Mono, weight 600. The font's
[SIL Open Font License](licenses/geist-mono-OFL.txt) is retained for reference;
font binaries are not bundled here. The license text describes the font, not a
separate license grant for the AgentSoma logo.

## App Icon and maintenance

The iOS build uses a copy of `soma-github-icon.png` at
[`Runner/Assets.xcassets/AppIcon.appiconset/AppIcon.png`](../../Runner/Assets.xcassets/AppIcon.appiconset/AppIcon.png).
Keep these two files identical when changing the square icon. The asset catalog
and Runner build configuration remain in `Runner/`; they are app-specific.

[`manifest.json`](manifest.json) records the shipped images and font license,
including sizes, formats, and SHA-256 checksums. Update it when replacing assets.
Old concepts, original generation files, prompts, review images, and ZIP exports
remain in the ignored local `output/` directory. Builds do not depend on it.
