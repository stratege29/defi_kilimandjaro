# -*- coding: utf-8 -*-
"""
Rubrique « LE VS » — reels 9:16 débat/tribalisme : deux options s'affrontent
(A en haut, B en bas, badge VS au centre), la commu VOTE en commentaire.
Source : vs.json.

Usage : /tmp/igvenv/bin/python functions/scripts/gen_vs.py 8 [--offset 0]
Sort au format gen_reels_theme (thème "vs") → add_reels.js vs.
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
FPS, DUR = 30, 6.0
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = GRT.OUT
A_COL, B_COL = G.SUCCESS, GP.ACC["nouchi"]


def eob(t):
    c1 = 1.70158
    c3 = c1 + 1
    return 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def frame(a, b, q, t):
    import compose_styles as C
    img = G.base(VW, VH, glow=G.GOLD, glow_strength=0.13)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 175), "LE VS", font=G.sans(44, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, 250), q, font=G.serif_it(44, 500), fill=G.T2, anchor="mm")
    # divider
    d.line([(120, VH / 2), (VW - 120, VH / 2)], fill=G.HAIR, width=3)
    # A tombe du haut
    pa = clamp(t / 0.35)
    ay = -120 + (640 + 120) * min(eob(pa), 1.04)
    fa = C.fit(d, a, VW - 150, lambda s: G.serif(s, 700), lo=58, hi=140)
    d.text((VW / 2, ay), a, font=fa, fill=A_COL, anchor="mm")
    # B monte du bas
    by = (VH + 120) - ((VH + 120) - 1280) * min(eob(pa), 1.04)
    fb = C.fit(d, b, VW - 150, lambda s: G.serif(s, 700), lo=58, hi=140)
    d.text((VW / 2, by), b, font=fb, fill=B_COL, anchor="mm")
    # badge VS
    ps = clamp((t - 0.3) / 0.2)
    if ps > 0:
        r = int(98 * min(eob(ps), 1.06))
        d.ellipse([VW / 2 - r, VH / 2 - r, VW / 2 + r, VH / 2 + r], fill=G.GOLD, outline=G.CANVAS, width=6)
        d.text((VW / 2, VH / 2), "VS", font=G.serif(int(r * 0.9), 700), fill=G.CANVAS, anchor="mm")
    # CTA
    if t > 0.5:
        pulse = 1 + 0.02 * math.sin(t * 6.28 * 2)
        d.rounded_rectangle([150, VH - 300, VW - 150, VH - 212], 44, fill=G.S2, outline=G.GOLD, width=2)
        d.text((VW / 2, VH - 256), "VOTE EN COMMENTAIRE", font=G.sans(int(31 * pulse), "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, VH - 130), "Défends ton camp", font=G.serif_it(36, 500), fill=G.T2, anchor="mm")
    d.text((VW / 2, VH - 60), "@defi_kilimandjaro", font=G.sans(28, "Bold"), fill=G.GOLD, anchor="mm")
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
    data = json.load(open(os.path.join(HERE, "vs.json"), encoding="utf-8"))
    os.makedirs(OUT, exist_ok=True)
    plan = []
    for i in range(count):
        o = data[(offset + i) % len(data)]
        a, b, q = o["a"], o["b"], o["q"]
        encode(lambda t, A=a, B=b, Q=q: frame(A, B, Q, t), os.path.join(OUT, f"REEL_vs_{i}.mp4"))
        frame(a, b, q, 0.9).save(os.path.join(OUT, f"COVER_vs_{i}.png"))
        cap = (f"{a} ou {b} ? {q} 🔥\nVote en commentaire 👇 et défends ton camp.\n"
               f"#LeVS #CôteDivoire #225 #DéfiKilimandjaro")
        plan.append({"i": i, "theme": "vs", "answer": f"{a} vs {b}",
                     "reel": f"REEL_vs_{i}.mp4", "cover": f"COVER_vs_{i}.png", "caption": cap})
        print(f"  {i+1}/{count} · {a} vs {b}")
    json.dump({"theme": "vs", "items": plan}, open(os.path.join(OUT, "reels_theme_vs_plan.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{count} reels « Le VS » -> {OUT}\nSuite : node functions/scripts/add_reels.js vs --start 2026-07-11 --every 7 --commit")


if __name__ == "__main__":
    cnt = int(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else 8
    oi = sys.argv.index("--offset") if "--offset" in sys.argv else -1
    off = int(sys.argv[oi + 1]) if oi >= 0 else 0
    build(cnt, off)
