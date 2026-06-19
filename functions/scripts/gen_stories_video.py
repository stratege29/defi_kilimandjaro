# -*- coding: utf-8 -*-
"""
Stories Instagram VIDÉO 9:16 (1080×1920) animées, style « Vert Nuit ».
  - ÉNIGME : les cases de la grille apparaissent + une barre chrono descend.
  - RÉPONSE : les lettres tombent une à une dans la grille, puis l'explication.
Réutilise l'infra ffmpeg des reels. ~6 s, audio silencieux (requis par IG).

Usage : /tmp/igvenv/bin/python functions/scripts/gen_stories_video.py 7
Sortie : docs/instagram_assets/stories/enigme_<i>.mp4 + reponse_<i>.mp4 + stories_plan.json
"""
import os
import sys
import json
import shutil
import subprocess
from PIL import ImageDraw
import generate as G
import gen_phrase as GP

VW, VH = 1080, 1920
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "docs/instagram_assets/stories"))
os.makedirs(OUT, exist_ok=True)
FPS, DUR = 30, 6.0


def eob(t):
    c1 = 1.70158
    c3 = c1 + 1
    return 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def _letters(ans):
    return [c for c in ans.upper() if c not in (" ", "-", "'")]


def layout(letters, top_y):
    n = len(letters)
    gap = 18
    s = min(150, int((VW - 200 - (n - 1) * gap) / max(n, 1)))
    rows = [letters]
    if s < 96 and n > 6:
        h = (n + 1) // 2
        rows = [letters[:h], letters[h:]]
        m = max(len(r) for r in rows)
        s = min(150, int((VW - 200 - (m - 1) * gap) / m))
    th = int(s * 1.18)
    rg = 22
    cells = []
    order = 0
    for ri, row in enumerate(rows):
        rw = len(row) * s + (len(row) - 1) * gap
        x0 = (VW - rw) / 2
        ry = top_y + ri * (th + rg)
        for ci, ch in enumerate(row):
            cells.append({"cx": x0 + ci * (s + gap) + s / 2, "cy": ry + th / 2, "ch": ch, "order": order})
            order += 1
    return cells, s, th


def empty_cell(d, cx, cy, s, th, scale=1.0):
    ss, hh = s * scale, th * scale
    d.rounded_rectangle([cx - ss / 2, cy - hh / 2, cx + ss / 2, cy + hh / 2], max(4, int(12 * scale)),
                        fill=G.S1, outline=G.HAIR, width=3)


