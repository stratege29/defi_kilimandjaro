# -*- coding: utf-8 -*-
"""
Rubrique « EXPLIQUE À TA DARONNE » — reels 9:16 : un message 100 % nouchi dans une
bulle, que la commu TRADUIT en commentaire (« ta daronne capte rien »). Pas de
traduction affichée → partage/tag. Source : nouchi_messages.json.

Usage : /tmp/igvenv/bin/python functions/scripts/gen_explique.py 8 [--offset 0]
Sort au format gen_reels_theme (thème "explique") → add_reels.js explique.
"""
import os
import sys
import json
import math
import shutil
import subprocess
from PIL import ImageDraw
import generate as G
import gen_phrase as GP
import gen_reels_theme as GRT

VW, VH = 1080, 1920
FPS, DUR = 30, 7.0
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = GRT.OUT


def eob(t):
    c1 = 1.70158
    c3 = c1 + 1
    return 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def frame(nouchi, t):
    img = G.base(VW, VH, glow=G.KOLA, glow_strength=0.13)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 235), "EXPLIQUE À TA DARONNE", font=G.sans(38, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, 312), "Ta daronne a reçu ça. Traduis-lui.", font=G.serif_it(40, 500), fill=G.T2, anchor="mm")
    yoff = int((1 - min(eob(clamp(t / 0.4)), 1.0)) * 80) if t < 0.4 else 0
    by0, by1 = 470 + yoff, 1180 + yoff
    d.rounded_rectangle([110, by0, VW - 110, by1], 48, fill=G.S2, outline=GP.ACC["nouchi"], width=3)
    d.polygon([(190, by1 - 4), (190, by1 + 60), (260, by1 - 4)], fill=G.S2)  # petite pointe de bulle
    G.draw_block(d, nouchi, G.serif_it(54, 500), 0, by0 + 90, VW - 250, G.T1, lh=1.3, align="center", anchor_cx=VW / 2)
    pulse = 1 + 0.02 * math.sin(t * 6.28 * 2)
    d.rounded_rectangle([150, VH - 330, VW - 150, VH - 242], 44, fill=G.S2, outline=G.GOLD, width=2)
    d.text((VW / 2, VH - 286), "TRADUIS EN COMMENTAIRE", font=G.sans(int(30 * pulse), "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, VH - 162), "Tag un pote bilingue", font=G.serif_it(36, 500), fill=G.T2, anchor="mm")
    d.text((VW / 2, VH - 80), "@defi_kilimandjaro", font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def encode(render, mp4):
    F = int(FPS * DUR)
    tmp = mp4 + "_f"
    os.makedirs(tmp, exist_ok=True)
    for i in range(F):
        render(i / (F - 1)).save(os.path.join(tmp, f"f{i:03d}.png"))
    cmd = ["ffmpeg", "-y", "-framerate", str(FPS), "-i", os.path.join(tmp, "f%03d.png"),
           "-f", "lavfi", "-t", str(DUR), "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", "-movflags", "+faststart", mp4]
    r = subprocess.run(cmd, capture_output=True, text=True)
    shutil.rmtree(tmp, ignore_errors=True)
    if r.returncode != 0:
        print("ffmpeg ERR", r.stderr[-300:])


def build(count, offset=0):
    data = json.load(open(os.path.join(HERE, "nouchi_messages.json"), encoding="utf-8"))
    os.makedirs(OUT, exist_ok=True)
    plan = []
    for i in range(count):
        o = data[(offset + i) % len(data)]
        nou = o["nouchi"]
        encode(lambda t, N=nou: frame(N, t), os.path.join(OUT, f"REEL_explique_{i}.mp4"))
        frame(nou, 0.6).save(os.path.join(OUT, f"COVER_explique_{i}.png"))
        cap = (f"Ta daronne a reçu ce message 😅\n« {nou} »\nTraduis-lui en commentaire 👇 et tag un pote bilingue.\n\n"
               f"#Nouchi #Abidjan #CôteDivoire #DéfiKilimandjaro #225")
        plan.append({"i": i, "theme": "explique", "answer": nou[:28],
                     "reel": f"REEL_explique_{i}.mp4", "cover": f"COVER_explique_{i}.png", "caption": cap})
        print(f"  {i+1}/{count} · {nou[:30]}…")
    json.dump({"theme": "explique", "items": plan}, open(os.path.join(OUT, "reels_theme_explique_plan.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{count} reels « Explique à ta daronne » -> {OUT}\nSuite : node functions/scripts/add_reels.js explique --start 2026-07-10 --every 7 --commit")


if __name__ == "__main__":
    cnt = int(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else 8
    oi = sys.argv.index("--offset") if "--offset" in sys.argv else -1
    off = int(sys.argv[oi + 1]) if oi >= 0 else 0
    build(cnt, off)
