# -*- coding: utf-8 -*-
"""
Rangée SÉPARATRICE pour mosaïque — 3 cartes déco (filet kente + marque) à insérer
ENTRE deux mots. Compatible add_mosaic.js (groupe `mosaic_sep_<n>`, 1 rangée).

Usage : /tmp/igvenv/bin/python functions/scripts/gen_separator.py 1
"""
import os
import sys
import json
from PIL import ImageDraw
import generate as G
import compose_styles as C

ROOT = os.path.abspath(os.path.join(C._HERE, "..", "..", "docs/instagram_assets/mosaic"))


def sep_card(center):
    img = G.base(C.W, C.H, glow=G.GOLD, glow_strength=0.10)
    d = ImageDraw.Draw(img)
    if center:
        d.text((C.W / 2, C.H / 2 - 40), "✦", font=G.serif(150, 700), fill=G.GOLD_DP, anchor="mm")
        G.kente_bar(d, C.W / 2 - 150, C.H / 2 + 60, 300)
        d.text((C.W / 2, C.H / 2 + 130), "DÉFI KILIMANDJARO", font=G.sans(28, "Bold"), fill=G.T2, anchor="mm")
    else:
        G.kente_bar(d, C.W / 2 - 150, C.H / 2 - 5, 300)
        d.text((C.W / 2, C.H / 2 + 70), "• • •", font=G.sans(44, "Bold"), fill=G.T3, anchor="mm")
    C.foot(d)
    return img


def build(n=1):
    group = f"mosaic_sep_{n}"
    out = os.path.join(ROOT, group)
    os.makedirs(out, exist_ok=True)
    posts = []
    for c in range(3):
        fn = f"{group}_r0_c{c}.png"
        sep_card(c == 1).save(os.path.join(out, fn))
        posts.append({"row": 0, "col": c, "file": fn, "isLetter": False, "letter": None,
                      "caption": "· · ·\n\n#DéfiKilimandjaro"})
    plan = {"group": group, "word": "", "col": -1, "rows": 1, "posts": posts}
    with open(os.path.join(out, "mosaic_plan.json"), "w", encoding="utf-8") as f:
        json.dump(plan, f, ensure_ascii=False, indent=1)
    print(f"séparateur {group} -> {out}")
    print("À insérer ENTRE deux mots : node functions/scripts/add_mosaic.js", group, "--commit")


if __name__ == "__main__":
    build(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