def enigme_frame(cat, accent, riddle, letters, t):
    img = G.base(VW, VH, glow=G.KOLA, glow_strength=0.13)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 235), "ÉNIGME DU JOUR", font=G.sans(40, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, 300), cat.upper(), font=G.sans(26, "Bold"), fill=accent, anchor="mm")
    G.kente_bar(d, VW / 2 - 170, 360, 340)
    G.draw_block(d, riddle, G.serif(52, 650), 0, 470, VW - 160, G.T1, lh=1.22, align="center", anchor_cx=VW / 2)
    cells, s, th = layout(letters, 1000)
    n = len(cells)
    for c in cells:                                   # pop-in séquentiel
        p = clamp((t - 0.06 * c["order"]) / 0.22)
        if p <= 0:
            continue
        empty_cell(d, c["cx"], c["cy"], s, th, scale=min(eob(p), 1.04))
    # barre chrono sous la grille
    bottom = max(c["cy"] for c in cells) + th / 2 + 60
    x0, x1 = 200, VW - 200
    d.rounded_rectangle([x0, bottom, x1, bottom + 22], 11, fill=G.S2)
    prog = 1 - clamp((t - 0.35) / 0.62)
    if prog > 0:
        d.rounded_rectangle([x0, bottom, x0 + (x1 - x0) * prog, bottom + 22], 11, fill=accent)
    # CTA pulsé
    pulse = 1 + 0.015 * __import__("math").sin(t * 6.28 * 3)
    d.rounded_rectangle([160, VH - 320, VW - 160, VH - 232], 44, fill=G.S2, outline=G.GOLD, width=2)
    d.text((VW / 2, VH - 276), "TA RÉPONSE EN DM", font=G.sans(int(32 * pulse), "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, VH - 150), "La réponse ce soir", font=G.serif_it(38, 500), fill=G.T2, anchor="mm")
    d.text((VW / 2, VH - 80), "@defi_kilimandjaro", font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def reponse_frame(cat, accent, letters, expl, t):
    img = G.base(VW, VH, glow=G.SUCCESS, glow_strength=0.13)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 250), "LA RÉPONSE", font=G.sans(44, "Bold"), fill=G.SUCCESS, anchor="mm")
    d.text((VW / 2, 320), cat.upper(), font=G.sans(26, "Bold"), fill=accent, anchor="mm")
    cells, s, th = layout(letters, 500)
    n = max(len(cells), 1)
    stag = 0.30 / n
    for c in cells:
        empty_cell(d, c["cx"], c["cy"], s, th)        # case vide statique
        p = clamp((t - stag * c["order"]) / 0.22)
        if p <= 0:
            continue
        y = -80 + (c["cy"] + 80) * min(eob(p), 1.04)  # la lettre tombe
        d.text((c["cx"], y), c["ch"], font=G.serif(int(s * 0.62), 700), fill=G.SUCCESS, anchor="mm")
    if t > 0.52:                                       # explication après révélation (~3 s visible)
        gb = max(c["cy"] for c in cells) + th / 2
        G.draw_block(d, expl, G.serif_it(40, 500), 0, gb + 80, VW - 200, G.T1, lh=1.26, align="center", anchor_cx=VW / 2)
    d.text((VW / 2, VH - 240), "Nouvelle énigme demain", font=G.serif(46, 650), fill=G.T1, anchor="mm")
    d.text((VW / 2, VH - 150), "Joue sur l'app · défi-Kili", font=G.sans(28, "Medium"), fill=G.T3, anchor="mm")
    d.text((VW / 2, VH - 80), "@defi_kilimandjaro", font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def encode(render, name):
    F = int(FPS * DUR)
    tmp = os.path.join(OUT, f"_t_{name}")
    os.makedirs(tmp, exist_ok=True)
    for i in range(F):
        render(i / (F - 1)).save(os.path.join(tmp, f"f{i:03d}.png"))
    mp4 = os.path.join(OUT, f"{name}.mp4")
    cmd = ["ffmpeg", "-y", "-framerate", str(FPS), "-i", os.path.join(tmp, "f%03d.png"),
           "-f", "lavfi", "-t", str(DUR), "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", "-movflags", "+faststart", mp4]
    r = subprocess.run(cmd, capture_output=True, text=True)
    shutil.rmtree(tmp, ignore_errors=True)
    if r.returncode != 0:
        print("ffmpeg ERR", name, r.stderr[-300:])


BLOCK = {"DJOSS", "DJANDJOU", "WOUBI", "BANGALA", "GNAMAKODE", "BLEDARD", "BABTOU", "COXER", "FARADJE"}


def build(count, offset=0):
    devs = [d for d in GP.load_devinettes() if d["answer"].upper() not in BLOCK]
    plan = []
    for i in range(count):
        dv = devs[(offset + i) % len(devs)]
        cat, accent = GP.PACKS[dv["pack"]]
        lets = _letters(dv["answer"])
        encode(lambda t: enigme_frame(cat, accent, dv["riddle"], lets, t), f"enigme_{i}")
        encode(lambda t: reponse_frame(cat, accent, lets, dv["expl"], t), f"reponse_{i}")
        plan.append({"i": i, "answer": dv["answer"], "cat": cat, "enigme": f"enigme_{i}.mp4", "reponse": f"reponse_{i}.mp4"})
        print(f"  {i+1}/{count}")
    json.dump({"days": count, "items": plan}, open(os.path.join(OUT, "stories_plan.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{count} jours · {count*2} stories vidéo -> {OUT}\nSuite : node functions/scripts/add_stories.js --commit")


if __name__ == "__main__":
    oi = sys.argv.index("--offset") if "--offset" in sys.argv else -1
    off = int(sys.argv[oi + 1]) if oi >= 0 else 0
    cnt = int(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else 7
    build(cnt, off)
