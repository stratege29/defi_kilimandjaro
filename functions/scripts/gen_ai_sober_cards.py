# -*- coding: utf-8 -*-
"""
Cartes IA « sobres » — charte Vert Nuit + grille de lettres, photo en MÉDAILLON
(petit disque cerclé d'or). Remplace le plein-cadre de photo_card.py.

Entrée  : docs/instagram_assets/ai/<subject>.png  (photos IA déjà générées)
Sortie  : docs/instagram_assets/ai/cards/CARD_<subject>.png
Lancer  : /tmp/igvenv/bin/python functions/scripts/gen_ai_sober_cards.py
"""
import os
from PIL import Image, ImageOps, ImageDraw
import generate as G

_HERE = os.path.dirname(os.path.abspath(__file__))
AI = os.path.abspath(os.path.join(_HERE, "..", "..", "docs/instagram_assets/ai"))
OUT = os.path.join(AI, "cards")
os.makedirs(OUT, exist_ok=True)

ACCENTS = {"culture": (240, 122, 26), "nouchi": (232, 93, 158),
           "villes": (199, 123, 58), "foot": (61, 163, 93)}


def photo_disc(photo, size):
    im = ImageOps.fit(Image.open(photo).convert("RGB"), (size, size), method=Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size, size], fill=255)
    im.putalpha(mask)
    return im


def medallion(img, photo, cx, cy, size, ring=G.GOLD):
    d = ImageDraw.Draw(img)
    r = size / 2 + 8
    # double anneau : halo sombre + cercle or
    d.ellipse([cx - r - 3, cy - r - 3, cx + r + 3, cy + r + 3], outline=G.HAIR, width=3)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=ring, width=6)
    disc = photo_disc(photo, size)
    img.paste(disc, (int(cx - size / 2), int(cy - size / 2)), disc)


def _chip(d, W, label, categorie, accent):
    d.rounded_rectangle([70, 66, 70 + 300, 66 + 58], 29, fill=G.S2, outline=G.HAIR, width=2)
    d.ellipse([92, 86, 112, 106], fill=accent)
    d.text((124, 95), label, font=G.sans(24, "Bold"), fill=G.T1, anchor="lm")
    d.text((W - 70, 95), categorie.upper(), font=G.sans(22, "Bold"), fill=G.GOLD, anchor="rm")


