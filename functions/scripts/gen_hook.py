# -*- coding: utf-8 -*-
"""
Couche HOOK 0-3s pour les reels — pattern-interrupt « Kacou Ananzè » (araignée-mascotte,
maître des devinettes) préfixé à chaque reel pour stopper le scroll AVANT le titre de
rubrique. Voir docs/instagram_mascotte_concept.md.

API :
  GH.HOOKS["vs"|"complete"|"explique"|"origine"|"gameplay"]  -> liste de punchlines
  GH.encode_hooked(content_render, mp4, hook_text, accent, fps, content_dur)
    -> encode HOOK_DUR s de carte hook + content_dur s de contenu en un seul mp4.

QA : /tmp/igvenv/bin/python functions/scripts/gen_hook.py  -> aperçus PNG.
"""
import os
import math
import shutil
import subprocess
from PIL import ImageDraw
import generate as G
import compose_styles as C

VW, VH = 1080, 1920
HOOK_DUR = 1.4  # secondes de hook avant le contenu

# Banque de punchlines (voix Tonton Kili) — pattern-interrupt par rubrique.
HOOKS = {
    "vs":       ["Ne reste pas neutre.", "Choisis ton camp ou assume.", "Y'a pas de match nul.",
                 "Toi, tu es team quoi ?", "On va te griller là."],
    "complete": ["Finis la phrase. Si tu peux.", "Bloqué dès la 1re ligne ?", "9 sur 10 sèchent ici.",
                 "Complète, vrai mogo.", "Tu vois la fin venir ?"],
    "explique": ["Ta daronne capte rien. Et toi ?", "Traduis-moi ça, le bilingue.", "Vrai 225 = tu décodes.",
                 "Décode, sinon assume.", "Ce message, tu le lis comment ?"],
    "origine":  ["Tu dis ce mot chaque jour…", "L'origine va te retourner.", "Tu le diras plus jamais pareil.",
                 "Devine d'où ça sort.", "Personne ne connaît la vraie."],
    "gameplay": ["3 secondes. Montre-moi.", "Trop facile pour toi ?", "Vrai ivoirien = tu trouves.",
                 "Tu sèches ou tu trouves ?", "Chrono lancé."],
}


def _clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def _eob(t):  # easeOutBack
    c1 = 1.70158
    return 1 + (c1 + 1) * ((t - 1) ** 3) + c1 * ((t - 1) ** 2)


def _web(d, cx, cy, r, accent):
    """Petite toile = emblème de Kacou Ananzè (8 rayons = 8 réponses)."""
    def pt(k, f=1.0):
        a = math.pi * 2 * k / 8 - math.pi / 2
        return (cx + r * f * math.cos(a), cy + r * f * math.sin(a))
    for k in range(8):
        d.line([(cx, cy), pt(k)], fill=accent, width=4)
    for f in (0.5, 0.82):
        ring = [pt(k, f) for k in range(8)]
        for k in range(8):
            d.line([ring[k], ring[(k + 1) % 8]], fill=accent, width=3)
    d.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=G.GOLD)


def hook_card(text, accent, t):
    """Carte hook animée : Tonton Kili lance le défi, la punchline monte/apparaît."""
    img = G.base(VW, VH, glow=accent, glow_strength=0.17)
    d = ImageDraw.Draw(img)
    # locuteur
    _web(d, VW // 2, 515, 72, accent)
    d.text((VW / 2, 645), "KACOU ANANZÈ", font=G.sans(36, "Bold"), fill=G.GOLD, anchor="mm")
    G.kente_bar(d, VW / 2 - 150, 690, 300)
    # punchline (apparition rapide : fondu + montée)
    p = min(_eob(_clamp(t / 0.42)), 1.04)
    yoff = int((1 - p) * 70)
    f = C.fit(d, text, VW - 170, lambda s: G.serif(s, 700), lo=66, hi=132)
    G.draw_block(d, text, f, 0, 980 - yoff, VW - 170, G.T1, lh=1.12, align="center", anchor_cx=VW / 2)
    # respiration / défi
    d.text((VW / 2, VH - 150), "défi-Kilimandjaro", font=G.serif_it(38, 500), fill=G.T2, anchor="mm")
    d.text((VW / 2, VH - 80), "@defi_kilimandjaro", font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def encode_hooked(content_render, mp4, hook_text, accent, fps, content_dur):
    """HOOK_DUR s de carte hook + content_dur s de contenu -> 1 mp4 (audio muet, +faststart)."""
    HF, CF = int(fps * HOOK_DUR), int(fps * content_dur)
    tmp = mp4 + "_f"
    os.makedirs(tmp, exist_ok=True)
    for i in range(HF):
        hook_card(hook_text, accent, i / max(HF - 1, 1)).save(os.path.join(tmp, f"f{i:04d}.png"))
    for j in range(CF):
        content_render(j / max(CF - 1, 1)).save(os.path.join(tmp, f"f{HF + j:04d}.png"))
    total = HOOK_DUR + content_dur
    cmd = ["ffmpeg", "-y", "-framerate", str(fps), "-i", os.path.join(tmp, "f%04d.png"),
           "-f", "lavfi", "-t", f"{total}", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", "-movflags", "+faststart", mp4]
    r = subprocess.run(cmd, capture_output=True, text=True)
    shutil.rmtree(tmp, ignore_errors=True)
    if r.returncode != 0:
        print("ffmpeg ERR", r.stderr[-300:])


if __name__ == "__main__":
    out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "docs/instagram_assets/hooks_preview"))
    os.makedirs(out, exist_ok=True)
    samples = [("vs", G.GOLD), ("explique", C.ACC["nouchi"]), ("origine", G.GOLD), ("gameplay", C.ACC["culture"])]
    for theme, acc in samples:
        hook_card(HOOKS[theme][0], acc, 0.85).save(os.path.join(out, f"hook_{theme}.png"))
    print("Aperçus ->", out)
