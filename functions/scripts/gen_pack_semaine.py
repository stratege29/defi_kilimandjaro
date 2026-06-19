# -*- coding: utf-8 -*-
"""
Rubrique « LE PACK DE LA SEMAINE » — carrousel qui met en avant UN pack/domaine
(montre la largeur du catalogue + invite au duel). Cover → échantillon → CTA.
Packs : culture (225) · nouchi · cdm (Coupe du Monde) · sommets (montagnes d'Afrique).

Usage : /tmp/igvenv/bin/python functions/scripts/gen_pack_semaine.py sommets 5 [--offset 0]
Sortie : docs/instagram_assets/carousels/pack_<name>/slide_*.png + carousel_plan.json
"""
import os
import sys
import io
import json
from PIL import ImageDraw, Image
import generate as G
import compose_styles as C
import gen_phrase as GP

W = 1080
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "docs/instagram_assets/carousels"))
DEV = os.path.abspath(os.path.join(HERE, "..", "..", "assets/data/devinettes/starter"))
SVG = os.path.abspath(os.path.join(HERE, "..", "..", "assets/svg/mountains"))
MT_JSON = os.path.abspath(os.path.join(HERE, "..", "..", "assets/data/mountains.json"))
BLOCK = {"DJOSS", "DJANDJOU", "WOUBI", "BANGALA", "GNAMAKODE", "BLEDARD", "BABTOU", "COXER", "FARADJE"}

PACKS = {
    "culture": {"title": "Culture 225", "kicker": "Pack Culture", "hook": "Tu te crois calé sur la Côte d'Ivoire ?", "accent": GP.ACC["culture"], "type": "dev", "src": "culture_ci", "tag": "#Culture225 #CôteDivoire"},
    "nouchi": {"title": "Crack Nouchi", "kicker": "Pack Nouchi", "hook": "Tu parles vraiment nouchi ?", "accent": GP.ACC["nouchi"], "type": "dev", "src": "crack_nouchi", "tag": "#Nouchi #Abidjan"},
    "cdm": {"title": "Coupe du Monde 2026", "kicker": "Pack Mondial", "hook": "Tu suis le Mondial ?", "accent": GP.ACC["foot"], "type": "cdm", "tag": "#CoupeDuMonde2026 #Football"},
    "sommets": {"title": "Sommets d'Afrique", "kicker": "Pack Géo", "hook": "Tu connais les toits du continent ?", "accent": GP.ACC["villes"], "type": "mt", "tag": "#Afrique #Géographie"},
}


def load_dev(src):
    return [{"riddle": (x.get("riddle") or {}).get("fr", ""), "answer": (x.get("answer") or "").strip()}
            for x in json.load(open(os.path.join(DEV, src + ".json"), encoding="utf-8"))
            if (x.get("answer") or "").strip().upper() not in BLOCK and (x.get("riddle") or {}).get("fr")]


def load_cdm():
    return [{"riddle": x["riddle"], "answer": x["answer"]} for x in json.load(open(os.path.join(HERE, "cdm2026.json"), encoding="utf-8"))]


def load_mt():
    m = json.load(open(MT_JSON, encoding="utf-8"))
    m.sort(key=lambda x: -x["altitude_m"])
    return m


def _cells(d, n, cy, accent):
    gap = 14
    s = min(96, int((W - 260 - (n - 1) * gap) / max(n, 1)))
    tot = n * s + (n - 1) * gap
    G.cells(d, (W - tot) / 2, cy, n, s, gap, letters=None)


