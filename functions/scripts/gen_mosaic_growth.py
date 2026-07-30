# -*- coding: utf-8 -*-
"""
Mosaïque COURTE « croissance » VARIÉE : un mot au milieu (lettres-reels), et des
CÔTÉS qui alternent pour casser la monotonie :
  - 1 côté = reel gameplay (question → révélation)  → portée
  - 1 côté = post « autre » varié (image) : médaillon photo / proverbe / mot révélé
    / « le saviez-vous » (réponse + fait)            → variété de ton & format
Toutes les vignettes sont carrées (1080²) → la grille reste alignée, le milieu
épelle le mot.

Usage : /tmp/igvenv/bin/python functions/scripts/gen_mosaic_growth.py AKWABA
Sortie : docs/instagram_assets/mosaic/<group>/media/ + growth_plan.json
"""
import os
import sys
import json
import gen_phrase as GP
import gen_mosaic_reels as GMR
import gen_reels_theme as GRT
import compose_styles as C

ROOT = GP.ROOT
HASH = "Joue sur défi-Kili (lien en bio) · #DéfiKilimandjaro"

# Mots écartés des CÔTÉS : retirés sur demande (CHAUD/ZOZO/PIPO/CALER) + nouchi
# edgy/obscurs + anti-doublon avec les rubriques (Complète/VS). Ne PAS bloquer
# les mots gardés du milieu/côtés (KPATA, FAROTER, GBANGBAN, MAQUIS, MOGO).
BLOCK = {
    "CHAUD", "ZOZO", "PIPO", "CALER",
    "ZIGUEHI", "KPACOLO", "GBONHI", "FRAYA", "GLOH", "GBAGBA", "CASSER", "AGBADJA",
    "ENJAILLE", "SAUCE", "ATTIEKE", "ALLOCO", "FOUTOU", "GAOU", "PAGNE", "FOYER",
    "GARBA", "ZOUGLOU", "PLACALI", "GINGEMBRE", "BISSAP", "KEDJENOU", "RESTAURANT",
    "BASSAM", "JACQUEVILLE",
}

# Mot imposé dans une cellule côté précise {(row, col): "ANSWER"} — sert à placer
# une signature reconnaissable (ex. BALAFON = instrument-signature du jeu).
PIN = {(5, 0): "BALAFON"}


