#!/usr/bin/env python3
"""Fetch the curated CC0 textures, HDRIs and models into the Godot project.

Sources are Poly Haven (api.polyhaven.com) and ambientCG (ambientcg.com/api/v2),
both CC0 1.0. Nothing is downloaded unless --download is given:

    python3 tools/fetch_cc0_assets.py                    # print the manifest (offline)
    python3 tools/fetch_cc0_assets.py --check            # resolve URLs and sizes (API metadata only)
    python3 tools/fetch_cc0_assets.py --download         # fetch every entry
    python3 tools/fetch_cc0_assets.py --download --only sand,limestone,sky_rain_night
    python3 tools/fetch_cc0_assets.py --download --tier 1
    python3 tools/fetch_cc0_assets.py --download --res 2k --force

Output naming follows the existing assets:
    textures  godot/assets/textures/<key>_{diff,nor,rough,arm,metal,ao}.jpg
              (`nor` is always the OpenGL / +Y normal map, never DirectX)
    hdris     godot/assets/hdri/<key>.hdr
    models    godot/assets/props/<key>/<key>.glb  (glTF packed to one GLB; Godot
              extracts the embedded JPGs next to it on import, like the other props)

Raw downloads are cached under tools/cache/cc0/ (git-ignored). Poly Haven files
are checked against the API's md5. Existing files are kept unless --force.
After a download, tools/cc0_assets.lock.json records source, authors, URLs and
md5 of every file written, for CREDITS.txt.

Models arrive at source polycount. `target_tris` is the Mobile budget each one
must be reduced to (Godot's import LODs, or a tools/build_*.py pass like the
pine and tree_small_02 builds) before it is placed in a city.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import os
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "godot" / "assets"
CACHE = ROOT / "tools" / "cache" / "cc0"
LOCK = ROOT / "tools" / "cc0_assets.lock.json"
# Poly Haven asks API clients to send a User-Agent that identifies the project.
UA = "vortex-cc0-fetch/1.0 (+https://github.com/tukehub/vortex)"
PH_API = "https://api.polyhaven.com"
ACG_API = "https://ambientcg.com/api/v2/full_json"
MAX_ZIP_MEMBER = 64 << 20

# Poly Haven map key -> our suffix. nor_dx is deliberately absent.
PH_MAPS = {"diff": "Diffuse", "nor": "nor_gl", "rough": "Rough", "arm": "arm", "ao": "AO"}
# ambientCG zip member suffix -> our suffix. NormalDX is deliberately absent.
ACG_MAPS = {"Color": "diff", "NormalGL": "nor", "Roughness": "rough", "Metalness": "metal", "AmbientOcclusion": "ao"}

# Maps: diff + nor (OpenGL) + arm (R=AO, G=roughness, B=metal; Godot's ORM
# layout). The export ships every file under res://, so a separate _rough
# would duplicate arm.g in the APK; shaders read roughness from arm.g.
#
# tier 1: visible gap in a shipped city (Tirana, Vlorë, Shkodër)
# tier 2: upgrade to an existing surface or prop
# tier 3: optional dressing
MANIFEST: list[dict] = [
    # ---------------------------------------------------------------- textures
    {"key": "sand", "src": "polyhaven", "id": "coast_sand_04", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "Vlorë beach: terrain.gdshader shades the shore band with a flat sand_color uniform."},
    {"key": "limestone", "src": "polyhaven", "id": "rock_face_03", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "sea_rocks.gd armour is vertex colour only; vlore_tunnel.gd portal reuses rock_diff (README: distinct portal rock)."},
    {"key": "promenade_paving", "src": "polyhaven", "id": "precast_stone_paving", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "Lungomare paving is a hash pattern in seafront_ground.gdshader (README: waterfront paving)."},
    {"key": "palm_bark", "src": "polyhaven", "id": "palm_tree_bark", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "palms.gd date palms ship with no textures."},
    {"key": "castle_wall", "src": "polyhaven", "id": "castle_wall_slates", "kind": "texture", "tier": 2,
     "maps": ["diff", "nor", "arm"],
     "gap": "rozafa_castle.gd rubble walls reuse cobble_diff / rooftiles_diff."},
    {"key": "stucco", "src": "polyhaven", "id": "white_stucco", "kind": "texture", "tier": 2,
     "maps": ["diff", "nor", "arm"],
     "gap": "Vlorë waterfront shopfronts and Kuzum Baba walls are vertex colour (README: local shopfronts)."},
    {"key": "shutter", "src": "polyhaven", "id": "painted_metal_shutter", "kind": "texture", "tier": 2,
     "maps": ["diff", "nor", "arm"],
     "gap": "Shopfront roller shutters for the waterfront frontages."},
    {"key": "asphalt", "src": "polyhaven", "id": "asphalt_02", "kind": "texture", "tier": 2,
     "maps": ["arm"],
     "gap": "Road roughness: road.gdshader reads arm.g; asphalt_rough.jpg was removed."},
    {"key": "pole_metal", "src": "ambientcg", "id": "Metal032", "kind": "texture", "tier": 2,
     "maps": ["diff", "nor", "arm"],
     "gap": "Lamp poles, signal masts and shelter frames are untextured vertex colour."},
    {"key": "ashlar_buff", "src": "polyhaven", "id": "sandstone_blocks_05", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "Korçë Resurrection Cathedral: coursed cream sandstone blocks with brown joints."},
    {"key": "rubble_wall", "src": "polyhaven", "id": "stone_wall", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "Korçë Mësonjëtorja: rubble limestone with pale pointing between timber bands."},
    {"key": "clay_roof", "src": "polyhaven", "id": "clay_roof_tiles_02", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "Korçë cathedral domes and the Mësonjëtorja hip roof: orange clay barrel tiles."},
    {"key": "square_granite", "src": "polyhaven", "id": "granite_tile_03", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "Vlorë: Sheshi i Flamurit's granite slabs round the Independence Monument."},
    {"key": "dark_granite", "src": "polyhaven", "id": "granite_tile", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "Vlorë: the Independence Monument's pylon and stepped base."},
    {"key": "river_pebbles", "src": "polyhaven", "id": "dry_river_pebbles", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "Berat: the Osum's gravel banks."},
    {"key": "dark_timber", "src": "polyhaven", "id": "dark_wooden_planks", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "Berat houses: window frames, eaves, brackets and doors."},
    {"key": "old_roof", "src": "polyhaven", "id": "roof_09", "kind": "texture", "tier": 1,
     "maps": ["diff", "nor", "arm"],
     "gap": "Berat houses: weathered grey-brown tile roofs of Mangalem and Gorica."},
    # ------------------------------------------------------------------- hdris
    {"key": "sky_rain_night", "src": "polyhaven", "id": "kloppenheim_07_puresky", "kind": "hdri", "tier": 1,
     "res": "2k",
     "gap": "SkyEnv.HDRI 'rain' reuses the clear, starry sky_night; this is an overcast night pure sky."},
    # ------------------------------------------------------------------ models
    {"key": "street_bin", "src": "polyhaven", "id": "metal_trash_can", "kind": "model", "tier": 2,
     "target_tris": 800,
     "gap": "street_props.gd bins are procedural boxes (48 in Tirana)."},
    {"key": "promenade_lamp", "src": "polyhaven", "id": "street_lamp_01", "kind": "model", "tier": 3,
     "target_tris": 1500,
     "gap": "Pedestrian lamps (3.9 m) for Lungomare; road lamps stay procedural."},
    {"key": "utility_box", "src": "polyhaven", "id": "utility_box_01", "kind": "model", "tier": 3,
     "target_tris": 900,
     "gap": "Kerbside electrical cabinets for street dressing."},
    {"key": "lion_head", "src": "polyhaven", "id": "lion_head", "kind": "model", "tier": 2,
     "target_tris": 6000,
     "gap": "Vlorë: the lion fountain at the Konomi split (Rrapi), water from its mouth (tools/build_lion_head.gd)."},
    {"key": "bench", "src": "polyhaven", "id": "painted_wooden_bench", "kind": "model", "tier": 3,
     "target_tris": 630,
     "gap": "Procedural benches (333 in Tirana). Rustic style: check it reads as street furniture."},
]


# ------------------------------------------------------------------ network

def _request(url: str) -> urllib.request.Request:
    return urllib.request.Request(url, headers={"User-Agent": UA})


def http_bytes(url: str, attempts: int = 4) -> bytes:
    delay = 2.0
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(_request(url), timeout=120) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code not in (429, 500, 502, 503, 504) or attempt == attempts:
                raise
        except urllib.error.URLError:
            if attempt == attempts:
                raise
        print(f"    retry {attempt}/{attempts - 1} in {delay:.0f}s: {url}")
        time.sleep(delay)
        delay *= 2
    raise RuntimeError("unreachable")


def http_json(url: str, cache_name: str | None = None) -> dict:
    if cache_name:
        path = CACHE / "api" / cache_name
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    data = json.loads(http_bytes(url))
    if cache_name:
        write_atomic(CACHE / "api" / cache_name, json.dumps(data).encode())
    return data


def write_atomic(dst: Path, data: bytes) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    part = dst.with_name(dst.name + ".part")
    part.write_bytes(data)
    os.replace(part, dst)


def fetch_cached(url: str, md5: str | None = None) -> bytes:
    """Download once into tools/cache/cc0/files/, verifying md5 when known."""
    name = hashlib.sha1(url.encode()).hexdigest()[:16] + "_" + Path(urllib.parse.urlparse(url).path).name
    path = CACHE / "files" / name
    if path.exists() and (md5 is None or hashlib.md5(path.read_bytes()).hexdigest() == md5):
        return path.read_bytes()
    print(f"    GET {url}")
    data = http_bytes(url)
    if md5 and hashlib.md5(data).hexdigest() != md5:
        raise RuntimeError(f"md5 mismatch for {url}")
    write_atomic(path, data)
    return data


# ------------------------------------------------------------- resolvers
# Each resolver returns (files, meta): files is a list of
# {"out": Path, "url": str, "md5": str|None, "size": int, "role": str}.

def resolve_polyhaven(entry: dict, res: str) -> tuple[list[dict], dict]:
    aid = entry["id"]
    files = http_json(f"{PH_API}/files/{aid}", f"ph_files_{aid}.json")
    info = http_json(f"{PH_API}/info/{aid}", f"ph_info_{aid}.json")
    meta = {"name": info.get("name", aid), "authors": sorted(info.get("authors", {})),
            "page": f"https://polyhaven.com/a/{aid}", "polycount": info.get("polycount")}
    out: list[dict] = []
    if entry["kind"] == "texture":
        for suffix in entry["maps"]:
            ph_key = PH_MAPS[suffix]
            item = files.get(ph_key, {}).get(res, {}).get("jpg")
            if not item:
                raise LookupError(f"{aid}: no {ph_key} {res} jpg")
            out.append({"out": ASSETS / "textures" / f"{entry['key']}_{suffix}.jpg", "url": item["url"],
                        "md5": item.get("md5"), "size": item.get("size", 0), "role": suffix})
    elif entry["kind"] == "hdri":
        hres = entry.get("res", res)
        item = files.get("hdri", {}).get(hres, {}).get("hdr")
        if not item:
            raise LookupError(f"{aid}: no {hres} hdr")
        out.append({"out": ASSETS / "hdri" / f"{entry['key']}.hdr", "url": item["url"],
                    "md5": item.get("md5"), "size": item.get("size", 0), "role": "hdri"})
    elif entry["kind"] == "model":
        item = files.get("gltf", {}).get(res, {}).get("gltf")
        if not item:
            raise LookupError(f"{aid}: no {res} gltf")
        glb = ASSETS / "props" / entry["key"] / f"{entry['key']}.glb"
        parts = [{"rel": rel, **v} for rel, v in item.get("include", {}).items()]
        out.append({"out": glb, "url": item["url"], "md5": item.get("md5"), "role": "gltf",
                    "size": item.get("size", 0) + sum(p.get("size", 0) for p in parts), "parts": parts})
    return out, meta


def resolve_ambientcg(entry: dict, res: str) -> tuple[list[dict], dict]:
    aid = entry["id"]
    q = urllib.parse.urlencode({"id": aid, "include": "downloadData,tagData"})
    data = http_json(f"{ACG_API}?{q}", f"acg_{aid}.json")
    assets = data.get("foundAssets", [])
    if not assets:
        raise LookupError(f"ambientCG: {aid} not found")
    attribute = f"{res.upper()}-JPG"
    link, size = None, 0
    for folder in assets[0].get("downloadFolders", {}).values():
        for category in folder.get("downloadFiletypeCategories", {}).values():
            for dl in category.get("downloads", []):
                if dl.get("attribute") == attribute:
                    link, size = dl["downloadLink"], dl.get("size", 0)
    if not link:
        raise LookupError(f"ambientCG: {aid} has no {attribute} download")
    meta = {"name": assets[0].get("displayName", aid), "authors": ["ambientCG"],
            "page": f"https://ambientcg.com/view?id={aid}"}
    zip_file = {"out": ASSETS / "textures" / f"{entry['key']}_*.jpg", "url": link, "md5": None,
                "size": size, "role": "zip", "attribute": attribute}
    return [zip_file], meta


RESOLVERS = {"polyhaven": resolve_polyhaven, "ambientcg": resolve_ambientcg}


# --------------------------------------------------------------- writers

def _safe_rel(rel: str) -> str:
    p = Path(rel)
    if p.is_absolute() or ".." in p.parts:
        raise ValueError(f"refusing unsafe path in glTF include: {rel}")
    return p.as_posix()


def pack_glb(gltf: dict, read_rel) -> bytes:
    """Pack a glTF with external buffers/images into a single GLB (one BIN chunk)."""
    blob = bytearray()

    def append(data: bytes) -> int:
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        blob.extend(data)
        return offset

    def load_uri(uri: str) -> bytes:
        if uri.startswith("data:"):
            return base64.b64decode(uri.split(",", 1)[1])
        return read_rel(_safe_rel(urllib.parse.unquote(uri)))

    base = [append(load_uri(b["uri"])) for b in gltf.get("buffers", [])]
    for view in gltf.get("bufferViews", []):
        view["byteOffset"] = view.get("byteOffset", 0) + base[view.get("buffer", 0)]
        view["buffer"] = 0
    views = gltf.setdefault("bufferViews", [])
    for image in gltf.get("images", []):
        uri = image.pop("uri", None)
        if uri is None:
            continue
        data = load_uri(uri)
        mime = "image/png" if data[:8] == b"\x89PNG\r\n\x1a\n" else "image/jpeg"
        views.append({"buffer": 0, "byteOffset": append(data), "byteLength": len(data)})
        image["bufferView"] = len(views) - 1
        image["mimeType"] = mime
    while len(blob) % 4:
        blob.append(0)
    gltf["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(blob)
    return (struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(js), b"JSON") + js
            + struct.pack("<I4s", len(blob), b"BIN\x00") + bytes(blob))


def pack_arm(ao: bytes | None, rough: bytes, metal: bytes | None) -> bytes | None:
    """R=AO, G=roughness, B=metalness (Godot ORMMaterial3D layout). Needs Pillow."""
    try:
        from PIL import Image
    except ImportError:
        print("    Pillow missing: skipped ARM pack (pip install pillow)")
        return None
    g = Image.open(io.BytesIO(rough)).convert("L")
    r = Image.open(io.BytesIO(ao)).convert("L").resize(g.size) if ao else Image.new("L", g.size, 255)
    b = Image.open(io.BytesIO(metal)).convert("L").resize(g.size) if metal else Image.new("L", g.size, 0)
    out = io.BytesIO()
    Image.merge("RGB", (r, g, b)).save(out, "JPEG", quality=92)
    return out.getvalue()


def write_out(path: Path, data: bytes, force: bool, written: list[dict], url: str, md5: str | None) -> None:
    if path.exists() and not force:
        print(f"    keep {path.relative_to(ROOT)} (exists; --force to replace)")
        return
    write_atomic(path, data)
    written.append({"path": path.relative_to(ROOT).as_posix(), "url": url,
                    "md5": hashlib.md5(data).hexdigest(), "bytes": len(data)})
    print(f"    wrote {path.relative_to(ROOT)} ({len(data) // 1024} KB)")


def install(entry: dict, files: list[dict], force: bool) -> list[dict]:
    written: list[dict] = []
    for f in files:
        if f["role"] == "gltf":
            parts = {_safe_rel(p["rel"]): p for p in f["parts"]}
            gltf = json.loads(fetch_cached(f["url"], f["md5"]))

            def read_rel(rel: str) -> bytes:
                if rel not in parts:
                    raise LookupError(f"{entry['id']}: glTF references {rel}, not in the API include list")
                return fetch_cached(parts[rel]["url"], parts[rel].get("md5"))

            write_out(f["out"], pack_glb(gltf, read_rel), force, written, f["url"], None)
        elif f["role"] == "zip":
            zdata = fetch_cached(f["url"])
            maps: dict[str, bytes] = {}
            with zipfile.ZipFile(io.BytesIO(zdata)) as z:
                for member in z.infolist():
                    stem = Path(member.filename).stem          # e.g. Metal032_1K-JPG_NormalGL
                    suffix = ACG_MAPS.get(stem.rsplit("_", 1)[-1])
                    if suffix and member.filename.lower().endswith(".jpg") and member.file_size <= MAX_ZIP_MEMBER:
                        maps[suffix] = z.read(member)
            wanted = entry["maps"]
            missing = [m for m in wanted if m != "arm" and m not in maps]
            if missing:
                print(f"    note: {entry['id']} zip has no {', '.join(missing)}")
            for suffix in wanted:
                if suffix in maps:
                    write_out(ASSETS / "textures" / f"{entry['key']}_{suffix}.jpg", maps[suffix], force, written,
                              f["url"], None)
            if "arm" in wanted and "rough" in maps:
                arm = pack_arm(maps.get("ao"), maps["rough"], maps.get("metal"))
                if arm:
                    write_out(ASSETS / "textures" / f"{entry['key']}_arm.jpg", arm, force, written, f["url"], None)
        else:
            write_out(f["out"], fetch_cached(f["url"], f["md5"]), force, written, f["url"], f["md5"])
    return written


# ------------------------------------------------------------------ main

def select(args) -> list[dict]:
    chosen = MANIFEST
    if args.only:
        names = {n.strip() for n in args.only.split(",") if n.strip()}
        unknown = names - {e["key"] for e in MANIFEST} - {e["id"] for e in MANIFEST}
        if unknown:
            sys.exit(f"unknown --only entries: {', '.join(sorted(unknown))}")
        chosen = [e for e in chosen if e["key"] in names or e["id"] in names]
    if args.tier:
        chosen = [e for e in chosen if e["tier"] <= args.tier]
    return chosen


def target_of(entry: dict) -> str:
    if entry["kind"] == "texture":
        return f"godot/assets/textures/{entry['key']}_{{{','.join(entry['maps'])}}}.jpg"
    if entry["kind"] == "hdri":
        return f"godot/assets/hdri/{entry['key']}.hdr"
    return f"godot/assets/props/{entry['key']}/{entry['key']}.glb"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="resolve URLs and sizes through the APIs (metadata only)")
    ap.add_argument("--download", action="store_true", help="download and install the selected assets")
    ap.add_argument("--only", help="comma-separated keys or source ids")
    ap.add_argument("--tier", type=int, choices=(1, 2, 3), help="only entries at or below this tier")
    ap.add_argument("--res", default="1k", choices=("1k", "2k"), help="texture/model resolution (HDRIs keep their own)")
    ap.add_argument("--force", action="store_true", help="replace files that already exist")
    args = ap.parse_args(argv)
    entries = select(args)

    if not (args.check or args.download):
        for e in entries:
            extra = f"  -> {e['target_tris']} tris" if "target_tris" in e else ""
            print(f"[T{e['tier']}] {e['key']:<17} {e['src']}:{e['id']:<24} {target_of(e)}{extra}")
            print(f"       {e['gap']}")
        print("\nNothing downloaded. --check resolves URLs; --download installs.")
        return 0

    lock = json.loads(LOCK.read_text(encoding="utf-8")) if LOCK.exists() else {}
    total = 0
    failed: list[str] = []
    for e in entries:
        print(f"[T{e['tier']}] {e['key']} <- {e['src']}:{e['id']}")
        try:
            files, meta = RESOLVERS[e["src"]](e, args.res)
        except (LookupError, urllib.error.URLError, json.JSONDecodeError) as err:
            print(f"    FAILED: {err}")
            failed.append(e["key"])
            continue
        size = sum(f["size"] for f in files)
        total += size
        if meta.get("polycount"):
            print(f"    source {meta['polycount']} tris, budget {e.get('target_tris', '-')}")
        for f in files:
            print(f"    {f['role']:<6} {f['size'] // 1024:>6} KB  {f['url']}")
        if not args.download:
            continue
        try:
            written = install(e, files, args.force)
        except (LookupError, RuntimeError, ValueError, urllib.error.URLError, zipfile.BadZipFile) as err:
            print(f"    FAILED: {err}")
            failed.append(e["key"])
            continue
        if written:
            lock[e["key"]] = {"source": e["src"], "id": e["id"], "name": meta["name"], "authors": meta["authors"],
                              "licence": "CC0-1.0", "page": meta["page"], "files": written}
    print(f"\n{len(entries) - len(failed)}/{len(entries)} resolved, ~{total / (1 << 20):.1f} MB source data.")
    if args.download:
        write_atomic(LOCK, (json.dumps(lock, indent=2, ensure_ascii=False) + "\n").encode())
        print(f"Provenance: {LOCK.relative_to(ROOT)}. Add the new entries to godot/assets/CREDITS.txt.")
        print("Next: godot --headless --path godot --editor --import")
    if failed:
        print(f"Failed: {', '.join(failed)}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
