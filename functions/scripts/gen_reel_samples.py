# -*- coding: utf-8 -*-
"""3 échantillons de reels de lettre-mosaïque (concepts 1/2/3). Lettre A + devinette ALLOCO."""
import os
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

ACCENT = (240, 122, 26)  # culture
CAT = "PACK CULTURE 225"
HOOK = "Vrai ivoirien ?"
QUESTION = "Banane bien mûre coupée en rondelles, je grésille dans l'huile et je dore au soleil."
ANS = "ALLOCO"
REVEAL = 0          # index de la lettre offerte (A)
LETTER = "A"

N = len(ANS)
GAP = 16
S = min(120, int((VW - 200 - (N - 1) * GAP) / N))
TOTAL = N * S + (N - 1) * GAP
X0 = (VW - TOTAL) / 2
GRID_Y = 760


def eob(t):
    c1 = 1.70158
    c3 = c1 + 1
    return 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)


def slot_x(i):
    return X0 + i * (S + GAP)


def scene(timer_p=0.0, reveal_tile_y=None, show_q=True, show_cta=True):
    img = G.base(VW, VH, glow=G.KOLA, glow_strength=0.12)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 200), CAT, font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, 300), HOOK, font=G.serif(62, 700), fill=G.T1, anchor="mm")
    G.kente_bar(d, VW / 2 - 160, 370, 320)
    if show_q:
        G.draw_block(d, QUESTION, G.serif_it(40, 500), 0, 460, VW - 180, G.T2, lh=1.25, align="center", anchor_cx=VW / 2)
    # grille (cases vides)
    G.cells(d, X0, GRID_Y, N, S, GAP, letters=None)
    # tuile-lettre offerte
    if reveal_tile_y is not None:
        C.big_tile(d, slot_x(REVEAL), reveal_tile_y, S, LETTER, r=14)
    # barre chrono
    by = GRID_Y + int(S * 1.18) + 70
    d.rounded_rectangle([X0, by, X0 + TOTAL, by + 20], 10, fill=G.S2)
    if timer_p > 0:
        d.rounded_rectangle([X0, by, X0 + TOTAL * timer_p, by + 20], 10, fill=ACCENT)
    d.text((VW / 2, by + 56), f"INDICE — {N} LETTRES", font=G.sans(24, "Bold"), fill=G.T3, anchor="mm")
    if show_cta:
        d.rounded_rectangle([170, VH - 250, VW - 170, VH - 170], 40, fill=ACCENT)
        d.text((VW / 2, VH - 210), "TA RÉPONSE EN COMMENTAIRE", font=G.sans(28, "Bold"), fill=(26, 18, 6), anchor="mm")
    d.text((VW / 2, VH - 110), "@defi_kilimandjaro", font=G.sans(32, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def teaser_frame(t):
    """Concept 3 : grande lettre animée + question, grille en fond."""
    img = G.base(VW, VH, glow=G.GOLD, glow_strength=0.14)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 230), CAT, font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, 340), "Tu connais le mot ?", font=G.serif(64, 700), fill=G.T1, anchor="mm")
    G.cells(d, X0, 1180, N, S, GAP, letters=None)   # grille en bas
    big = 520
    if t < 0.4:
        p = t / 0.4
        cy = -big + (VH * 0.5 + big) * min(eob(p), 1.05)
    else:
        cy = VH * 0.5 + int(8 * math.sin((t - 0.4) * math.pi * 3))
    C.big_tile(d, (VW - big) / 2, cy - big / 2, big, LETTER)
    d.text((VW / 2, VH - 110), "@defi_kilimandjaro", font=G.sans(32, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def encode(concept, frames, fps=30):
    tmp = os.path.join(OUT, f"_t{concept}")
    os.makedirs(tmp, exist_ok=True)
    for i, im in enumerate(frames):
        im.save(os.path.join(tmp, f"f{i:03d}.png"))
    mp4 = os.path.join(OUT, f"SAMPLE_concept{concept}.mp4")
    dur = len(frames) / fps
    cmd = ["ffmpeg", "-y", "-framerate", str(fps), "-i", os.path.join(tmp, "f%03d.png"),
           "-f", "lavfi", "-t", str(dur), "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest",
           "-movflags", "+faststart", mp4]
    r = subprocess.run(cmd, capture_output=True, text=True)
    shutil.rmtree(tmp, ignore_errors=True)
    if r.returncode != 0:
        print("ERR", concept, r.stderr[-500:])
    else:
        print("OK", os.path.basename(mp4))


def main():
    fps = 30
    target_y = GRID_Y + (int(S * 1.18) - S) // 2
    # Concept 1 : tout visible, lettre offerte posée, chrono qui descend
    f1 = []
    for i in range(int(fps * 5)):
        t = i / (fps * 5 - 1)
        f1.append(scene(timer_p=1 - t, reveal_tile_y=target_y))
    encode(1, f1, fps)
    # Concept 2 : la lettre tombe à sa place, puis chrono
    f2 = []
    F = int(fps * 5)
    for i in range(F):
        t = i / (F - 1)
        if t < 0.22:
            f2.append(scene(timer_p=0, reveal_tile_y=None))
        elif t < 0.45:
            p = (t - 0.22) / 0.23
            y = -S + (target_y + S) * min(eob(p), 1.05)
            f2.append(scene(timer_p=0, reveal_tile_y=y))
        else:
            tp = (t - 0.45) / 0.55
            f2.append(scene(timer_p=1 - tp, reveal_tile_y=target_y))
    encode(2, f2, fps)
    # Concept 3 : teaser générique
    f3 = [teaser_frame(i / (int(fps * 3.5) - 1)) for i in range(int(fps * 3.5))]
    encode(3, f3, fps)
    # cover commun
    C.s_lettre(LETTER, "Akwaba · la phrase cachée").save(os.path.join(OUT, "COVER_A.png"))


if __name__ == "__main__":
    main()
