# -*- coding: utf-8 -*-
"""
Générateur de STORIES Instagram 9:16 (1080×1920), style « Vert Nuit ».
Boucle quotidienne : ÉNIGME DU JOUR (matin) → LA RÉPONSE (soir), à partir des
vraies devinettes (culture_ci, crack_nouchi).

Usage : /tmp/igvenv/bin/python functions/scripts/gen_stories.py 7   # 7 jours
Sortie : docs/instagram_assets/stories/enigme_<i>.png + reponse_<i>.png + stories_plan.json
"""
import os
import sys
import json
from PIL import ImageDraw
import generate as G
import gen_phrase as GP

VW, VH = 1080, 1920
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "docs/instagram_assets/stories"))
os.makedirs(OUT, exist_ok=True)


def _letters(ans):
    return [c for c in ans.upper() if c not in (" ", "-", "'")]


def _grid(d, letters, y, filled, color):
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
    for ri, row in enumerate(rows):
        rw = len(row) * s + (len(row) - 1) * gap
        G.cells(d, (VW - rw) / 2, y + ri * (th + rg), len(row), s, gap,
                letters=(row if filled else None), color=color)
    return y + len(rows) * (th + rg)


def enigme_story(cat, accent, riddle, ans):
    img = G.base(VW, VH, glow=G.KOLA, glow_strength=0.13)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 235), "ÉNIGME DU JOUR", font=G.sans(40, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, 300), cat.upper(), font=G.sans(26, "Bold"), fill=accent, anchor="mm")
    G.kente_bar(d, VW / 2 - 170, 360, 340)
    G.draw_block(d, riddle, G.serif(52, 650), 0, 470, VW - 160, G.T1, lh=1.22, align="center", anchor_cx=VW / 2)
    _grid(d, _letters(ans), 980, filled=False, color=G.GOLD)
    d.rounded_rectangle([160, VH - 320, VW - 160, VH - 232], 44, fill=G.S2, outline=G.GOLD, width=2)
    d.text((VW / 2, VH - 276), "TA RÉPONSE EN DM", font=G.sans(32, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, VH - 150), "La réponse ce soir", font=G.serif_it(38, 500), fill=G.T2, anchor="mm")
    d.text((VW / 2, VH - 80), "@defi_kilimandjaro", font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def reponse_story(cat, accent, ans, expl):
    img = G.base(VW, VH, glow=G.SUCCESS, glow_strength=0.13)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 250), "LA RÉPONSE", font=G.sans(44, "Bold"), fill=G.SUCCESS, anchor="mm")
    d.text((VW / 2, 320), cat.upper(), font=G.sans(26, "Bold"), fill=accent, anchor="mm")
    y = _grid(d, _letters(ans), 470, filled=True, color=G.SUCCESS)
    G.draw_block(d, expl, G.serif_it(40, 500), 0, y + 80, VW - 200, G.T1, lh=1.26, align="center", anchor_cx=VW / 2)
    d.text((VW / 2, VH - 240), "Nouvelle énigme demain", font=G.serif(46, 650), fill=G.T1, anchor="mm")
    d.text((VW / 2, VH - 150), "Joue sur l'app · défi-Kili", font=G.sans(28, "Medium"), fill=G.T3, anchor="mm")
    d.text((VW / 2, VH - 80), "@defi_kilimandjaro", font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def build(count):
    devs = GP.load_devinettes()
    plan = []
    for i in range(count):
        dv = devs[i % len(devs)]
        cat, accent = GP.PACKS[dv["pack"]]
        enigme_story(cat, accent, dv["riddle"], dv["answer"]).save(os.path.join(OUT, f"enigme_{i}.png"))
        reponse_story(cat, accent, dv["answer"], dv["expl"]).save(os.path.join(OUT, f"reponse_{i}.png"))
        plan.append({"i": i, "answer": dv["answer"], "cat": cat,
                     "enigme": f"enigme_{i}.png", "reponse": f"reponse_{i}.png"})
    json.dump({"days": count, "items": plan}, open(os.path.join(OUT, "stories_plan.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{count} jours · {count*2} stories générées -> {OUT}")
    print("Suite : node functions/scripts/add_stories.js --commit")


if __name__ == "__main__":
    build(int(sys.argv[1]) if len(sys.argv) > 1 else 7)
