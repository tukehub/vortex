"""Build the Vlorë rock library from checksum-pinned Poly Haven geometry."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parents[1]
sys.path.insert(0, str(TOOLS))
from fetch_cc0_assets import fetch_cached  # noqa: E402


def stage_scan(scan, root):
    folder = root / scan["id"]
    folder.mkdir()
    for ref in scan["files"]:
        name = "source.gltf" if ref["path"] == "gltf" else ref["path"]
        (folder / name).write_bytes(fetch_cached(ref["url"], ref["md5"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path,
                        default=TOOLS.parent / "godot/assets/cities/vlore/rock_scans.glb")
    args = parser.parse_args()
    manifest = HERE / "sources.json"
    scans = json.loads(manifest.read_text())["sources"]
    with tempfile.TemporaryDirectory(prefix="vortex-rocks-") as tmp:
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda scan: stage_scan(scan, Path(tmp)), scans))
        subprocess.run(["node", str(HERE / "bake.mjs"), str(manifest), tmp, str(args.out.resolve())],
                       check=True)


if __name__ == "__main__":
    main()