def build(word):
    letters = GMR.clean_letters(word)
    n = len(letters)
    group = f"mosaic_growth_{GP.slug(word)}"
    out = os.path.join(ROOT, group)
    media = os.path.join(out, "media")
    os.makedirs(media, exist_ok=True)

    devs = GP.load_devinettes()
    mapped = GMR.assign([(r, ch) for r, ch in enumerate(letters)], devs)
    used = set(m[0]["answer"] for (_, _, m) in mapped if m)
    posts = []

    # --- MILIEU : lettres-reels DOUBLE RÔLE (la lettre tombe dans une devinette =
    #     question, ET la grande tuile épelle la phrase = design) ---
    for (r, ch, m) in mapped:
        GMR.render_reel(media, r, ch, m)
        posts.append({"row": r, "col": 1, "type": "reel", "reel": f"REEL_r{r}.mp4", "cover": f"COVER_r{r}.png",
                      "caption": f"🧩 Une phrase se cache dans la colonne du milieu… lis de haut en bas.\n{HASH} #Mosaïque"})

    # pools côtés (≠ du milieu)
    pool = [("Crack Nouchi", GP.ACC["nouchi"], d) for d in GRT.load("crack_nouchi") if d["answer"] not in used and d["answer"] not in BLOCK]
    pool += [("Culture 225", GP.ACC["culture"], d) for d in GRT.load("culture_ci") if d["answer"] not in used and d["answer"] not in BLOCK]
    pi = [0]

    def next_dev():
        while pi[0] < len(pool):
            cat, acc, d = pool[pi[0]]; pi[0] += 1
            if d["answer"] not in used:
                used.add(d["answer"]); return cat, acc, d
        return pool[0][0], pool[0][1], pool[0][2]

    def _find(ans):
        for cat, key, pack in (("Crack Nouchi", "nouchi", "crack_nouchi"), ("Culture 225", "culture", "culture_ci")):
            for d in GRT.load(pack):
                if d["answer"] == ans:
                    return cat, GP.ACC[key], d
        return None

    def dev_for(r, col):
        if (r, col) in PIN:
            hit = _find(PIN[(r, col)])
            if hit:
                used.add(hit[2]["answer"]); return hit
        return next_dev()

    def gameplay(k, r, col):
        cat, acc, d = dev_for(r, col)
        mp4 = f"side_{k}.mp4"
        GRT.encode(lambda t, c=cat, a=acc, dd=d: GRT.frame(c, a, dd["riddle"], GRT.letters_of(dd["answer"]), dd["expl"], t),
                   os.path.join(media, mp4))
        GP.side_enigme(cat, acc, d["riddle"], d["answer"])[0].save(os.path.join(media, f"side_{k}.png"))
        return {"row": r, "col": col, "type": "reel", "reel": mp4, "cover": f"side_{k}.png",
                "caption": f"Tu trouves en 3 s ? 👀 {d['riddle']}\n\nRéponse : {d['answer']} ✅ {d['expl']}\n\n{HASH}"}

    def variety(k, r, col, kind):
        img_name = f"var_{k}.png"
        if kind == "medaillon":
            ph, kick, title, acc = GP.MEDALLIONS[k % len(GP.MEDALLIONS)]
            C.s_medaillon(os.path.join(C.AI, f"{ph}.png"), kick, title, acc).save(os.path.join(media, img_name))
            cap = f"{title}\n\n{HASH} #Culture225"
        elif kind == "proverbe":
            txt, src = GP.PROVERBS[k % len(GP.PROVERBS)]
            C.s_proverbe(txt, src, GP.ACC["foot"]).save(os.path.join(media, img_name))
            cap = f"« {txt} »\n— {src}\n\n{HASH} #ProverbeAfricain"
        elif kind == "mot":
            cat, acc, d = dev_for(r, col)
            ex = d["expl"] if len(d["expl"]) <= 90 else d["expl"][:88] + "…"
            C.s_mot(d["answer"], "Le mot du jour", ex, acc).save(os.path.join(media, img_name))
            cap = f"{d['answer']} = {d['expl']}\n\n{HASH} #Nouchi"
        else:  # reponse / « le saviez-vous »
            cat, acc, d = dev_for(r, col)
            GP.side_reponse(cat, acc, d["answer"], d["expl"])[0].save(os.path.join(media, img_name))
            cap = f"Le saviez-vous ? {d['answer']} : {d['expl']}\n\n{HASH}"
        return {"row": r, "col": col, "type": "image", "img": img_name, "caption": cap}

    VAR = ["medaillon", "reponse", "proverbe", "mot", "medaillon", "reponse"]
    k = 0
    for r in range(n):
        reel_col, var_col = (0, 2) if r % 2 == 0 else (2, 0)  # alterne la colonne
        posts.append(gameplay(k, r, reel_col)); k += 1
        posts.append(variety(k, r, var_col, VAR[r % len(VAR)])); k += 1
        print(f"  rangée {r+1}/{n}")

    json.dump({"group": group, "word": word, "rows": n, "posts": posts},
              open(os.path.join(out, "growth_plan.json"), "w"), ensure_ascii=False, indent=1)
    nr = sum(1 for p in posts if p["type"] == "reel")
    print(f"\nMosaïque '{word}' VARIÉE : {n} rangées · {len(posts)} posts ({nr} reels + {len(posts)-nr} images) -> {out}")
    print("Suite : node functions/scripts/add_mosaic_growth.js", group, "--base 2026-06-22 --commit")


if __name__ == "__main__":
    build((sys.argv[1] if len(sys.argv) > 1 else "AKWABA").upper())
