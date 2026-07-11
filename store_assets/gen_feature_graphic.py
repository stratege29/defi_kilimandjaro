#!/usr/bin/env python3
"""Feature graphic Google Play 1024x500 — style charte Vert Nuit / Or."""
import sys, os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "functions", "scripts"))
import generate as G
from PIL import Image, ImageDraw

W, H = 1024, 500
OUT = os.path.join(os.path.dirname(__file__), "play_feature_graphic.png")

img = G.base(W, H, glow=G.GOLD, glow_strength=0.18, glow_y=-0.05)
d = ImageDraw.Draw(img)

# Montagnes en fond
G.mountains(d, W, H, base_y=int(H * 0.98), color=G.S2, peaks=6, amp=0.30)

# Médaillon montagne (logo) à gauche
G.logo_medallion = getattr(G, "logo_medallion", None)
cx, cy, r = 170, H // 2, 92
d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=G.S1, outline=G.GOLD, width=6)
d.polygon(
    [(cx - r * 0.65, cy + r * 0.45), (cx - r * 0.12, cy - r * 0.5),
     (cx + r * 0.18, cy - r * 0.1), (cx + r * 0.42, cy - r * 0.42), (cx + r * 0.72, cy + r * 0.45)],
    fill=G.GOLD,
)
d.polygon([(cx - r * 0.25, cy - r * 0.28), (cx - r * 0.12, cy - r * 0.5), (cx + r * 0.01, cy - r * 0.28)], fill=G.T1)

# Titre + tagline
tx = 320
d.text((tx, 150), "DÉFI", font=G.sans(40, "Bold"), fill=G.T2, anchor="lm")
d.text((tx, 226), "Kilimandjaro", font=G.serif(96, 700), fill=G.GOLD, anchor="lm")
d.text((tx, 316), "Le jeu de mots de la sagesse ivoirienne", font=G.serif_it(34, 500), fill=G.T1, anchor="lm")

# Tuiles de lettres "SAGESSE"
letters = "SAGESSE"
s, gap = 52, 10
total = len(letters) * (s + gap) - gap
x0 = tx
y0 = 368
for i, ch in enumerate(letters):
    cx2 = x0 + i * (s + gap)
    d.rounded_rectangle([cx2, y0, cx2 + s, y0 + int(s * 1.15)], 10, fill=G.S1, outline=G.GOLD, width=3)
    d.text((cx2 + s / 2, y0 + s * 0.58), ch, font=G.sans(30, "Bold"), fill=G.T1, anchor="mm")

# Barre kente en bas
G.kente_bar(d, 0, H - 12, W, h=12)

img.save(OUT)
print(OUT, img.size)
