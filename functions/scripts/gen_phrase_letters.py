# -*- coding: utf-8 -*-
"""
Mosaïque PHRASE — UNE LETTRE PAR POST, colonne du milieu.
Chaque mot = N rangées (1 grosse tuile-lettre / post) ; rangée séparatrice entre mots.
Colonnes latérales = vrai contenu (devinettes réelles, réponses, proverbes, médaillons).

Usage : /tmp/igvenv/bin/python functions/scripts/gen_phrase_letters.py "Akwaba sur defi-Kili, le jeu de lettres 100% Roots" 1
Sortie : docs/instagram_assets/mosaic/<group>/ + mosaic_plan.json + _preview.jpg (1ères rangées)
"""
import os
import sys
import json
from PIL import Image
import compose_styles as C
import gen_phrase as GP
import gen_separator as SEP

W = H = 1080
ROOT = GP.ROOT


def clean_letters(word):
    return [c for c in word.upper() if c.isalnum() or c == "%"]


class Sides:
    """Distributeur de cartes latérales réelles, sans répétition de devinette."""

    def __init__(self):
        self.devs = GP.load_devinettes()
        self.di = self.pv = self.md = 0

    def nxt(self, kind):
        if kind == "proverbe":
            t, src = GP.PROVERBS[self.pv % len(GP.PROVERBS)]; self.pv += 1
            return C.s_proverbe(t, src, GP.ACC["foot"]), f"« {t} »\n— {src}\n\n#ProverbeAfricain #DéfiKilimandjaro"
        if kind == "medaillon":
            k, kick, title, acc = GP.MEDALLIONS[self.md % len(GP.MEDALLIONS)]; self.md += 1
            return C.s_medaillon(os.path.join(C.AI, f"{k}.png"), kick, title, acc), f"{title}\n\n#DéfiKilimandjaro #Culture225"
        dv = self.devs[self.di % len(self.devs)]; self.di += 1
        cat, acc = GP.PACKS[dv["pack"]]
        if kind == "reponse":
            return GP.side_reponse(cat, acc, dv["answer"], dv["expl"])
        return GP.side_enigme(cat, acc, dv["riddle"], dv["answer"])


SIDE_SEQ = ["enigme", "reponse", "enigme", "medaillon", "enigme", "reponse", "proverbe",
            "enigme", "reponse", "enigme", "medaillon", "enigme", "reponse", "enigme", "proverbe", "reponse"]


def build(phrase, col=1):
    words = phrase.split()
    plan_rows = []  # ('letter', ch) | ('sep', None)
    for wi, w in enumerate(words):
        for ch in clean_letters(w):
            plan_rows.append(("letter", ch))
        if wi < len(words) - 1:
            plan_rows.append(("sep", None))
    L = len(plan_rows)
    n_letters = sum(1 for k, _ in plan_rows if k == "letter")

    group = f"mosaic_phrase_{GP.slug(words[0])}"
    out = os.path.join(ROOT, group)
    os.makedirs(out, exist_ok=True)
    sides = Sides()
    si = 0
    posts = []
    preview = []

    def save(r, c, img, caption, is_letter, letter):
        fn = f"{group}_r{r}_c{c}.png"
        img.save(os.path.join(out, fn))
        posts.append({"row": r, "col": c, "file": fn, "isLetter": is_letter, "letter": letter, "caption": caption})

    for r, (kind, val) in enumerate(plan_rows):
        trio = [None, None, None]
        for c in range(3):
            if kind == "sep":
                img = SEP.sep_card(c == 1)
                save(r, c, img, "· · ·\n\n#DéfiKilimandjaro", False, None)
            elif c == col:
                img = C.s_lettre(val, "Akwaba · la phrase cachée")
                cap = ("🧩 La phrase se révèle lettre par lettre… Lis la colonne du milieu de haut en bas 👀\n\n"
                       "#DéfiKilimandjaro #JeuDeMots #Mosaïque")
                save(r, c, img, cap, True, val)
            else:
                img, cap = sides.nxt(SIDE_SEQ[si % len(SIDE_SEQ)]); si += 1
                save(r, c, img, cap, False, None)
            trio[c] = img
        if r < 13:
            preview.append(trio)

    plan = {"group": group, "word": phrase, "col": col, "rows": L, "posts": posts}
    with open(os.path.join(out, "mosaic_plan.json"), "w", encoding="utf-8") as f:
        json.dump(plan, f, ensure_ascii=False, indent=1)

    cell, gap = 280, 5
    sheet = Image.new("RGB", (cell * 3 + gap * 2, cell * len(preview) + gap * (len(preview) - 1)), (8, 14, 11))
    for r, trio in enumerate(preview):
        for c, im in enumerate(trio):
            sheet.paste(im.resize((cell, cell), Image.LANCZOS), (c * (cell + gap), r * (cell + gap)))
    sheet.save(os.path.join(out, "_preview.jpg"), "JPEG", quality=70)

    print(f"{len(posts)} posts · {n_letters} lettres + {L - n_letters} rangées séparatrices = {L} rangées -> {out}")
    mids = [val for k, val in plan_rows if k == "letter"]
    print("Colonne %d (haut→bas) : %s" % (col, " ".join(mids)))
    print("Aperçu (13 1ères rangées) : _preview.jpg · Suite : node functions/scripts/add_mosaic.js", group)


if __name__ == "__main__":
    phrase = sys.argv[1] if len(sys.argv) > 1 else "Akwaba sur defi-Kili, le jeu de lettres 100% Roots"
    col = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    build(phrase, col)
