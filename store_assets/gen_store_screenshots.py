#!/usr/bin/env python3
"""Compose les screenshots Play Store 1080x1920 (9:16) : capture simulateur encadrée sur fond charte + accroche."""
import sys, os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "scripts"))
import generate as G
from PIL import Image, ImageDraw, ImageOps

W, H = 1080, 1920
DIR = os.path.dirname(__file__)

SHOTS = [
    ("shot_home.png",    "final_01_accueil.png",   "Gravis les sommets", "d'Afrique, mot après mot"),
    ("shot_game2.png", "final_02_devinette.png", "Résous des devinettes", "de la sagesse ivoirienne"),
    ("shot_victory.png", "final_03_victoire.png",  "Apprends en gagnant", "culture, proverbes et fleuves"),
    ("shot_sommets.png", "final_04_sommets.png",   "52 sommets à conquérir", "chaque pays, sa montagne"),
    ("shot_duel.png",    "final_05_duel.png",      "Défie tes amis en 1v1", "le plus rapide gagne"),
    ("shot_packs.png",   "final_06_packs.png",     "Des packs à explorer", "nouchi, football, Abidjan…"),
]


def rounded(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, im.size[0], im.size[1]], radius, fill=255)
    out = ImageOps.fit(im, im.size)
    out.putalpha(mask)
    return out


for src, dst, title, sub in SHOTS:
    base = G.base(W, H, glow=G.GOLD, glow_strength=0.15, glow_y=-0.1)
    d = ImageDraw.Draw(base)
    G.mountains(d, W, H, base_y=int(H * 1.0), color=G.S2, peaks=5, amp=0.18)

    d.text((W / 2, 120), title, font=G.serif(64, 700), fill=G.GOLD, anchor="mm")
    d.text((W / 2, 196), sub, font=G.serif_it(40, 500), fill=G.T1, anchor="mm")

    shot = Image.open(os.path.join(DIR, src))
    target_h = 1560
    ratio = target_h / shot.height
    shot = shot.resize((int(shot.width * ratio), target_h), Image.LANCZOS)
    shot = rounded(shot, 56)

    x = (W - shot.width) // 2
    y = 270
    d.rounded_rectangle([x - 5, y - 5, x + shot.width + 5, y + shot.height + 5], 60, outline=G.GOLD, width=5)
    base.paste(shot, (x, y), shot)

    G.kente_bar(d, 0, H - 14, W, h=14)
    base.save(os.path.join(DIR, dst))
    print(dst)
