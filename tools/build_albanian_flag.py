"""Rasterise the Albanian flag for the flagpoles (LandmarkKit.albanian_flag).

tools/flag/albanian_flag.svg is Wikimedia Commons' File:Flag_of_Albania.svg
(public domain: a national flag), with the field set to the flag's official
red (#e41e20). Chromium (Playwright) draws it at 1024 x 732, the 5:7 flag.

    python3 tools/build_albanian_flag.py
"""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SVG = ROOT / 'tools/flag/albanian_flag.svg'
OUT = ROOT / 'godot/assets/textures/albanian_flag.png'
W, H = 1024, 732

SCRIPT = """
const { chromium } = require('playwright');
(async () => {
  const [svg, out, w, h] = JSON.parse(process.argv[1]);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  const sized = svg.replace(/<svg width="700" height="500"/, `<svg width="${w}" height="${h}" viewBox="0 0 700 500" preserveAspectRatio="none"`);
  await page.setContent(`<body style="margin:0">${sized}</body>`);
  await page.screenshot({ path: out, clip: { x: 0, y: 0, width: w, height: h } });
  await browser.close();
})();
"""


def main():
    args = json.dumps([SVG.read_text(encoding='utf8'), str(OUT), W, H])
    root = subprocess.run(['npm', 'root', '-g'], capture_output=True, text=True, check=True).stdout.strip()
    subprocess.run(['node', '-e', SCRIPT, args], check=True, env={**os.environ, 'NODE_PATH': root})
    print(f'{OUT.relative_to(ROOT)} {W}x{H}')


if __name__ == '__main__':
    main()