def cover(p, n):
    img = G.base(W, W, glow=G.GOLD, glow_strength=0.14)
    d = ImageDraw.Draw(img)
    d.text((W / 2, 140), "LE PACK DE LA SEMAINE", font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((W / 2, 210), p["kicker"].upper(), font=G.sans(24, "Bold"), fill=p["accent"], anchor="mm")
    G.draw_block(d, p["title"], G.serif(84, 700), 0, 300, W - 150, G.T1, lh=1.05, align="center", anchor_cx=W / 2)
    G.draw_block(d, p["hook"], G.serif_it(46, 500), 0, 560, W - 200, G.T2, lh=1.2, align="center", anchor_cx=W / 2)
    G.kente_bar(d, W / 2 - 160, 740, 320)
    d.text((W / 2 - 28, W - 150), "GLISSE", font=G.sans(36, "Bold"), fill=G.T1, anchor="rm")
    cx = W / 2 + 22
    d.polygon([(cx, W - 170), (cx, W - 130), (cx + 36, W - 150)], fill=G.GOLD)
    d.text((W / 2, W - 70), "@defi_kilimandjaro", font=G.sans(28, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def item_dev(idx, total, riddle, ans, accent):
    img = G.base(W, W, glow=G.KOLA, glow_strength=0.10)
    d = ImageDraw.Draw(img)
    d.ellipse([70, 70, 150, 150], fill=G.S2, outline=accent, width=3)
    d.text((110, 110), str(idx), font=G.sans(42, "Bold"), fill=accent, anchor="mm")
    d.text((W - 70, 110), f"{idx}/{total}", font=G.sans(24, "Bold"), fill=G.T3, anchor="rm")
    G.draw_block(d, riddle, G.serif(50, 600), 0, 320, W - 160, G.T1, lh=1.25, align="center", anchor_cx=W / 2)
    n = len([c for c in ans.upper() if c.isalnum()])
    _cells(d, n, 760, accent)
    d.text((W / 2, W - 70), "Tu trouves ? Réponse dans le jeu", font=G.serif_it(34, 500), fill=G.T3, anchor="mm")
    return img


def item_mt(idx, total, mt, accent):
    img = G.base(W, W, glow=G.GOLD, glow_strength=0.12).convert("RGBA")
    d = ImageDraw.Draw(img)
    d.ellipse([70, 70, 150, 150], fill=G.S2, outline=accent, width=3)
    d.text((110, 110), str(idx), font=G.sans(42, "Bold"), fill=accent, anchor="mm")
    d.text((W - 70, 110), f"{idx}/{total}", font=G.sans(24, "Bold"), fill=G.T3, anchor="rm")
    d.text((W / 2, 250), mt["name"].upper(), font=G.serif(58, 700), fill=G.T1, anchor="mm")
    d.text((W / 2, 315), mt["country_name"], font=G.sans(26, "Bold"), fill=G.T2, anchor="mm")
    svg = os.path.join(SVG, mt["id"] + ".svg")
    if os.path.exists(svg):
        import cairosvg
        png = cairosvg.svg2png(url=svg, output_width=720, output_height=720)
        m = Image.open(io.BytesIO(png)).convert("RGBA")
        img.alpha_composite(m, (int((W - 720) / 2), W - 720))
    d.text((W / 2, W - 60), f"{mt['altitude_m']} m", font=G.serif(50, 700), fill=G.GOLD, anchor="mm")
    return img.convert("RGB")


def cta(p):
    img = G.base(W, W, glow=G.GOLD, glow_strength=0.14)
    d = ImageDraw.Draw(img)
    G.draw_block(d, f"Débloque le pack {p['title']}", G.serif(70, 700), 0, 300, W - 160, G.T1, lh=1.1, align="center", anchor_cx=W / 2)
    d.rounded_rectangle([140, 560, W - 140, 650], 45, fill=G.S2, outline=G.GOLD, width=2)
    d.text((W / 2, 605), "ET DÉFIE UN POTE DESSUS", font=G.sans(30, "Bold"), fill=G.GOLD, anchor="mm")
    d.text((W / 2, 770), "Joue sur l'app · lien en bio", font=G.serif_it(40, 500), fill=G.T2, anchor="mm")
    d.text((W / 2, W - 70), "@defi_kilimandjaro", font=G.sans(28, "Bold"), fill=G.GOLD, anchor="mm")
    return img


def build(pack, count, offset=0):
    if pack not in PACKS:
        print("Packs:", ", ".join(PACKS)); return
    p = PACKS[pack]
    if p["type"] == "dev":
        items = load_dev(p["src"])[offset:offset + count]
    elif p["type"] == "cdm":
        items = load_cdm()[offset:offset + count]
    else:
        items = load_mt()[offset:offset + count]
    n = len(items)
    if n < 3:
        print(f"Pas assez d'items ({n})."); return
    group = f"pack_{pack}"
    out = os.path.join(ROOT, group)
    os.makedirs(out, exist_ok=True)
    slides = ["slide_0.png"]
    cover(p, n).save(os.path.join(out, "slide_0.png"))
    for i, it in enumerate(items, 1):
        img = item_mt(i, n, it, p["accent"]) if p["type"] == "mt" else item_dev(i, n, it["riddle"], it["answer"], p["accent"])
        img.save(os.path.join(out, f"slide_{i}.png"))
        slides.append(f"slide_{i}.png")
    cta(p).save(os.path.join(out, f"slide_{n+1}.png"))
    slides.append(f"slide_{n+1}.png")
    cap = (f"🎴 LE PACK DE LA SEMAINE : {p['title']}.\n{p['hook']} Glisse pour goûter →\n"
           f"Débloque-le et défie un pote. 👇\n\n{p['tag']} #DéfiKilimandjaro #Quiz")
    json.dump({"group": group, "theme": pack, "slides": slides, "caption": cap},
              open(os.path.join(out, "carousel_plan.json"), "w"), ensure_ascii=False, indent=1)
    print(f"Pack de la semaine '{pack}' : {len(slides)} slides -> {out}")
    print(f"Suite : node functions/scripts/add_carousel.js {group} --date 2026-07-07 --commit")


if __name__ == "__main__":
    pack = sys.argv[1] if len(sys.argv) > 1 else "sommets"
    count = int(sys.argv[2]) if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else 5
    oi = sys.argv.index("--offset") if "--offset" in sys.argv else -1
    off = int(sys.argv[oi + 1]) if oi >= 0 else 0
    build(pack, count, off)
