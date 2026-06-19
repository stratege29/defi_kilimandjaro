# -*- coding: utf-8 -*-
"""
Générateur de CARROUSELS Instagram (1080×1080, feed) — format « saves/autorité ».
Listicle culturel : COVER → N slides item (mot + définition) → CTA.
Source : vraies devinettes (answer + explanation + tags).

Usage : /tmp/igvenv/bin/python functions/scripts/gen_carousel.py nouchi 5
Thèmes : nouchi · cuisine · culture
Sortie : docs/instagram_assets/carousels/<group>/slide_*.png + carousel_plan.json
"""
import os
import sys
import json
from PIL import ImageDraw
import generate as G
import compose_styles as C
import gen_phrase as GP

W = 1080
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "docs/instagram_assets/carousels"))
DEV = os.path.abspath(os.path.join(HERE, "..", "..", "assets/data/devinettes/starter"))

THEMES = {
    "nouchi": {"pack": "crack_nouchi", "tag": None, "kicker": "Crack Nouchi", "accent": GP.ACC["nouchi"],
               "title": lambda n: f"{n} mots nouchi que seuls les vrais connaissent",
               "cta": "Lequel t'a eu ?", "tags": "#Nouchi #Abidjan #CôteDivoire #225 #DéfiKilimandjaro"},
    "cuisine": {"pack": "culture_ci", "tag": "cuisine", "kicker": "Culture 225", "accent": GP.ACC["culture"],
                "title": lambda n: f"{n} plats ivoiriens à connaître absolument",
                "cta": "Ton préféré ?", "tags": "#CuisineIvoirienne #Foutou #Attiéké #225 #DéfiKilimandjaro"},
    "culture": {"pack": "culture_ci", "tag": None, "kicker": "Culture 225", "accent": GP.ACC["culture"],
                "title": lambda n: f"{n} énigmes de Côte d'Ivoire",
                "cta": "Combien tu en trouves ?", "tags": "#CôteDivoire #Culture225 #Devinette #DéfiKilimandjaro"},
}


def load(pack):
    p = os.path.join(DEV, pack + ".json")
    out = []
    for x in json.load(open(p, encoding="utf-8")):
        out.append({"answer": (x.get("answer") or "").strip(),
                    "expl": (x.get("explanation") or {}).get("fr", ""),
                    "tags": x.get("tags") or []})
    return out


def slug(s):
    return "".join(c for c in s.lower() if c.isalnum())


def cover(t, n):
    img = G.base(W, W, glow=G.GOLD, glow_strength=0.14)
    d = ImageDraw.Draw(img)
    d.text((W / 2, 150), t["kicker"].upper(), font=G.sans(28, "Bold"), fill=t["accent"], anchor="mm")
    G.draw_block(d, t["title"](n), G.serif(82, 700), 0, 320, W - 150, G.GOLD, lh=1.1, align="center", anchor_cx=W / 2)
    G.kente_bar(d, W / 2 - 160, 760, 320)
    d.text((W / 2 - 28, W - 150), "GLISSE", font=G.sans(36, "Bold"), fill=G.T1, anchor="rm")
    cx = W / 2 + 22
    d.polygon([(cx, W - 170), (cx, W - 130), (cx + 36, W - 150)], fill=G.GOLD)
    d.text((W / 2, W - 70), "@defi_kilimandjaro", font=G.sans(28, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def item(idx, total, word, definition, accent):
    img = G.base(W, W, glow=G.KOLA, glow_strength=0.10)
    d = ImageDraw.Draw(img)
    d.ellipse([70, 70, 150, 150], fill=G.S2, outline=accent, width=3)
    d.text((110, 110), str(idx), font=G.sans(42, "Bold"), fill=accent, anchor="mm")
    d.text((W - 70, 110), f"{idx}/{total}", font=G.sans(24, "Bold"), fill=G.T3, anchor="rm")
    f = C.fit(d, word.upper(), W - 160, lambda s: G.serif(s, 700), lo=56, hi=150)
    d.text((W / 2, 360), word.upper(), font=f, fill=G.GOLD, anchor="mm")
    G.kente_bar(d, W / 2 - 110, 460, 220)
    G.draw_block(d, definition, G.serif_it(44, 500), 0, 560, W - 180, G.T1, lh=1.3, align="center", anchor_cx=W / 2)
    d.text((W / 2, W - 70), "@defi_kilimandjaro", font=G.sans(26, "Bold"), fill=G.T3, anchor="mm")
    return img


def cta(t):
    img = G.base(W, W, glow=G.GOLD, glow_strength=0.14)
    d = ImageDraw.Draw(img)
    G.draw_block(d, t["cta"], G.serif(78, 700), 0, 330, W - 160, G.T1, lh=1.1, align="center", anchor_cx=W / 2)
    d.rounded_rectangle([140, 560, W - 140, 650], 45, fill=G.S2, outline=G.GOLD, width=2)
    d.text((W / 2, 605), "RÉPONDS EN DM", font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((W / 2, 770), "Joue sur l'app · défi-Kili", font=G.serif_it(40, 500), fill=G.T2, anchor="mm")
    d.text((W / 2, W - 70), "@defi_kilimandjaro", font=G.sans(28, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def build(theme, count):
    if theme not in THEMES:
        print("Thèmes:", ", ".join(THEMES)); return
    t = THEMES[theme]
    pool = [d for d in load(t["pack"]) if (t["tag"] is None or t["tag"] in d["tags"])]
    items = pool[:count]
    n = len(items)
    if n < 3:
        print(f"Pas assez de devinettes ({n}) pour {theme}."); return
    group = f"carousel_{theme}"
    out = os.path.join(ROOT, group)
    os.makedirs(out, exist_ok=True)
    slides = ["slide_0.png"]
    cover(t, n).save(os.path.join(out, "slide_0.png"))
    for i, it in enumerate(items, 1):
        item(i, n, it["answer"], it["expl"], t["accent"]).save(os.path.join(out, f"slide_{i}.png"))
        slides.append(f"slide_{i}.png")
    cta(t).save(os.path.join(out, f"slide_{n+1}.png"))
    slides.append(f"slide_{n+1}.png")
    cap = (f"{t['title'](n)} 👀\nGlisse pour les découvrir →\n{t['cta']} Réponds en DM.\n\n{t['tags']}")
    json.dump({"group": group, "theme": theme, "slides": slides, "caption": cap},
              open(os.path.join(out, "carousel_plan.json"), "w"), ensure_ascii=False, indent=1)
    print(f"Carrousel '{theme}' : {len(slides)} slides (cover + {n} + cta) -> {out}")
    print("Suite : node functions/scripts/add_carousel.js", group, "--date 2026-06-20 --commit")


if __name__ == "__main__":
    theme = sys.argv[1] if len(sys.argv) > 1 else "nouchi"
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    build(theme, count)
