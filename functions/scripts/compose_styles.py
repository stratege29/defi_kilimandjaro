# -*- coding: utf-8 -*-
"""
Exploration de COMPOSITIONS — 4 styles de posts qui s'harmonisent en grille.
Charte Vert Nuit (generate.py). Rend 4 échantillons + une planche 3x3.

Sortie : docs/instagram_assets/ai/styles/STYLE_*.png  +  _montage.jpg
Lancer : /tmp/igvenv/bin/python functions/scripts/compose_styles.py
"""
import os
from PIL import Image, ImageOps, ImageDraw
import generate as G

_HERE = os.path.dirname(os.path.abspath(__file__))
AI = os.path.abspath(os.path.join(_HERE, "..", "..", "docs/instagram_assets/ai"))
OUT = os.path.join(AI, "styles")
os.makedirs(OUT, exist_ok=True)

ACC = {"culture": (240, 122, 26), "nouchi": (232, 93, 158), "villes": (199, 123, 58), "foot": (61, 163, 93)}
W = H = 1080


def fit(d, text, max_w, mk, lo=40, hi=240):
    """Plus grande taille de police (via mk(size)) qui tient dans max_w."""
    best = mk(lo)
    while lo <= hi:
        mid = (lo + hi) // 2
        f = mk(mid)
        if d.textlength(text, font=f) <= max_w:
            best = f; lo = mid + 2
        else:
            hi = mid - 2
    return best


def disc(photo, size):
    im = ImageOps.fit(Image.open(photo).convert("RGB"), (size, size), Image.LANCZOS).convert("RGBA")
    m = Image.new("L", (size, size), 0); ImageDraw.Draw(m).ellipse([0, 0, size, size], fill=255)
    im.putalpha(m); return im


def medallion(img, photo, cx, cy, size, ring=G.GOLD):
    d = ImageDraw.Draw(img); r = size / 2 + 8
    d.ellipse([cx - r - 3, cy - r - 3, cx + r + 3, cy + r + 3], outline=G.HAIR, width=3)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=ring, width=6)
    di = disc(photo, size); img.paste(di, (int(cx - size / 2), int(cy - size / 2)), di)


def foot(d, fill=G.GOLD):
    d.text((W / 2, H - 56), "@defi_kilimandjaro", font=G.sans(28, "Bold"), fill=fill, anchor="mm")


# ---------- STYLE 1 — ÉNIGME (tuiles héro, sans photo) ----------
def s_enigme(categorie, question, nb_cells, accent):
    img = G.base(W, H, glow=G.KOLA, glow_strength=0.12); d = ImageDraw.Draw(img)
    d.rounded_rectangle([70, 66, 370, 124], 29, fill=G.S2, outline=G.HAIR, width=2)
    d.ellipse([92, 86, 112, 106], fill=accent)
    d.text((124, 95), "ÉNIGME", font=G.sans(24, "Bold"), fill=G.T1, anchor="lm")
    d.text((W - 70, 95), categorie.upper(), font=G.sans(22, "Bold"), fill=G.GOLD, anchor="rm")
    y = 250
    y = G.draw_block(d, question, G.serif(72, 700), 0, y, W - 200, G.T1, lh=1.1, align="center", anchor_cx=W / 2)
    y += 70
    gap = 18; avail = W - 200
    s = min(118, int((avail - (nb_cells - 1) * gap) / nb_cells))
    total = nb_cells * s + (nb_cells - 1) * gap
    G.cells(d, (W - total) / 2, y, nb_cells, s, gap, letters=None)
    d.rounded_rectangle([90, H - 150, W - 90, H - 90], 30, fill=G.S2, outline=G.GOLD, width=2)
    d.text((W / 2, H - 120), "TA RÉPONSE EN COMMENTAIRE", font=G.sans(26, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((W / 2, H - 50), "@defi_kilimandjaro", font=G.sans(20, "Medium"), fill=G.T3, anchor="mm")
    return img


# ---------- STYLE 2 — MÉDAILLON (photo + punchline) ----------
def s_medaillon(photo, kicker, title, accent):
    img = G.base(W, H, glow=G.GOLD, glow_strength=0.14)
    medallion(img, photo, W / 2, 330, 360)
    d = ImageDraw.Draw(img)
    d.text((W / 2, 575), kicker.upper(), font=G.sans(26, "Bold"), fill=accent, anchor="mm")
    y = 620
    y = G.draw_block(d, title, G.serif(82, 700), 0, y, W - 180, G.GOLD, lh=1.05, align="center", anchor_cx=W / 2)
    y += 18
    G.kente_bar(d, W / 2 - 150, y, 300)
    foot(d)
    return img


# ---------- STYLE 3 — PROVERBE (citation, respiration) ----------
def s_proverbe(texte, source, accent):
    img = G.base(W, H, glow=G.GOLD, glow_strength=0.15); d = ImageDraw.Draw(img)
    d.text((W / 2, 230), "“", font=G.serif(220, 700), fill=G.GOLD_DP, anchor="mm")
    y = 380
    y = G.draw_block(d, texte, G.serif(66, 650), 0, y, W - 220, G.T1, lh=1.22, align="center", anchor_cx=W / 2)
    y += 36
    G.kente_bar(d, W / 2 - 150, y, 300); y += 50
    d.text((W / 2, y), source.upper(), font=G.sans(24, "Bold"), fill=G.GOLD, anchor="mm")
    foot(d)
    return img


# ---------- STYLE 4 — AFFICHE TYPO (mot/chiffre géant) ----------
def s_affiche(word, sub, invert=False):
    if invert:
        img = G.base(W, H, glow=G.GOLD, glow_strength=0.0)
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, W, H], fill=G.GOLD)
        ink = (26, 18, 6); sub_c = (60, 44, 16)
    else:
        img = G.base(W, H, glow=G.GOLD, glow_strength=0.16); d = ImageDraw.Draw(img)
        ink = G.GOLD; sub_c = G.T2
    d.text((70, 80), "DÉFI KILIMANDJARO", font=G.sans(24, "Bold"), fill=(ink if invert else G.T3), anchor="lm")
    f = fit(d, word, W - 160, lambda s: G.serif(s, 700), lo=80, hi=300)
    d.text((W / 2, H / 2 - 20), word, font=f, fill=ink, anchor="mm")
    G.kente_bar(d, W / 2 - 150, H / 2 + 70, 300)
    if sub:
        d.text((W / 2, H / 2 + 130), sub, font=G.serif_it(40, 500), fill=sub_c, anchor="mm")
    d.text((W / 2, H - 56), "@defi_kilimandjaro", font=G.sans(28, "Bold"),
           fill=(ink if invert else G.GOLD), anchor="mm")
    return img


