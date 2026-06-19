# -*- coding: utf-8 -*-
"""
Reels thématiques « devinette gameplay » 9:16 (1080×1920) — format PORTÉE.
Un reel = ÉNIGME (question + grille + chrono) → RÉVÉLATION (les lettres tombent)
→ SENS (explication) + CTA. Sert aussi de « Mot nouchi du vendredi » (pack nouchi).

Usage : /tmp/igvenv/bin/python functions/scripts/gen_reels_theme.py nouchi 4
Thèmes : nouchi · culture
Sortie : docs/instagram_assets/reels/theme/REEL_<i>.mp4 + COVER_<i>.png + reels_theme_plan.json
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
import gen_stories_video as GSV

VW, VH = 1080, 1920
FPS, DUR = 30, 10.0
P1, P2 = 0.42, 0.64  # fin énigme / fin révélation
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "docs/instagram_assets/reels/theme"))
DEV = os.path.abspath(os.path.join(HERE, "..", "..", "assets/data/devinettes/starter"))
PACKS = {"nouchi": ("crack_nouchi", "Crack Nouchi", GP.ACC["nouchi"]),
         "culture": ("culture_ci", "Culture 225", GP.ACC["culture"])}


def load(pack):
    p = os.path.join(DEV, pack + ".json")
    return [{"answer": (x.get("answer") or "").strip(),
             "riddle": (x.get("riddle") or {}).get("fr", ""),
             "expl": (x.get("explanation") or {}).get("fr", "")}
            for x in json.load(open(p, encoding="utf-8"))]


def letters_of(ans):
    return [c for c in ans.upper() if c not in (" ", "-", "'")]


def frame(cat, accent, riddle, letters, expl, t):
    outro = t >= P2
    img = G.base(VW, VH, glow=(G.SUCCESS if t >= P1 else G.KOLA), glow_strength=0.12)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 205), "DEVINETTE", font=G.sans(40, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, 272), cat.upper(), font=G.sans(26, "Bold"), fill=accent, anchor="mm")
    G.kente_bar(d, VW / 2 - 160, 330, 320)
    hook = "Tu trouves en 3 s ?" if t < P1 else ("La réponse !" if t < P2 else "")
    if hook:
        d.text((VW / 2, 430), hook, font=G.serif(54, 650), fill=G.T1, anchor="mm")
    if t < P2:
        G.draw_block(d, riddle, G.serif(48, 600), 0, 540, VW - 160, G.T1, lh=1.2, align="center", anchor_cx=VW / 2)
    cells, s, th = GSV.layout(letters, 900)
    n = max(len(cells), 1)
    gb = max(c["cy"] for c in cells) + th / 2
    for c in cells:
        GSV.empty_cell(d, c["cx"], c["cy"], s, th)
        if t >= P1:
            start = P1 + (P2 - P1) * 0.55 * (c["order"] / n)
            p = GSV.clamp((t - start) / ((P2 - P1) * 0.5))
            if p > 0:
                y = -80 + (c["cy"] + 80) * min(GSV.eob(p), 1.04)
                d.text((c["cx"], y), c["ch"], font=G.serif(int(s * 0.62), 700), fill=G.SUCCESS, anchor="mm")
    if t < P1:  # chrono
        prog = 1 - GSV.clamp((t - 0.05) / (P1 - 0.08))
        x0, x1, by = 220, VW - 220, gb + 60
        d.rounded_rectangle([x0, by, x1, by + 22], 11, fill=G.S2)
        if prog > 0:
            d.rounded_rectangle([x0, by, x0 + (x1 - x0) * prog, by + 22], 11, fill=accent)
    if outro:  # sens + CTA
        ex = expl if len(expl) <= 135 else expl[:132].rsplit(" ", 1)[0] + "…"
        G.draw_block(d, ex, G.serif_it(36, 500), 0, gb + 60, VW - 200, G.T1, lh=1.24, align="center", anchor_cx=VW / 2)
        pulse = 1 + 0.015 * math.sin(t * 6.28 * 3)
        d.rounded_rectangle([170, VH - 330, VW - 170, VH - 242], 44, fill=G.S2, outline=G.GOLD, width=2)
        d.text((VW / 2, VH - 286), "JOUE SUR DÉFI-KILI", font=G.sans(int(32 * pulse), "Bold"), fill=G.GOLD, anchor="mm")
        d.text((VW / 2, VH - 165), "Lien en bio", font=G.serif_it(36, 500), fill=G.T2, anchor="mm")
    d.text((VW / 2, VH - 80), "@defi_kilimandjaro", font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def encode(render, mp4):
    F = int(FPS * DUR)
    tmp = mp4 + "_frames"
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


def build(theme, count):
    if theme not in PACKS:
        print("Thèmes:", ", ".join(PACKS)); return
    pack, cat, accent = PACKS[theme]
    devs = load(pack)
    os.makedirs(OUT, exist_ok=True)
    plan = []
    for i in range(count):
        dv = devs[i % len(devs)]
        lets = letters_of(dv["answer"])
        encode(lambda t: frame(cat, accent, dv["riddle"], lets, dv["expl"], t), os.path.join(OUT, f"REEL_{theme}_{i}.mp4"))
        frame(cat, accent, dv["riddle"], lets, dv["expl"], 0.20).save(os.path.join(OUT, f"COVER_{theme}_{i}.png"))
        cap = (f"Tu trouves en 3 secondes ? 👀\n{dv['riddle']}\n\nRéponse : {dv['answer']} ✅\n{dv['expl']}\n\n"
               f"Joue sur défi-Kili (lien en bio) · #Devinette #CôteDivoire #225 #DéfiKilimandjaro")
        plan.append({"i": i, "theme": theme, "answer": dv["answer"],
                     "reel": f"REEL_{theme}_{i}.mp4", "cover": f"COVER_{theme}_{i}.png", "caption": cap})
        print(f"  {i+1}/{count}")
    json.dump({"theme": theme, "items": plan}, open(os.path.join(OUT, f"reels_theme_{theme}_plan.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{count} reels '{theme}' -> {OUT}\nSuite : node functions/scripts/add_reels.js {theme} --start 2026-06-20 --commit")


if __name__ == "__main__":
    theme = sys.argv[1] if len(sys.argv) > 1 else "nouchi"
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    build(theme, count)
