#!/usr/bin/env python3
"""Compose the Soma SVG with Geist Mono text and export portable path-only logos.

Usage: python3 scripts/export-brand-wordmark.py /path/to/geist-mono.woff2
Requires fonttools[woff]. The font itself is not copied into the repository.
"""

import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


ROOT = Path(__file__).resolve().parents[1] / "assets/brand"
SVG = "{http://www.w3.org/2000/svg}"
# Original 960 × 210 PNG layout: 180 px type, -0.045 em tracking, rounded
# 100 px character advances, baseline y=165, and a 109 × 151 px symbol box.
RUNS = (("Agent", 19), ("oma", 638))


def number(value):
    return f"{value:.4f}".rstrip("0").rstrip(".") or "0"


def document(content, ink, description):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="960" height="210" '
        'viewBox="0 0 960 210" role="img" aria-labelledby="title desc">\n'
        '  <title id="title">AgentSoma</title>\n'
        f'  <desc id="desc">{description}</desc>\n'
        f'  <g fill="{ink}">\n{content}\n  </g>\n</svg>\n'
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("font", type=Path)
    args = parser.parse_args()
    font = TTFont(args.font)
    if font["name"].getDebugName(1) != "Geist Mono":
        raise ValueError("Use the Geist Mono variable font from the original wordmark")
    font = instantiateVariableFont(font, {"wght": 600})
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = 180 / font["head"].unitsPerEm

    symbol = ROOT / "agent-soma.svg"
    paths = ET.parse(symbol).getroot().findall(f"{SVG}path")
    if len(paths) != 2:
        raise ValueError("Expected the supplied head and body paths in agent-soma.svg")
    # Map the original raster crop (375, 145, 1072, 1109) to its existing
    # 109 × 151 layout box. Preserve the supplied vector contours verbatim.
    mark = (
        '    <g aria-label="Soma symbol" transform="translate(528 16) '
        f'scale({109 / 697:.10f} {151 / 964:.10f}) translate(-375 -145)">\n'
        + "\n".join(f'      <path d="{" ".join(p.attrib["d"].split())}"/>' for p in paths)
        + "\n    </g>"
    )
    outlined = []
    editable = []
    for text, left in RUNS:
        outlined.append(f'    <g aria-label="{text}">')
        for index, char in enumerate(text):
            pen = SVGPathPen(glyphs, ntos=number)
            transform = (scale, 0, 0, -scale, left + index * 100, 165)
            glyphs[cmap[ord(char)]].draw(TransformPen(pen, transform))
            outlined.append(f'      <path d="{pen.getCommands()}"/>')
        outlined.append("    </g>")
        positions = " ".join(str(left + index * 100) for index in range(len(text)))
        editable.append(
            f'    <text x="{positions}" y="165" font-family="Geist Mono, monospace" '
            f'font-size="180" font-weight="600">{text}</text>'
        )

    portable = "\n".join(outlined + [mark])
    description = "Geist Mono lettering and the supplied Soma symbol, all drawn as vector paths."
    exports = {
        "agentsoma-wordmark.svg": document(portable, "#171717", description),
        "agentsoma-wordmark-dark.svg": document(portable, "#f0f6fc", description),
        "agentsoma-wordmark-source.svg": document(
            "\n".join(editable + [mark]), "#171717",
            "Editable Agent and oma text with the supplied Soma symbol. Requires Geist Mono SemiBold.",
        ),
    }
    manifest_path = ROOT / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["provenance"]["vector_wordmark"] = {
        "symbol": symbol.name,
        "symbol_sha256": hashlib.sha256(symbol.read_bytes()).hexdigest(),
        "font_family": "Geist Mono",
        "font_weight": 600,
        "font_version": font["name"].getDebugName(5),
        "font_sha256": hashlib.sha256(args.font.read_bytes()).hexdigest(),
        "generator": "scripts/export-brand-wordmark.py",
        "layout_reference": "agentsoma-wordmark.png",
    }
    manifest["files"] = [entry for entry in manifest["files"] if entry["path"] not in exports]
    for name, content in exports.items():
        (ROOT / name).write_text(content)
        data = (ROOT / name).read_bytes()
        manifest["files"].append({
            "path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "format": "SVG", "viewBox": [0, 0, 960, 210],
            "rendering": "Editable text and vector symbol paths; requires Geist Mono" if "-source" in name
                         else "Vector paths only; no embedded images, filters, or font dependencies",
        })
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