# ---------- STYLE 5 — LE MOT EN TUILES (grille qui écrit un mot) ----------
def s_mot(word, label, sub, accent, glow=G.GOLD):
    img = G.base(W, H, glow=glow, glow_strength=0.14); d = ImageDraw.Draw(img)
    d.text((W / 2, 168), label.upper(), font=G.sans(28, "Bold"), fill=accent, anchor="mm")
    letters = [c for c in word.upper() if c != " "]
    n = len(letters); margin = 110; maxw = W - 2 * margin; gap = 18
    s = min(156, int((maxw - (n - 1) * gap) / n))
    rows = [letters]
    if s < 104 and n > 5:                       # mot long -> 2 rangées
        half = (n + 1) // 2
        rows = [letters[:half], letters[half:]]
        m = max(len(r) for r in rows)
        s = min(156, int((maxw - (m - 1) * gap) / m))
    row_gap = 26
    total_h = len(rows) * s + (len(rows) - 1) * row_gap
    y0 = H / 2 - total_h / 2 + 20
    for ri, row in enumerate(rows):
        rw = len(row) * s + (len(row) - 1) * gap
        x0 = (W - rw) / 2
        ry = y0 + ri * (s + row_gap)
        for i, ch in enumerate(row):
            G.tile(d, x0 + i * (s + gap), ry, s, ch, sel=True)
    if sub:
        d.text((W / 2, y0 + total_h + 78), sub, font=G.serif_it(40, 500), fill=G.T1, anchor="mm")
    foot(d)
    return img


# ---------- STYLE 6 — LA LETTRE (1 lettre/post -> mosaïque de grille) ----------
def big_tile(d, x, y, s, ch, r=None):
    r = r or int(s * 0.12)
    d.rounded_rectangle([x, y + 9, x + s, y + s + 9], r, fill=G.GOLD_DP)
    d.rounded_rectangle([x, y, x + s, y + s], r, fill=G.GOLD)
    d.rounded_rectangle([x, y, x + s, y + int(s * 0.5)], r, fill=G.GOLD_LT)
    d.text((x + s / 2, y + s / 2), ch, font=G.sans(int(s * 0.52), "Bold"), fill=(26, 18, 6), anchor="mm")