def card_riddle(out, photo, categorie, question, indice, nb_cells, accent):
    W, H = 1080, 1080
    img = G.base(W, H, glow=G.KOLA, glow_strength=0.12)
    d = ImageDraw.Draw(img)
    _chip(d, W, "ÉNIGME", categorie, accent)
    medallion(img, photo, W / 2, 300, 256)
    d = ImageDraw.Draw(img)
    y = 470
    y = G.draw_block(d, question, G.serif(56, 700), 0, y, W - 200, G.T1, lh=1.12, align="center", anchor_cx=W / 2)
    # grille de lettres (vides)
    y += 30
    avail = W - 240
    gap = 16
    s = min(92, int((avail - (nb_cells - 1) * gap) / nb_cells))
    total = nb_cells * s + (nb_cells - 1) * gap
    G.cells(d, (W - total) / 2, y, nb_cells, s, gap, letters=None)
    y += int(s * 1.18) + 52
    d.text((W / 2, y), "INDICE", font=G.sans(22, "Bold"), fill=G.GOLD, anchor="mm")
    y += 40
    G.draw_block(d, indice, G.serif_it(34, 500), 0, y, W - 280, G.T2, lh=1.2, align="center", anchor_cx=W / 2)
    d.rounded_rectangle([90, H - 150, W - 90, H - 90], 30, fill=G.S2, outline=G.GOLD, width=2)
    d.text((W / 2, H - 120), "TA RÉPONSE EN COMMENTAIRE", font=G.sans(26, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((W / 2, H - 50), "@defi_kilimandjaro", font=G.sans(20, "Medium"), fill=G.T3, anchor="mm")
    img.save(out)
    print("OK", os.path.basename(out))


def card_brand(out, photo, kicker, title, sub, accent):
    W, H = 1080, 1080
    img = G.base(W, H, glow=G.GOLD, glow_strength=0.14)
    medallion(img, photo, W / 2, 300, 300)
    d = ImageDraw.Draw(img)
    d.text((W / 2, 500), kicker.upper(), font=G.sans(26, "Bold"), fill=accent, anchor="mm")
    y = 540
    y = G.draw_block(d, title, G.serif(78, 700), 0, y, W - 200, G.GOLD, lh=1.04, align="center", anchor_cx=W / 2)
    y += 18
    G.kente_bar(d, W / 2 - 150, y, 300)
    y += 46
    G.draw_block(d, sub, G.serif_it(38, 500), 0, y, W - 260, G.T1, lh=1.25, align="center", anchor_cx=W / 2)
    G.footer(d, W, H)
    img.save(out)
    print("OK", os.path.basename(out))


def card_proverbe(out, photo, texte, source, accent):
    W, H = 1080, 1080
    img = G.base(W, H, glow=G.GOLD, glow_strength=0.14)
    medallion(img, photo, W / 2, 250, 230)
    d = ImageDraw.Draw(img)
    d.text((W / 2, 250 + 150 + 40), "“", font=G.serif(150, 700), fill=G.GOLD_DP, anchor="mm")
    y = 470
    y = G.draw_block(d, texte, G.serif(54, 650), 0, y, W - 240, G.T1, lh=1.24, align="center", anchor_cx=W / 2)
    y += 26
    G.kente_bar(d, W / 2 - 150, y, 300)
    y += 46
    d.text((W / 2, y), source.upper(), font=G.sans(24, "Bold"), fill=G.GOLD, anchor="mm")
    G.footer(d, W, H)
    img.save(out)
    print("OK", os.path.basename(out))


# subject -> spec
RIDDLES = {
    "abidjan":      ("Villes d'Afrique", "Trop facile pour un Abidjanais ?", "Capitale économique du 225.", 7, "villes"),
    "dakar":        ("Villes d'Afrique", "La porte la plus à l'ouest de l'Afrique.", "Capitale du Sénégal.", 5, "villes"),
    "lagos":        ("Villes d'Afrique", "La plus grande ville d'Afrique ?", "Mégapole côtière du Nigeria.", 5, "villes"),
    "marrakech":    ("Villes d'Afrique", "« La ville rouge ». Tu sais laquelle ?", "Ville marocaine mythique.", 9, "villes"),
    "yamoussoukro": ("Villes d'Afrique", "La plus grande basilique du monde est ici.", "Capitale politique du 225.", 12, "villes"),
    "attieke":      ("Pack Culture 225", "Vrai ivoirien = tu trouves en 3 secondes.", "Semoule de manioc fermentée.", 7, "culture"),
    "alloco":       ("Pack Culture 225", "Le snack n°1 des maquis.", "Bananes plantains mûres frites.", 6, "culture"),
}

BRAND = {
    "kilimandjaro": ("Le sommet", "5 895 m. Le toit de l'Afrique.", "Le plus haut sommet du continent.", "foot"),
    "balafon":      ("Coulisses", "Le son du jeu ? 100 % maison.", "Chaque note synthétisée, inspirée du balafon.", "culture"),
    "masque":       ("Culture 225", "Derrière chaque masque, une légende.", "Le patrimoine ivoirien, transformé en jeu.", "culture"),
    "player":       ("Défi Kilimandjaro", "Toi, ce soir.", "Le jeu de mots qui rend accro.", "villes"),
    "friends":      ("Le duel 1v1", "Le duel qui finit en fou rire.", "1v1 en temps réel. Tague ton adversaire.", "foot"),
    "duel":         ("La signature", "Le plus rapide gagne.", "Duel 1v1 en temps réel.", "foot"),
}

PROVERBES = {
    "baobab": ("La sagesse est comme un baobab : personne ne peut l'enlacer à lui seul.", "Proverbe akan", "culture"),
}


def main():
    done = 0
    for key, (cat, q, ind, n, acc) in RIDDLES.items():
        src = os.path.join(AI, f"{key}.png")
        if not os.path.exists(src):
            print("manquante:", key); continue
        card_riddle(os.path.join(OUT, f"CARD_{key}.png"), src, cat, q, ind, n, ACCENTS[acc]); done += 1
    for key, (kick, title, sub, acc) in BRAND.items():
        src = os.path.join(AI, f"{key}.png")
        if not os.path.exists(src):
            print("manquante:", key); continue
        card_brand(os.path.join(OUT, f"CARD_{key}.png"), src, kick, title, sub, ACCENTS[acc]); done += 1
    for key, (texte, source, acc) in PROVERBES.items():
        src = os.path.join(AI, f"{key}.png")
        if not os.path.exists(src):
            print("manquante:", key); continue
        card_proverbe(os.path.join(OUT, f"CARD_{key}.png"), src, texte, source, ACCENTS[acc]); done += 1
    print(f"\n{done} cartes sobres (médaillon) dans {OUT}")


if __name__ == "__main__":
    main()
