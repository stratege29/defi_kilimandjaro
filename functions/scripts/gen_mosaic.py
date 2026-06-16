# -*- coding: utf-8 -*-
"""
Mode MOSAÏQUE — génère un feed 3 colonnes où une colonne épelle un mot.
Réutilise les compositions de compose_styles.py (Vert Nuit + or).

Usage :
  /tmp/igvenv/bin/python functions/scripts/gen_mosaic.py ATTIÉKÉ 1
                                                         (mot)   (colonne 0|1|2)
Sortie : docs/instagram_assets/mosaic/<group>/  + mosaic_plan.json
"""
import os
import sys
import json
import unicodedata
import compose_styles as C

ROOT = os.path.abspath(os.path.join(C._HERE, "..", "..", "docs/instagram_assets/mosaic"))
ACC = C.ACC
PHOTOS = ["friends", "abidjan", "lagos", "alloco", "dakar", "masque", "baobab", "attieke"]


def slug(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return "".join(ch.lower() for ch in s if ch.isalnum())


def side(i):
    """Carte latérale (vrai contenu) + légende, variée par index."""
    ph = lambda k: os.path.join(C.AI, f"{k}.png")
    m = i % 5
    if m == 0:
        return (C.s_enigme("Villes d'Afrique", "La plus grande ville d'Afrique ?", 5, ACC["villes"]),
                "Devine 👇 Réponse en commentaire.\n\n#VillesDAfrique #DéfiKilimandjaro")
    if m == 1:
        return (C.s_medaillon(ph(PHOTOS[i % len(PHOTOS)]), "Culture 225", "Tu connais ?", ACC["culture"]),
                "La culture du 225, en jeu 🇨🇮\n\n#Culture225 #DéfiKilimandjaro")
    if m == 2:
        return (C.s_proverbe("Quand tu ne sais pas où tu vas, regarde d'où tu viens.", "Proverbe africain", ACC["foot"]),
                "Sagesse du jour 🌍\n\n#ProverbeAfricain #DéfiKilimandjaro")
    if m == 3:
        return (C.s_affiche("J-?", "Bientôt.", invert=(i % 2 == 0)),
                "Ça arrive très vite 👀\n\n#DéfiKilimandjaro")
    return (C.s_mot("ALLOCO", "Pack Culture 225", "Bananes plantains frites.", ACC["culture"]),
            "Trop facile ? 🍌\n\n#Alloco #Culture225 #DéfiKilimandjaro")


def build(word, col=1):
    letters = [c for c in word.upper() if c != " "]
    L = len(letters)
    group = f"mosaic_{slug(word)}"
    out = os.path.join(ROOT, group)
    os.makedirs(out, exist_ok=True)
    posts = []
    si = 0
    for r in range(L):
        for c in range(3):
            fn = f"{group}_r{r}_c{c}.png"
            if c == col:
                img = C.s_lettre(letters[r], "Le mot caché")
                cap = (f"🧩 Un mot se cache dans la colonne du profil… ({r + 1}/{L})\n\n"
                       f"Sauras-tu le lire ? 👀\n\n#DéfiKilimandjaro #JeuDeMots #Mosaïque")
                is_letter = True
            else:
                img, cap = side(si)
                si += 1
                is_letter = False
            img.save(os.path.join(out, fn))
            posts.append({"row": r, "col": c, "file": fn, "isLetter": is_letter,
                          "letter": letters[r] if c == col else None, "caption": cap})
    plan = {"group": group, "word": word, "col": col, "rows": L, "posts": posts}
    with open(os.path.join(out, "mosaic_plan.json"), "w", encoding="utf-8") as f:
        json.dump(plan, f, ensure_ascii=False, indent=1)
    print(f"{len(posts)} posts ({L} rangées × 3) -> {out}")
    print(f"Colonne cachée : {col}  ·  mot : {word}")
    print("Étape suivante : node functions/scripts/add_mosaic.js", group, "(dry-run) puis --commit")


if __name__ == "__main__":
    w = sys.argv[1] if len(sys.argv) > 1 else "ATTIÉKÉ"
    c = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    build(w, c)
