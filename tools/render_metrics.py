"""Image metrics for before/after renders from godot/tests/render_compare.tscn.

Usage: python3 tools/render_metrics.py <dir of PNGs>  -> prints and writes metrics.json
  sharp_all / sharp_road: variance of the Laplacian (x1e4), whole frame / lower 45%
  luma: mean luma; sat: mean HSV saturation; clip: % pixels with a channel >= 0.985;
  crush: % pixels with every channel < 0.02.
"""
import sys, json, glob, os
import numpy as np
from PIL import Image

def metrics(path):
    im = np.asarray(Image.open(path).convert('RGB')).astype(np.float32) / 255.0
    g = im @ np.array([0.299, 0.587, 0.114], np.float32)
    lap = g[1:-1, 1:-1] * 4 - g[:-2, 1:-1] - g[2:, 1:-1] - g[1:-1, :-2] - g[1:-1, 2:]
    h = g.shape[0]
    road = lap[int(h * 0.55):, :]            # lower part: road and markings
    mx, mn = im.max(2), im.min(2)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
    return {"sharp_all": float(lap.var() * 1e4), "sharp_road": float(road.var() * 1e4),
            "luma": float(g.mean()), "sat": float(sat.mean()),
            "clip": float((mx > 0.985).mean() * 100), "crush": float((mx < 0.02).mean() * 100)}

out = {}
for p in sorted(glob.glob(os.path.join(sys.argv[1], '*.png'))):
    out[os.path.basename(p)[:-4]] = metrics(p)
json.dump(out, open(os.path.join(sys.argv[1], 'metrics.json'), 'w'), indent=1)
for k, v in out.items():
    print(f"{k:28s} " + " ".join(f"{a}={b:7.2f}" for a, b in v.items()))
