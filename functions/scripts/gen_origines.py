# -*- coding: utf-8 -*-
"""
Rubrique « D'OÙ ÇA SORT ? » — reels 9:16 : un mot → la révélation de son origine
(surprenante, drôle, mindblowing). Source vérifiée : origines.json.
Sort au format de `gen_reels_theme` (thème "origine") → seed avec `add_reels.js origine`.

Usage : /tmp/igvenv/bin/python functions/scripts/gen_origines.py 6 [--offset 0]
Sortie : docs/instagram_assets/reels/theme/REEL_origine_<i>.mp4 + COVER_origine_<i>.png
"""
import os
import sys
import json
import math
from PIL import ImageDraw
import generate as G
import compose_styles as C
import gen_reels_theme as GRT

VW, VH = 1080, 1920
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = GRT.OUT
P = 0.42  # moment de la révélation


def eob(t):
    c1 = 1.70158
    c3 = c1 + 1
    return 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def load():
    return json.load(open(os.path.join(HERE, "origines.json"), encoding="utf-8"))


def frame(word, origin, t):
    img = G.base(VW, VH, glow=G.GOLD, glow_strength=0.14)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 240), "D'OÙ ÇA SORT ?", font=G.sans(42, "Bold"), fill=G.GOLD, anchor="mm")
    # mot : chute + repos
    f = C.fit(d, word, VW - 160, lambda s: G.serif(s, 700), lo=64, hi=180)
    if t < 0.3:
        wy = -80 + (560 + 80) * min(eob(t / 0.3), 1.04)
    else:
        wy = 560 + int(6 * math.sin((t - 0.3) * math.pi * 3))
    d.text((VW / 2, wy), word, font=f, fill=G.T1, anchor="mm")
    G.kente_bar(d, VW / 2 - 160, 680, 320)
    if t < P:
        d.text((VW / 2, 840), "Tu sais d'où vient ce mot ?", font=G.serif_it(48, 500), fill=G.T2, anchor="mm")
    else:
        p = clamp((t - P) / 0.18)
        yoff = int((1 - eob(p)) * 70)
        G.draw_block(d, origin, G.serif(46, 600), 0, 790 + yoff, VW - 150, G.T1, lh=1.26, align="center", anchor_cx=VW / 2)
    pulse = 1 + 0.015 * math.sin(t * 6.28 * 3) if t >= P else 1.0
    d.rounded_rectangle([160, VH - 330, VW - 160, VH - 242], 44, fill=G.S2, outline=G.GOLD, width=2)
    d.text((VW / 2, VH - 286), "TAG UN POTE QUI SAIT PAS", font=G.sans(int(30 * pulse), "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, VH - 162), "Étonnant, non ?", font=G.serif_it(38, 500), fill=G.T2, anchor="mm")
    d.text((VW / 2, VH - 80), "@defi_kilimandjaro", font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def build(count, offset=0):
    data = load()
    os.makedirs(OUT, exist_ok=True)
    plan = []
    for i in range(count):
        o = data[(offset + i) % len(data)]
        w, org = o["word"], o["origin"]
        GRT.encode(lambda t, W=w, O=org: frame(W, O, t), os.path.join(OUT, f"REEL_origine_{i}.mp4"))
        frame(w, org, 0.20).save(os.path.join(OUT, f"COVER_origine_{i}.png"))
        cap = (f"D'où vient le mot {w} ? 🤯\n{org}\n\nTu savais ? Tag un pote qui sait pas 👇\n"
               f"#DéfiKilimandjaro #LeSaviezVous #Étymologie #CultureG")
        plan.append({"i": i, "theme": "origine", "answer": w,
                     "reel": f"REEL_origine_{i}.mp4", "cover": f"COVER_origine_{i}.png", "caption": cap})
        print(f"  {i+1}/{count} · {w}")
    json.dump({"theme": "origine", "items": plan}, open(os.path.join(OUT, "reels_theme_origine_plan.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{count} reels « D'où ça sort ? » -> {OUT}\nSuite : node functions/scripts/add_reels.js origine --start 2026-06-23 --every 7 --commit")


if __name__ == "__main__":
    cnt = int(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else 6
    oi = sys.argv.index("--offset") if "--offset" in sys.argv else -1
    off = int(sys.argv[oi + 1]) if oi >= 0 else 0
    build(cnt, off)