def s_lettre(ch, kicker=None):
    img = G.base(W, H, glow=G.GOLD, glow_strength=0.13); d = ImageDraw.Draw(img)
    if kicker:
        d.text((W / 2, 110), kicker.upper(), font=G.sans(24, "Bold"), fill=G.T3, anchor="mm")
    s = 600
    big_tile(d, (W - s) / 2, (H - s) / 2 - 6, s, ch)
    d.text((W / 2, H - 56), "@defi_kilimandjaro", font=G.sans(28, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def demo_grid_word(word, P):
    """Maquette de feed 3 colonnes : la colonne du milieu épelle `word`."""
    letters = [c for c in word.upper() if c != " "]
    photos = [P("friends"), P("abidjan"), P("lagos"), P("alloco"), P("dakar"), P("masque")]

    def side(i):
        m = i % 6
        if m == 0: return s_enigme("Villes d'Afrique", "La plus grande ville d'Afrique ?", 5, ACC["villes"])
        if m == 1: return s_medaillon(photos[i % len(photos)], "Culture 225", "Tu connais ?", ACC["culture"])
        if m == 2: return s_proverbe("Quand tu ne sais pas où tu vas, regarde d'où tu viens.", "Proverbe africain", ACC["foot"])
        if m == 3: return s_affiche("J-3", "Bientôt.", invert=(i % 4 == 0))
        if m == 4: return s_mot("ALLOCO", "Pack Culture 225", "Bananes plantains frites.", ACC["culture"])
        return s_medaillon(photos[i % len(photos)], "Villes d'Afrique", "Trop facile ?", ACC["villes"])

    rows = len(letters); cell = 360; gap = 6
    mw = cell * 3 + gap * 2; mh = cell * rows + gap * (rows - 1)
    sheet = Image.new("RGB", (mw, mh), (8, 14, 11))
    for r in range(rows):
        trio = [side(2 * r), s_lettre(letters[r], "Pack Culture 225"), side(2 * r + 1)]
        for c, im in enumerate(trio):
            th = im.resize((cell, cell), Image.LANCZOS)
            sheet.paste(th, (c * (cell + gap), r * (cell + gap)))
    out = os.path.join(OUT, "_grid_word.jpg")
    sheet.save(out, "JPEG", quality=70)
    print("grid-word:", out, sheet.size)


def main():
    P = lambda k: os.path.join(AI, f"{k}.png")
    # 9 slots — séquence pensée pour la grille 3x3
    slots = [
        s_enigme("Villes d'Afrique", "« La ville rouge ». Tu sais laquelle ?", 9, ACC["villes"]),
        s_medaillon(P("friends"), "Le duel 1v1", "Le duel qui finit en fou rire.", ACC["foot"]),
        s_mot("ATTIÉKÉ", "La réponse", "Semoule de manioc fermentée.", ACC["culture"]),
        s_affiche("225", "Tu connais la Côte d'Ivoire ?", invert=True),
        s_enigme("Pack Culture 225", "Vrai ivoirien = tu trouves en 3 secondes.", 7, ACC["culture"]),
        s_mot("KILIMANDJARO", "Le sommet", "Le toit de l'Afrique. 5 895 m.", ACC["foot"]),
        s_medaillon(P("abidjan"), "Villes d'Afrique", "Trop facile pour un Abidjanais ?", ACC["villes"]),
        s_proverbe("Quand tu ne sais pas où tu vas, regarde d'où tu viens.", "Proverbe africain", ACC["foot"]),
        s_mot("ABIDJAN", "Villes d'Afrique", "Capitale économique du 225.", ACC["villes"]),
    ]
    # échantillons individuels (un par style)
    slots[0].save(os.path.join(OUT, "STYLE_1_enigme.png"))
    slots[1].save(os.path.join(OUT, "STYLE_2_medaillon.png"))
    slots[7].save(os.path.join(OUT, "STYLE_3_proverbe.png"))
    slots[3].save(os.path.join(OUT, "STYLE_4_affiche.png"))
    slots[2].save(os.path.join(OUT, "STYLE_5_mot.png"))
    slots[5].save(os.path.join(OUT, "STYLE_5_mot_long.png"))
    s_lettre("A", "Pack Culture 225").save(os.path.join(OUT, "STYLE_6_lettre.png"))
    # maquette feed : colonne du milieu = ATTIÉKÉ
    demo_grid_word("ATTIÉKÉ", P)
    # planche 3x3
    cell = 360; gap = 6
    mw = cell * 3 + gap * 2
    sheet = Image.new("RGB", (mw, mw), (8, 14, 11))
    for i, im in enumerate(slots):
        th = im.resize((cell, cell), Image.LANCZOS)
        r, c = divmod(i, 3)
        sheet.paste(th, (c * (cell + gap), r * (cell + gap)))
    sheet.save(os.path.join(OUT, "_montage.jpg"), "JPEG", quality=72)
    print("montage:", os.path.join(OUT, "_montage.jpg"), sheet.size)


if __name__ == "__main__":
    main()
