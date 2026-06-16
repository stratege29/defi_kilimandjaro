# -*- coding: utf-8 -*-
"""Template 'photo + voile' — pose le texte de marque sur une vraie photo."""
import os, sys, math
import numpy as np
from PIL import Image, ImageOps, ImageDraw
import generate as G
from generate import (serif, serif_it, sans, draw_block, kente_bar, paste_logo,
                      ImageDraw as _D, CANVAS, GOLD, T1, KOLA)

ACCENTS = {"culture":(240,122,26),"nouchi":(232,93,158),"villes":(199,123,58),"foot":(61,163,93)}
def accent_for(pack):
    p=pack.lower()
    if "nouchi" in p: return ACCENTS["nouchi"]
    if "ville" in p: return ACCENTS["villes"]
    if "monde" in p or "foot" in p: return ACCENTS["foot"]
    return ACCENTS["culture"]

def photo_card(out, photo, kicker, title, sub=None, accent=None, W=1080, H=1350):
    accent = accent or GOLD
    img = ImageOps.fit(Image.open(photo).convert("RGB"), (W, H), method=Image.LANCZOS)
    # voile vert nuit : dégradé bas (opaque, pour le texte) + léger haut (logo)
    arr = np.array(img).astype(np.float32)
    ys = np.linspace(0, 1, H)
    bottom = np.clip((ys - 0.40) / 0.60, 0, 1) ** 1.3 * 0.92   # fort en bas
    top = np.clip((0.22 - ys) / 0.22, 0, 1) * 0.55             # léger en haut
    veil = np.clip(bottom + top, 0, 0.95)[:, None]
    for i in range(3):
        arr[:, :, i] = arr[:, :, i] * (1 - veil) + CANVAS[i] * veil
    img = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(img)
    # logo + kicker en haut
    paste_logo(img, W/2, 130, 104)
    d.text((W/2, 222), kicker.upper(), font=sans(26, "Bold"), fill=accent, anchor="mm")
    # bloc bas : kente + titre + (sous-titre)
    y = H - 440
    kente_bar(d, 80, y, 300); y += 40
    y = draw_block(d, title, serif(76, 700), 80, y, W-160, GOLD, lh=1.08)
    if sub:
        y += 14
        draw_block(d, sub, serif_it(38, 500), 80, y, W-200, T1, lh=1.25)
    d.text((W/2, H-58), "@defi_kilimandjaro", font=sans(28, "Bold"), fill=GOLD, anchor="mm")
    img.save(out)
    print("OK", os.path.basename(out))

def _placeholder(path, c1, c2):
    """Génère une fausse 'photo' (dégradé) pour la démo."""
    W, H = 1080, 1350
    yy = np.linspace(0, 1, H)[:, None]
    xx = np.linspace(0, 1, W)[None, :]
    g = (0.5*yy + 0.5*xx)
    arr = np.zeros((H, W, 3), np.float32)
    for i in range(3):
        arr[:, :, i] = c1[i]*(1-g[:, :]) + c2[i]*g[:, :]
    arr += np.random.randn(H, W, 1)*6
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(path)

if __name__ == "__main__":
    os.makedirs("photo_demo", exist_ok=True)
    # placeholders (en attendant tes vraies photos)
    _placeholder("photo_demo/_ph_food.jpg", (180, 90, 40), (90, 50, 20))
    _placeholder("photo_demo/_ph_city.jpg", (70, 110, 150), (20, 40, 70))
    photo_card("photo_demo/DEMO_plat.png", "photo_demo/_ph_food.jpg",
               "Pack Culture 225", "Si tu connais ce plat,\ntu es vraiment du 225.",
               sub="Indice : 7 lettres. Ta réponse en commentaire.", accent=ACCENTS["culture"])
    photo_card("photo_demo/DEMO_ville.png", "photo_demo/_ph_city.jpg",
               "Villes d'Afrique", "Non, ce n'est PAS\nAbidjan.",
               sub="La vraie capitale ? 12 lettres.", accent=ACCENTS["villes"])
