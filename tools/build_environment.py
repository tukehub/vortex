#!/usr/bin/env python3
"""Build Godot-ready mobile GLB LODs from Poly Haven CC0 scans."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from fetch_cc0_assets import CACHE, _safe_rel, fetch_cached, pack_glb, resolve_polyhaven

TOOLS = Path(__file__).resolve().parent
CONFIG = TOOLS / "environment" / "assets.json"
LICENCE = "https://polyhaven.com/license"


def validate(asset: dict) -> str:
    if not re.fullmatch(r"[a-z0-9_]+", asset["id"]):
        raise ValueError("Expected a Poly Haven asset ID.")
    resolution = asset.get("resolution", "1k")
    if resolution not in ("1k", "2k"):
        raise ValueError("Only 1k and 2k source textures are supported.")
    if resolution == "2k" and (
        asset.get("major_landmark") is not True or not asset.get("resolution_reason", "").strip()
    ):
        raise ValueError("2k requires major_landmark=true and a visible-quality resolution_reason.")
    triangles = asset["triangles"]
    if len(triangles) != 3 or any(type(n) is not int or n < 1 for n in triangles) or not (
        triangles[0] > triangles[1] > triangles[2]
    ):
        raise ValueError("Provide three positive, decreasing triangle budgets.")
    errors = asset.get("errors", [0.01, 0.02, 0.04])
    if len(errors) != 3 or not 0 < errors[0] <= errors[1] <= errors[2] <= 1:
        raise ValueError("Provide three non-decreasing relative error limits from 0 to 1.")
    return resolution


def stage_source(asset: dict, resolution: str, directory: Path) -> tuple[Path, dict]:
    [model], meta = resolve_polyhaven({**asset, "key": asset["id"], "kind": "model"}, resolution)
    source = directory / "source.gltf"
    parts = {_safe_rel(part["rel"]): part for part in model["parts"]}
    source_bytes = fetch_cached(model["url"], model["md5"])
    gltf = json.loads(source_bytes)
    source.write_bytes(source_bytes)

    # Poly Haven may store a shared geometry buffer under an 8k URL. Image URLs
    # must come from the selected 1k/2k tier and every file must be in the API list.
    def stage(item: dict, is_image: bool) -> dict:
        uri = _safe_rel(item["uri"])
        part = parts[uri]
        if is_image and f"/{resolution}/" not in part["url"]:
            raise ValueError(f"Image is outside the requested source tier: {part['url']}")
        data = fetch_cached(part["url"], part["md5"])
        path = directory / uri
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return {"path": uri, "url": part["url"], "md5": part["md5"], "bytes": len(data)}

    with ThreadPoolExecutor(max_workers=4) as pool:
        jobs = [pool.submit(stage, item, is_image)
                for is_image, group in ((False, "buffers"), (True, "images"))
                for item in gltf.get(group, [])]
        files = [job.result() for job in jobs]
    files.insert(0, {"path": source.name, "url": model["url"], "md5": model["md5"],
                     "bytes": len(source_bytes)})
    return source, {**meta, "provider": "Poly Haven", "id": asset["id"],
                    "license": "CC0-1.0", "license_url": LICENCE, "files": files}


def texture_import(path: Path, role: str, resolution: int) -> None:
    path.with_suffix(path.suffix + ".import").write_text(
        '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
        'compress/mode=2\ncompress/high_quality=true\n'
        f'compress/normal_map={1 if role == "normal" else 2}\n'
        'mipmaps/generate=true\n'
        f'process/size_limit={resolution}\n'
        'detect_3d/compress_to=0\n',
        encoding="utf-8",
    )


def scene_import(path: Path) -> None:
    path.with_suffix(".glb.import").write_text(
        '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
        'meshes/ensure_tangents=true\nmeshes/generate_lods=false\n'
        'meshes/create_shadow_meshes=false\nanimation/import=false\n',
        encoding="utf-8",
    )


def write_package(intermediate: Path, package: Path, source_meta: dict, asset: dict, resolution: str) -> dict:
    geometry = json.loads((intermediate / "geometry.json").read_text())
    textures = {}
    for index, lod in enumerate(geometry["levels"]):
        document = json.loads((intermediate / f"lod{index}.gltf").read_text())
        for image in document["images"]:
            uri = image["uri"]
            if uri not in textures:
                textures[uri] = geometry["textureFiles"][uri]
                path = package / uri
                shutil.copyfile(intermediate / uri, path)
                texture_import(path, textures[uri]["role"], int(resolution[0]) * 1024)
        buffers = {buf["uri"]: (intermediate / buf["uri"]).read_bytes() for buf in document["buffers"]}
        for buf in document["buffers"]:
            if len(buffers[buf["uri"]]) != buf["byteLength"]:
                raise ValueError(f'LOD{index}: binary buffer does not match its declared size.')
        path = package / f'{asset["id"]}_lod{index}.glb'
        path.write_bytes(pack_glb(document, buffers.__getitem__, embed_images=False))
        scene_import(path)
        lod["file"] = path.name
    files = {path.name: {"bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
             for path in sorted(package.iterdir()) if path.suffix != ".import"}
    return {
        "source": source_meta,
        "texture_tier": resolution,
        "resolution_reason": asset.get("resolution_reason"),
        "lock_border": asset.get("lock_border", False),
        "source_geometry": geometry["original"],
        "lods": geometry["levels"],
        "textures": textures,
        "files": files,
        "total_bytes": sum(entry["bytes"] for entry in files.values()),
    }


def build(asset: dict, output: Path) -> dict:
    resolution = validate(asset)
    if output.exists():
        raise FileExistsError(f"{output} already exists. Choose a fresh output directory.")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".environment-", dir=output.parent) as temp:
        stage = Path(temp)
        raw, intermediate, package = (stage / name for name in ("source", "intermediate", "package"))
        for directory in (raw, intermediate, package):
            directory.mkdir()
        source, meta = stage_source(asset, resolution, raw)
        settings = stage / "settings.json"
        settings.write_text(json.dumps({
            "resolution": int(resolution[0]) * 1024,
            "triangles": asset["triangles"],
            "errors": asset.get("errors", [0.01, 0.02, 0.04]),
            "lock_border": asset.get("lock_border", False),
        }))
        subprocess.run(["node", str(TOOLS / "environment" / "optimize.mjs"), str(source),
                        str(intermediate), str(settings)], check=True)
        report = write_package(intermediate, package, meta, asset, resolution)
        (package / "environment-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        os.rename(package, output)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("asset", help="Entry from the manifest")
    parser.add_argument("--manifest", type=Path, default=CONFIG)
    parser.add_argument("--out", type=Path, help="New package directory (defaults to tools/cache/environment/ASSET)")
    args = parser.parse_args()
    try:
        asset = json.loads(args.manifest.read_text())[args.asset]
        output = (args.out or CACHE.parent / "environment" / args.asset).resolve()
        report = build(asset, output)
    except (LookupError, OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Environment build failed: {error}\n")
    print(f'{output}: {report["total_bytes"]:,} bytes across GLBs and shared textures')


if __name__ == "__main__":
    main()
