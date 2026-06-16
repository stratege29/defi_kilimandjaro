# -*- coding: utf-8 -*-
"""Patterns géométriques africains (bogolan / kente / adinkra), discrets."""
import numpy as np
from PIL import Image, ImageDraw

def _draw(kind, W, H, color, alpha):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    c = (color[0], color[1], color[2], alpha)
    if kind == "diamonds":          # bogolan : losanges + point
        step = 130
        for yi, y in enumerate(range(0, H + step, step)):
            off = step // 2 if yi % 2 else 0
            for x in range(-step, W + step, step):
                cx, cy, r = x + off, y, 38
                d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], outline=c, width=3)
                d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=c)
    elif kind == "adinkra":         # croix + cercles
        step = 120
        for yi, y in enumerate(range(0, H + step, step)):
            off = step // 2 if yi % 2 else 0
            for x in range(-step, W + step, step):
                cx, cy, r = x + off, y, 17
                d.line([(cx - r, cy), (cx + r, cy)], fill=c, width=3)
                d.line([(cx, cy - r), (cx, cy + r)], fill=c, width=3)
                d.ellipse([cx - 33, cy - 33, cx + 33, cy + 33], outline=c, width=2)
    elif kind == "chevrons":        # kente : zigzags
        step = 64
        for y in range(-step, H + step, step):
            for x in range(-step, W + step, step * 2):
                d.line([(x, y), (x + step, y + step // 2), (x + 2 * step, y)], fill=c, width=4)
    elif kind == "triangles":       # montagnes tessellées
        step = 96
        for yi, y in enumerate(range(0, H + step, step)):
            off = step // 2 if yi % 2 else 0
            for x in range(-step, W + step, step):
                xx = x + off
                d.polygon([(xx, y + step), (xx + step // 2, y), (xx + step, y + step)], outline=c, width=3)
    return layer

def apply_pattern(img, kind, color, alpha=24, fade=True):
    """Composite un pattern sur img (RGB), atténué au centre (zone texte)."""
    W, H = img.size
    layer = _draw(kind, W, H, color, alpha)
    if fade:
        a = np.array(layer)[:, :, 3].astype(np.float32)
        ys = np.linspace(0, 1, H)
        # fort en haut (0-28%) et bas (72-100%), faible au centre
        prof = np.clip(np.minimum(ys / 0.28, (1 - ys) / 0.28), 0.12, 1.0)
        a *= prof[:, None]
        arr = np.array(layer); arr[:, :, 3] = a.astype(np.uint8)
        layer = Image.fromarray(arr)
    out = Image.alpha_composite(img.convert("RGBA"), layer)
    return out.convert("RGB")

PATTERN_FOR = {  # par famille de pack
    "culture": "diamonds",
    "nouchi": "adinkra",
    "villes": "chevrons",
    "foot": "triangles",
}
def pattern_for(pack):
    p = pack.lower()
    if "nouchi" in p: return "adinkra"
    if "ville" in p: return "chevrons"
    if "monde" in p or "foot" in p: return "triangles"
    return "diamonds"
