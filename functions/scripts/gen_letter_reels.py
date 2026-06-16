# -*- coding: utf-8 -*-
"""
Reels de tuiles-lettres pour la mosaïque — vidéo 9:16 (la lettre tombe + rebondit),
+ cover carré 1:1 (la grille du profil reste alignée).

Usage : /tmp/igvenv/bin/python functions/scripts/gen_letter_reels.py A         # échantillon
        /tmp/igvenv/bin/python functions/scripts/gen_letter_reels.py A K W ... # plusieurs
Sortie : docs/instagram_assets/mosaic/reels/REEL_<ch>.mp4 + COVER_<ch>.png
"""
import os
import sys
import math
import shutil
import subprocess
from PIL import ImageDraw
import generate as G
import compose_styles as C

VW, VH = 1080, 1920
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "docs/instagram_assets/mosaic/reels"))
os.makedirs(OUT, exist_ok=True)


def ease_out_back(t):
    c1 = 1.70158
    c3 = c1 + 1
    return 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)


def bg():
    img = G.base(VW, VH, glow=G.GOLD, glow_strength=0.14)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 300), "AKWABA · LA PHRASE CACHÉE", font=G.sans(30, "Bold"), fill=G.T3, anchor="mm")
    G.kente_bar(d, VW / 2 - 160, VH - 250, 320)
    d.text((VW / 2, VH - 185), "Lis la colonne du milieu 👀", font=G.serif_it(40, 500), fill=G.T1, anchor="mm")
    d.text((VW / 2, VH - 110), "@defi_kilimandjaro", font=G.sans(34, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def render(ch, fps=30, dur=3.5):
    frames = int(fps * dur)
    base = bg()
    tmp = os.path.join(OUT, f"_f_{ch if ch.isalnum() else 'x'}")
    os.makedirs(tmp, exist_ok=True)
    S = 560
    cy_t = VH * 0.45
    for i in range(frames):
        t = i / (frames - 1)
        img = base.copy()
        d = ImageDraw.Draw(img)
        if t < 0.38:                       # chute + léger dépassement
            p = t / 0.38
            cy = -S + (cy_t + S) * min(ease_out_back(p), 1.05)
            s = S
        else:                              # repos + respiration douce
            cy = cy_t
            s = int(S * (1 + 0.02 * math.sin((t - 0.38) * math.pi * 3)))
        C.big_tile(d, (VW - s) / 2, cy - s / 2, s, ch)
        img.save(os.path.join(tmp, f"f{i:03d}.png"))
    mp4 = os.path.join(OUT, f"REEL_{ch}.mp4")
    cover = os.path.join(OUT, f"COVER_{ch}.png")
    C.s_lettre(ch, "Akwaba · la phrase cachée").save(cover)
    cmd = ["ffmpeg", "-y", "-framerate", str(fps), "-i", os.path.join(tmp, "f%03d.png"),
           "-f", "lavfi", "-t", str(dur), "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest",
           "-movflags", "+faststart", mp4]
    r = subprocess.run(cmd, capture_output=True, text=True)
    shutil.rmtree(tmp, ignore_errors=True)
    if r.returncode != 0:
        print("FFMPEG ERR:", r.stderr[-800:])
        sys.exit(1)
    print("OK", os.path.basename(mp4), os.path.basename(cover))
    return mp4, cover


if __name__ == "__main__":
    letters = sys.argv[1:] or ["A"]
    for ch in letters:
        render(ch.upper())
    print(f"\n{len(letters)} reel(s) -> {OUT}")
