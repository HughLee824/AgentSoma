#!/usr/bin/env python3
"""Build the static website from an explicit list of public files."""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def build(output=None):
    output = (Path(output) if output else ROOT / "dist").resolve()
    if output == ROOT or output in ROOT.parents:
        raise ValueError("Build output must not replace the site source or its parents")
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)
    for name in ("index.html", "styles.css", "tokens.css", "site.js"):
        shutil.copyfile(ROOT / name, output / name)
    shutil.copytree(ROOT / "assets", output / "assets")
    # Return a real 404 instead of silently serving the landing page for missing files.
    (output / "404.html").write_text('<!doctype html><html lang="en"><meta charset="utf-8">'
                                   '<title>Page not found — AgentSoma</title><h1>Page not found</h1>'
                                   '<a href="/">Return to AgentSoma</a></html>')
    return output


if __name__ == "__main__":
    print(build())
