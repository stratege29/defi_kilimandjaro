# -*- coding: utf-8 -*-
"""
Production des REELS (concept 2) pour les lettres d'une mosaïque-phrase.
Chaque lettre tombe à sa place dans une VRAIE devinette qui la contient.
Cover = grande tuile-lettre (la grille du profil épelle la phrase).

Mapping : --plan  (affiche lettre→devinette sans rendre)
Rendu   : (sans --plan) génère REEL_r<r>.mp4 + COVER_r<r>.png par rangée-lettre.

Usage : /tmp/igvenv/bin/python functions/scripts/gen_mosaic_reels.py "<phrase>" 1 [--plan]
Sortie : docs/instagram_assets/mosaic/<group>/reels/
"""
import os
import sys
import math
import json
import shutil
import unicodedata
import subprocess
from PIL import ImageDraw
import generate as G
import compose_styles as C
import gen_phrase as GP

VW, VH = 1080, 1920
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = GP.ROOT
PLAN = "--plan" in sys.argv
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
PHRASE = ARGS[0] if ARGS else "Akwaba sur defi-Kili, le jeu de lettres 100% Roots"
COL = int(ARGS[1]) if len(ARGS) > 1 else 1


def norm(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().upper()
    return "".join(c for c in s if c.isalnum())


def clean_letters(word):
    return [c for c in word.upper() if c.isalnum() or c == "%"]


def letter_rows(phrase):
    """(row_index, char) pour chaque rangée-lettre (séparateurs comptés mais ignorés ici)."""
    words = phrase.split()
    rows = []
    r = 0
    for wi, w in enumerate(words):
        for ch in clean_letters(w):
            rows.append((r, ch)); r += 1
        if wi < len(words) - 1:
            r += 1  # rangée séparatrice
    return rows


# Réponses exclues du pool public (trop crues pour un compte Instagram grand public).
BLOCK = {"DJOSS", "DJANDJOU", "WOUBI"}
ONLY = None
if "--rows" in sys.argv:
    _i = sys.argv.index("--rows")
    ONLY = {int(x) for x in sys.argv[_i + 1].split(",")}


def assign(rows, devs):
    """Map chaque lettre à une devinette unique qui la contient (sinon fallback)."""
    used = set()
    out = []
    for (r, ch) in rows:
        chosen = None
        if ch.isalpha():
            for i, dv in enumerate(devs):
                if i in used:
                    continue
                na = norm(dv["answer"])
                if na in BLOCK:
                    continue
                if ch in na:
                    used.add(i)
                    chosen = (dv, na.index(ch), len(na))
                    break
        out.append((r, ch, chosen))
    return out


def scene(cat, accent, question, n, reveal_idx, ch, reveal_y, timer_p, show_q=True, fallback=False):
    img = G.base(VW, VH, glow=(G.GOLD if fallback else G.KOLA), glow_strength=0.12)
    d = ImageDraw.Draw(img)
    d.text((VW / 2, 200), cat.upper(), font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((VW / 2, 300), ("Akwaba — la phrase se construit" if fallback else "Tu trouves ?"),
           font=G.serif(58, 700), fill=G.T1, anchor="mm")
    G.kente_bar(d, VW / 2 - 160, 372, 320)
    if show_q and question:
        G.draw_block(d, question, G.serif_it(38, 500), 0, 460, VW - 180, G.T2, lh=1.24, align="center", anchor_cx=VW / 2)
    gap = 16
    s = min(120, int((VW - 200 - (n - 1) * gap) / max(n, 1)))
    total = n * s + (n - 1) * gap
    x0 = (VW - total) / 2
    gy = 780
    G.cells(d, x0, gy, n, s, gap, letters=None)
    ty = gy + (int(s * 1.18) - s) // 2
    if reveal_y is not None:
        C.big_tile(d, x0 + reveal_idx * (s + gap), reveal_y if reveal_y is not None else ty, s, ch, r=14)
    by = gy + int(s * 1.18) + 70
    d.rounded_rectangle([x0, by, x0 + total, by + 20], 10, fill=G.S2)
    if timer_p > 0:
        d.rounded_rectangle([x0, by, x0 + total * timer_p, by + 20], 10, fill=accent)
    d.text((VW / 2, by + 54), (f"INDICE — {n} LETTRES" if not fallback else "LIS LA COLONNE DU MILIEU"),
           font=G.sans(24, "Bold"), fill=G.T3, anchor="mm")
    d.rounded_rectangle([170, VH - 250, VW - 170, VH - 170], 40, fill=accent)
    d.text((VW / 2, VH - 210), ("TA RÉPONSE EN COMMENTAIRE" if not fallback else "SUIS @DEFI_KILIMANDJARO"),
           font=G.sans(28, "Bold"), fill=(26, 18, 6), anchor="mm")
    d.text((VW / 2, VH - 110), "@defi_kilimandjaro", font=G.sans(32, "Bold"), fill=G.GOLD, anchor="mm")
    return img, s, gy, ty


def eob(t):
    c1 = 1.70158
    c3 = c1 + 1
    return 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)


def render_reel(outdir, r, ch, mapping, fps=30, dur=4.5):
    if mapping:
        dv, idx, n = mapping
        cat, accent = GP.PACKS[dv["pack"]]
        question = dv["riddle"]
        fb = False
    else:
        cat, accent, question, idx, n, fb = "Défi Kilimandjaro", G.GOLD, None, 0, 1, True
    F = int(fps * dur)
    # géométrie (via une 1ère passe)
    _, s, gy, ty = scene(cat, accent, question, n, idx, ch, None, 0, fallback=fb)
    frames = []
    for i in range(F):
        t = i / (F - 1)
        if t < 0.22:
            ry = None; tp = 0
        elif t < 0.45:
            p = (t - 0.22) / 0.23
            ry = -s + (ty + s) * min(eob(p), 1.05); tp = 0
        else:
            ry = ty; tp = 1 - (t - 0.45) / 0.55
        img, *_ = scene(cat, accent, question, n, idx, ch, ry, tp, fallback=fb)
        frames.append(img)
    tmp = os.path.join(outdir, f"_t{r}")
    os.makedirs(tmp, exist_ok=True)
    for i, im in enumerate(frames):
        im.save(os.path.join(tmp, f"f{i:03d}.png"))
    mp4 = os.path.join(outdir, f"REEL_r{r}.mp4")
    cmd = ["ffmpeg", "-y", "-framerate", str(fps), "-i", os.path.join(tmp, "f%03d.png"),
           "-f", "lavfi", "-t", str(dur), "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest",
           "-movflags", "+faststart", mp4]
    res = subprocess.run(cmd, capture_output=True, text=True)
    shutil.rmtree(tmp, ignore_errors=True)
    if res.returncode != 0:
        print("ERR r%d:" % r, res.stderr[-300:]); return
    C.s_lettre(ch, "Akwaba · la phrase cachée").save(os.path.join(outdir, f"COVER_r{r}.png"))


def main():
    rows = letter_rows(PHRASE)
    devs = GP.load_devinettes()
    mapped = assign(rows, devs)
    group = f"mosaic_phrase_{GP.slug(PHRASE.split()[0])}"
    outdir = os.path.join(ROOT, group, "reels")
    os.makedirs(outdir, exist_ok=True)
    fb = [ch for (_, ch, m) in mapped if m is None]
    print(f"{len(mapped)} lettres · {len(mapped)-len(fb)} mappées à une devinette · fallback: {fb}\n")
    for (r, ch, m) in mapped:
        if m:
            print(f"r{r:>2}  {ch}  ->  {m[0]['answer']:<12} (slot {m[1]})  « {m[0]['riddle'][:48]}… »")
        else:
            print(f"r{r:>2}  {ch}  ->  [fallback]")
    if PLAN:
        return
    todo = [x for x in mapped if ONLY is None or x[0] in ONLY]
    print(f"\nRendu des reels… ({len(todo)} rangée(s){' — filtre ' + str(sorted(ONLY)) if ONLY else ''})")
    for k, (r, ch, m) in enumerate(todo):
        render_reel(outdir, r, ch, m)
        if (k + 1) % 5 == 0:
            print(f"  {k+1}/{len(todo)}")
    meta = [{"row": r, "char": ch, "reel": f"REEL_r{r}.mp4", "cover": f"COVER_r{r}.png"} for (r, ch, m) in mapped]
    json.dump({"group": group, "letters": meta}, open(os.path.join(outdir, "reels_plan.json"), "w"), ensure_ascii=False, indent=1)
    print(f"\nOK -> {outdir}")


if __name__ == "__main__":
    main()
