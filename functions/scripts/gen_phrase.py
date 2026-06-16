# -*- coding: utf-8 -*-
"""
Mosaïque PHRASE — la colonne du milieu lit une phrase (1 mot par post).
Colonnes latérales = VRAI contenu, non répétitif : vraies devinettes (culture_ci,
crack_nouchi), réponses révélées, proverbes, médaillons photo.

Usage : /tmp/igvenv/bin/python functions/scripts/gen_phrase.py "Akwaba sur defi-Kili, le jeu de lettres 100% Roots" 1
Sortie : docs/instagram_assets/mosaic/<group>/ + mosaic_plan.json + _preview.jpg
"""
import os
import sys
import json
import unicodedata
from PIL import Image, ImageDraw
import generate as G
import compose_styles as C

W = H = 1080
REPO = os.path.abspath(os.path.join(C._HERE, "..", ".."))
ROOT = os.path.join(REPO, "docs/instagram_assets/mosaic")
DEV = os.path.join(REPO, "assets/data/devinettes/starter")
ACC = C.ACC
PACKS = {"culture_ci": ("Culture 225", ACC["culture"]), "crack_nouchi": ("Crack Nouchi", ACC["nouchi"])}
PROVERBS = [
    ("La sagesse est comme un baobab : personne ne peut l'enlacer à lui seul.", "Proverbe akan"),
    ("Quand tu ne sais pas où tu vas, regarde d'où tu viens.", "Proverbe africain"),
    ("Seul on va plus vite, ensemble on va plus loin.", "Proverbe africain"),
    ("C'est au bout de l'ancienne corde qu'on tisse la nouvelle.", "Proverbe africain"),
    ("La pirogue ne dédaigne pas les petits ruisseaux.", "Proverbe africain"),
    ("Le savoir est un jardin : si on ne le cultive pas, on ne récolte rien.", "Proverbe africain"),
]
MEDALLIONS = [
    ("abidjan", "Villes d'Afrique", "La perle des lagunes.", ACC["villes"]),
    ("attieke", "Pack Culture 225", "Le roi des maquis.", ACC["culture"]),
    ("lagos", "Villes d'Afrique", "La mégapole qui ne dort jamais.", ACC["villes"]),
    ("masque", "Culture 225", "Le patrimoine, transformé en jeu.", ACC["culture"]),
    ("baobab", "Sagesse", "L'arbre de vie.", ACC["culture"]),
    ("dakar", "Villes d'Afrique", "La pointe ouest du continent.", ACC["villes"]),
]


