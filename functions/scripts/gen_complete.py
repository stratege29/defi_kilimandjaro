# -*- coding: utf-8 -*-
"""
Rubrique « COMPLÈTE » — reels 9:16 participation : une phrase-setup + des cases
vides (= longueur du mot) + « COMPLÈTE EN COMMENTAIRE ». PAS de révélation → la
réponse part dans les commentaires (friction zéro = participation max).
Source : complete.json. Sort au format gen_reels_theme (thème "complete").

Usage : /tmp/igvenv/bin/python functions/scripts/gen_complete.py 8 [--offset 0]
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
import gen_hook as GH

VW, VH = 1080, 1920
FPS, DUR = 30, 7.0
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = GRT.OUT
ACC = {"Nouchi": GP.ACC["nouchi"], "Au maquis": GP.ACC["nouchi"], "Culture 225": GP.ACC["culture"]}


def eob(t):
    c1 = 1.70158
    c3 = c1 + 1
    return 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def frame(sentence, answer, tag, t):
    accent = ACC.get(tag, G.GOLD)
    img = G.base(VW, VH, glow=G.GOLD, glow_strength=0.14)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 240), "COMPLÈTE LA PHRASE", font=G.sans(40, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, 312), tag.upper(), font=G.sans(26, "Bold"), fill=accent, anchor="mm")
    G.kente_bar(d, VW / 2 - 150, 372, 300)
    G.draw_block(d, sentence, G.serif(56, 650), 0, 500, VW - 150, G.T1, lh=1.25, align="center", anchor_cx=VW / 2)
    # cases vides (longueur de la réponse) qui apparaissent
    letters = [c for c in answer.upper() if c.isalnum()]
    n = len(letters)
    gap = 16
    s = min(112, int((VW - 220 - (n - 1) * gap) / max(n, 1)))
    tot = n * s + (n - 1) * gap
    x0 = (VW - tot) / 2
    cy = 1200
    for i in range(n):
        p = clamp((t - 0.15 - 0.05 * i) / 0.25)
        if p <= 0:
            continue
        ss = s * min(eob(p), 1.04)
        ch = ss * 1.18
        cx0 = x0 + i * (s + gap) + s / 2
        d.rounded_rectangle([cx0 - ss / 2, cy - ch / 2, cx0 + ss / 2, cy + ch / 2], 12, fill=G.S1, outline=G.GOLD, width=3)
    pulse = 1 + 0.02 * math.sin(t * 6.28 * 2)
    d.rounded_rectangle([150, VH - 330, VW - 150, VH - 242], 44, fill=G.S2, outline=G.GOLD, width=2)
    d.text((VW / 2, VH - 286), "COMPLÈTE EN COMMENTAIRE", font=G.sans(int(30 * pulse), "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, VH - 162), "La réponse est dans le jeu", font=G.serif_it(36, 500), fill=G.T2, anchor="mm")
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
    data = json.load(open(os.path.join(HERE, "complete.json"), encoding="utf-8"))
    os.makedirs(OUT, exist_ok=True)
    plan = []
    for i in range(count):
        o = data[(offset + i) % len(data)]
        sent, ans, tag = o["sentence"], o["answer"], o.get("tag", "Nouchi")
        GH.encode_hooked(lambda t, S=sent, A=ans, T=tag: frame(S, A, T, t), os.path.join(OUT, f"REEL_complete_{i}.mp4"),
                         GH.HOOKS["complete"][i % len(GH.HOOKS["complete"])], G.GOLD, FPS, DUR)
        frame(sent, ans, tag, 0.6).save(os.path.join(OUT, f"COVER_complete_{i}.png"))
        htag = "#Nouchi #Abidjan" if tag in ("Nouchi", "Au maquis") else "#Culture225 #CôteDivoire"
        cap = (f"Complète : « {sent} » 👇\nDis ta réponse en commentaire — et tag un pote qui sèche.\n"
               f"(La réponse est dans le jeu !)\n\n{htag} #DéfiKilimandjaro #JeuDeMots")
        plan.append({"i": i, "theme": "complete", "answer": ans,
                     "reel": f"REEL_complete_{i}.mp4", "cover": f"COVER_complete_{i}.png", "caption": cap})
        print(f"  {i+1}/{count} · {ans}")
    json.dump({"theme": "complete", "items": plan}, open(os.path.join(OUT, "reels_theme_complete_plan.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{count} reels « Complète » -> {OUT}\nSuite : node functions/scripts/add_reels.js complete --start 2026-07-08 --every 7 --commit")


if __name__ == "__main__":
    cnt = int(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else 8
    oi = sys.argv.index("--offset") if "--offset" in sys.argv else -1
    off = int(sys.argv[oi + 1]) if oi >= 0 else 0
    build(cnt, off)
