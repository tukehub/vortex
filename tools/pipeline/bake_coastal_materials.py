"""Bake Vlorë's 1K colour and packed PBR atlases from pinned CC0 sources."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import io
import json
from pathlib import Path
import sys

from PIL import Image
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from fetch_cc0_assets import fetch_cached  # noqa: E402

TILE = 512
OUT = HERE.parents[1] / "godot/assets/cities/vlore"


def layer(source):
    images = {}
    for role, ref in source["maps"].items():
        data = fetch_cached(ref["url"], ref["md5"])
        with Image.open(io.BytesIO(data)) as image:
            if image.size != (1024, 1024):
                raise ValueError(f"{source['id']} {role} is not the pinned 1K source")
            mode = "RGB" if role in ("albedo", "normal") else "L"
            images[role] = image.convert(mode).resize((TILE, TILE), Image.Resampling.LANCZOS)
    nx, ny, _ = images["normal"].split()
    data = Image.merge("RGBA", (nx, ny, images["roughness"], images["height"]))
    linear = (np.asarray(images["albedo"], dtype=np.float32) / 255.0) ** 2.2
    print(source["role"], "linear albedo mean", tuple(round(float(x), 3) for x in linear.mean(axis=(0, 1))))
    return images["albedo"], data


def bake(directory):
    sources = json.loads((HERE / "coastal_materials.json").read_text())["layers"]
    palette = Image.new("RGB", (2*TILE, 2*TILE))
    packed = Image.new("RGBA", palette.size)
    with ThreadPoolExecutor(max_workers=4) as pool:
        for i, (colour, data) in enumerate(pool.map(layer, sources)):
            offset = (i % 2 * TILE, i // 2 * TILE)
            palette.paste(colour, offset)
            packed.paste(data, offset)
    directory.mkdir(parents=True, exist_ok=True)
    palette.save(directory / "ground_layers.jpg", quality=90, subsampling=0, optimize=True)
    # Six-bit channels are within two 8-bit values of the source. Keep
    # them lossless after quantizing so colour subsampling cannot affect data.
    pixels = np.asarray(packed).astype(np.uint16)
    quantized = np.minimum((pixels + 2) // 4 * 4, 255).astype(np.uint8)
    Image.fromarray(quantized).save(directory / "ground_layers_pbr.webp",
                                  lossless=True, quality=80, method=4, exact=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=OUT)
    bake(parser.parse_args().out)