def slug(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return "".join(ch.lower() for ch in s if ch.isalnum())


# Réponses exclues partout (sensibles / crues pour un compte grand public).
BLOCK = {"WOUBI", "DJOSS", "DJANDJOU"}


def load_devinettes():
    pool = []
    for pack in ("culture_ci", "crack_nouchi"):
        p = os.path.join(DEV, f"{pack}.json")
        if not os.path.exists(p):
            continue
        for it in json.load(open(p, encoding="utf-8")):
            r = (it.get("riddle") or {}).get("fr") or ""
            a = (it.get("answer") or "").strip()
            e = (it.get("explanation") or {}).get("fr") or ""
            if a.upper() in BLOCK:
                continue
            if r and a:
                pool.append({"pack": pack, "riddle": r, "answer": a, "expl": e})
    # entrelace les deux packs pour varier les catégories
    cult = [x for x in pool if x["pack"] == "culture_ci"]
    nou = [x for x in pool if x["pack"] == "crack_nouchi"]
    out = []
    for i in range(max(len(cult), len(nou))):
        if i < len(cult):
            out.append(cult[i])
        if i < len(nou):
            out.append(nou[i])
    return out


def _letters(ans):
    return [c for c in ans.upper() if c not in (" ", "-", "'")]


def side_enigme(cat, accent, riddle, ans):
    img = G.base(W, H, glow=G.KOLA, glow_strength=0.12)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([70, 66, 370, 124], 29, fill=G.S2, outline=G.HAIR, width=2)
    d.ellipse([92, 86, 112, 106], fill=accent)
    d.text((124, 95), "ÉNIGME", font=G.sans(24, "Bold"), fill=G.T1, anchor="lm")
    d.text((W - 70, 95), cat.upper(), font=G.sans(22, "Bold"), fill=G.GOLD, anchor="rm")
    y = 240
    y = G.draw_block(d, riddle, G.serif(46, 650), 0, y, W - 150, G.T1, lh=1.2, align="center", anchor_cx=W / 2)
    n = len(_letters(ans))
    y = max(y + 46, 640)
    gap = 16
    s = min(92, int((W - 220 - (n - 1) * gap) / max(n, 1)))
    total = n * s + (n - 1) * gap
    G.cells(d, (W - total) / 2, y, n, s, gap, letters=None)
    d.rounded_rectangle([90, H - 150, W - 90, H - 90], 30, fill=G.S2, outline=G.GOLD, width=2)
    d.text((W / 2, H - 120), "TA RÉPONSE EN COMMENTAIRE", font=G.sans(26, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((W / 2, H - 50), "@defi_kilimandjaro", font=G.sans(20, "Medium"), fill=G.T3, anchor="mm")
    return img, f"{riddle}\n\nTa réponse en commentaire 👇\n\n#DéfiKilimandjaro #Devinette"


def side_reponse(cat, accent, ans, expl):
    img = G.base(W, H, glow=G.SUCCESS, glow_strength=0.12)
    d = ImageDraw.Draw(img)
    d.text((W / 2, 150), ("RÉPONSE · " + cat).upper(), font=G.sans(24, "Bold"), fill=G.T2, anchor="mm")
    letters = _letters(ans)
    n = len(letters)
    gap = 16
    rows = [letters]
    s = min(118, int((W - 200 - (n - 1) * gap) / max(n, 1)))
    if s < 90 and n > 6:
        h = (n + 1) // 2
        rows = [letters[:h], letters[h:]]
        m = max(len(r) for r in rows)
        s = min(118, int((W - 200 - (m - 1) * gap) / m))
    th = int(s * 1.18)
    rg = 22
    tot = len(rows) * th + (len(rows) - 1) * rg
    y0 = 320
    for ri, row in enumerate(rows):
        rw = len(row) * s + (len(row) - 1) * gap
        G.cells(d, (W - rw) / 2, y0 + ri * (th + rg), len(row), s, gap, letters=row, color=G.SUCCESS)
    y = y0 + tot + 64
    G.draw_block(d, expl, G.serif_it(34, 500), 0, y, W - 220, G.T1, lh=1.26, align="center", anchor_cx=W / 2)
    G.footer(d, W, H)
    return img, f"La réponse : {ans} ✅\n\n{expl}\n\n#DéfiKilimandjaro #Culture225"


def build(phrase, col=1):
    words = phrase.split()
    L = len(words)
    devs = load_devinettes()
    di = [0]
    pv = [0]
    md = [0]

    def next_side(kind):
        if kind == "proverbe":
            t, src = PROVERBS[pv[0] % len(PROVERBS)]
            pv[0] += 1
            return C.s_proverbe(t, src, ACC["foot"]), f"« {t} »\n— {src}\n\n#ProverbeAfricain #DéfiKilimandjaro"
        if kind == "medaillon":
            k, kick, title, acc = MEDALLIONS[md[0] % len(MEDALLIONS)]
            md[0] += 1
            ph = os.path.join(C.AI, f"{k}.png")
            return C.s_medaillon(ph, kick, title, acc), f"{title}\n\n#DéfiKilimandjaro #Culture225"
        dv = devs[di[0] % len(devs)]
        di[0] += 1
        cat, acc = PACKS[dv["pack"]]
        if kind == "reponse":
            return side_reponse(cat, acc, dv["answer"], dv["expl"])
        return side_enigme(cat, acc, dv["riddle"], dv["answer"])

    SEQ = ["enigme", "medaillon", "reponse", "enigme", "proverbe", "enigme",
           "reponse", "medaillon", "enigme", "enigme", "reponse", "proverbe",
           "enigme", "medaillon", "reponse", "enigme", "enigme", "proverbe"]

    group = f"mosaic_phrase_{slug(words[0])}"
    out = os.path.join(ROOT, group)
    os.makedirs(out, exist_ok=True)
    posts = []
    si = 0
    tiles = {}
    for r in range(L):
        for c in range(3):
            fn = f"{group}_r{r}_c{c}.png"
            if c == col:
                img = word_card(words[r])
                cap = (f"🧩 Une phrase se cache dans la colonne du milieu… ({r + 1}/{L})\n\n"
                       f"Akwaba ! Lis de haut en bas 👀\n\n#DéfiKilimandjaro #JeuDeMots #Mosaïque")
                is_letter = True
            else:
                img, cap = next_side(SEQ[si % len(SEQ)])
                si += 1
                is_letter = False
            img.save(os.path.join(out, fn))
            tiles[(r, c)] = img
            posts.append({"row": r, "col": c, "file": fn, "isLetter": is_letter,
                          "letter": words[r] if c == col else None, "caption": cap})
    plan = {"group": group, "word": phrase, "col": col, "rows": L, "posts": posts}
    with open(os.path.join(out, "mosaic_plan.json"), "w", encoding="utf-8") as f:
        json.dump(plan, f, ensure_ascii=False, indent=1)
    cell, gap = 280, 5
    sheet = Image.new("RGB", (cell * 3 + gap * 2, cell * L + gap * (L - 1)), (8, 14, 11))
    for (r, c), im in tiles.items():
        sheet.paste(im.resize((cell, cell), Image.LANCZOS), (c * (cell + gap), r * (cell + gap)))
    sheet.save(os.path.join(out, "_preview.jpg"), "JPEG", quality=68)
    print(f"{len(posts)} posts ({L} mots × 3) · {len(devs)} devinettes réelles dispo -> {out}")
    print("Colonne %d : %s" % (col, " / ".join(words)))
    print("Aperçu : _preview.jpg · Suite : node functions/scripts/add_mosaic.js", group)


def word_card(word):
    """Le mot épelé en TUILES dorées (côté scrabble). '-' et espace = gap ; ',' final ignoré."""
    img = G.base(W, H, glow=G.GOLD, glow_strength=0.13)
    d = ImageDraw.Draw(img)
    d.text((W / 2, 150), "AKWABA · LA PHRASE CACHÉE", font=G.sans(22, "Bold"), fill=G.T3, anchor="mm")
    raw = word.upper().rstrip(",.;:!?")
    slots = [None if c in ("-", " ") else c for c in raw]   # None = case vide (gap)
    n = len(slots)
    gap = 18
    s = min(150, int((W - 220 - (n - 1) * gap) / max(n, 1)))
    rw = n * s + (n - 1) * gap
    x0 = (W - rw) / 2
    y = H / 2 - s / 2 + 6
    for i, sl in enumerate(slots):
        if sl is not None:
            G.tile(d, x0 + i * (s + gap), y, s, sl, sel=True)
    d.text((W / 2, H - 56), "@defi_kilimandjaro", font=G.sans(28, "Bold"), fill=G.GOLD, anchor="mm")
    return img


if __name__ == "__main__":
    phrase = sys.argv[1] if len(sys.argv) > 1 else "Akwaba sur defi-Kili, le jeu de lettres 100% Roots"
    col = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    build(phrase, col)
