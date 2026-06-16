#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Générateur de visuels Instagram — Kilimandjaro (charte "Vert Nuit")."""
import os, math
from PIL import Image, ImageDraw, ImageFont
import numpy as np

OUT = os.path.dirname(os.path.abspath(__file__))
_HERE = os.path.dirname(os.path.abspath(__file__))
_LOCAL_FONTS = os.path.join(_HERE, "fonts")
GF = _LOCAL_FONTS if os.path.isdir(_LOCAL_FONTS) else "/usr/share/fonts/truetype/google-fonts"

# ---------------- Palette "Vert Nuit" ----------------
CANVAS   = (12, 23, 18)      # #0C1712
S1       = (21, 36, 28)      # #15241C
S2       = (30, 51, 40)      # #1E3328
HAIR     = (44, 64, 52)      # #2C4034
GOLD     = (233, 185, 73)    # #E9B949
GOLD_DP  = (193, 138, 42)    # #C18A2A
GOLD_LT  = (241, 199, 102)   # #F1C766
BRONZE   = (198, 138, 66)    # #C68A42
BRONZE_DK= (94, 61, 26)      # #5E3D1A
KOLA     = (240, 83, 59)     # #F0533B
SUCCESS  = (40, 199, 111)    # #28C76F
T1       = (244, 236, 216)   # #F4ECD8
T2       = (166, 174, 156)   # #A6AE9C
T3       = (113, 122, 108)   # #717A6C

# ---------------- Fonts ----------------
def serif(size, wght=700):
    f = ImageFont.truetype(f"{GF}/Lora-Variable.ttf", size)
    try: f.set_variation_by_axes([wght])
    except Exception: pass
    return f
def serif_it(size, wght=500):
    f = ImageFont.truetype(f"{GF}/Lora-Italic-Variable.ttf", size)
    try: f.set_variation_by_axes([wght])
    except Exception: pass
    return f
def sans(size, weight="Regular"):
    return ImageFont.truetype(f"{GF}/Poppins-{weight}.ttf", size)

# ---------------- Logo (vrai logo de l'app) ----------------
LOGO_PATH = os.path.join(OUT, "logo.png")
_logo_cache = {}
def logo_disc(size):
    if size in _logo_cache:
        return _logo_cache[size]
    im = Image.open(LOGO_PATH).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size, size], fill=255)
    im.putalpha(mask)
    _logo_cache[size] = im
    return im
def paste_logo(img, cx, cy, size, ring=True):
    """Colle le logo (disque) centré en (cx,cy), avec un léger halo doré."""
    disc = logo_disc(size)
    if ring:
        d = ImageDraw.Draw(img)
        r = size/2 + 6
        d.ellipse([cx-r, cy-r, cx+r, cy+r], outline=GOLD, width=4)
    img.paste(disc, (int(cx-size/2), int(cy-size/2)), disc)

# ---------------- Helpers ----------------
def base(w, h, glow=GOLD, glow_strength=0.16, glow_y=-0.08):
    """Canvas + soft radial gold glow at top."""
    img = Image.new("RGB", (w, h), CANVAS)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w*0.5, h*glow_y
    d = np.sqrt(((xx-cx)/(w*0.62))**2 + ((yy-cy)/(h*0.6))**2)
    a = np.clip(1.0 - d, 0, 1)**2 * glow_strength
    arr = np.array(img).astype(np.float32)
    for i in range(3):
        arr[:,:,i] += (glow[i]-arr[:,:,i]) * a
    return Image.fromarray(np.clip(arr,0,255).astype(np.uint8))

def kente_bar(d, x, y, w, h=10, seq=(GOLD,KOLA,BRONZE,SUCCESS,GOLD_DP)):
    """Thin decorative band of segments."""
    n = 16
    seg = w/n
    for i in range(n):
        c = seq[i % len(seq)]
        d.rectangle([x+i*seg, y, x+(i+1)*seg-3, y+h], fill=c)

def mountains(d, w, h, base_y, color=S2, peaks=5, amp=0.16):
    """Simple layered mountain silhouette across bottom."""
    pts=[(0,h)]
    step=w/(peaks)
    for i in range(peaks+1):
        px=i*step
        py=base_y - (amp*h)*(0.5+0.5*math.sin(i*1.7))
        pts.append((px,py))
    pts.append((w,h))
    d.polygon(pts, fill=color)

def wrap(d, text, font, max_w):
    words=text.split()
    lines=[]; cur=""
    for wd in words:
        t=(cur+" "+wd).strip()
        if d.textlength(t, font=font) <= max_w: cur=t
        else:
            if cur: lines.append(cur)
            cur=wd
    if cur: lines.append(cur)
    return lines

def draw_block(d, text, font, x, y, max_w, fill, lh=1.18, align="left", anchor_cx=None):
    lines = wrap(d, text, font, max_w)
    asc, desc = font.getmetrics()
    line_h = int((asc+desc)*lh)
    for ln in lines:
        if align=="center":
            cx = anchor_cx if anchor_cx is not None else x+max_w/2
            d.text((cx, y), ln, font=font, fill=fill, anchor="ma")
        else:
            d.text((x, y), ln, font=font, fill=fill)
        y += line_h
    return y

def tile(d, x, y, s, ch, sel=False):
    c1 = GOLD_LT if sel else (215,160,87)
    c2 = GOLD if sel else BRONZE
    r=18
    # shadow base
    d.rounded_rectangle([x, y+5, x+s, y+s+5], r, fill=(BRONZE_DK if not sel else GOLD_DP))
    d.rounded_rectangle([x, y, x+s, y+s], r, fill=c2)
    d.rounded_rectangle([x, y, x+s, y+int(s*0.5)], r, fill=c1)
    f=sans(int(s*0.5),"Bold")
    d.text((x+s/2, y+s/2), ch, font=f, fill=(26,18,6), anchor="mm")

def cells(d, x, y, n, s, gap, letters=None, color=GOLD):
    for i in range(n):
        cx=x+i*(s+gap)
        d.rounded_rectangle([cx, y, cx+s, y+int(s*1.18)], 12, outline=HAIR, width=3, fill=S1)
        if letters and i < len(letters) and letters[i] != " ":
            d.text((cx+s/2, y+int(s*1.18)/2), letters[i], font=serif(int(s*0.62),700), fill=color, anchor="mm")

def logo_mark(d, cx, cy, r):
    """Small mountain emblem in a gold ring."""
    d.ellipse([cx-r, cy-r, cx+r, cy+r], outline=GOLD, width=6)
    m=Image.new("RGBA",(r*2,r*2),(0,0,0,0)); md=ImageDraw.Draw(m)
    md.polygon([(r*0.2,r*1.5),(r*0.75,r*0.55),(r*1.05,r*0.95),(r*1.35,r*0.45),(r*1.85,r*1.5)], fill=GOLD)
    md.polygon([(r*0.62,r*0.7),(r*0.75,r*0.55),(r*0.88,r*0.7)], fill=T1)  # snow cap
    d.paste(Image.new("RGB",(1,1)), (0,0))  # noop
    return m

def footer(d, w, h, handle="@defi_kilimandjaro"):
    d.text((w/2, h-58), handle, font=sans(30,"Bold"), fill=GOLD, anchor="mm")

def save(img, name):
    p=os.path.join(OUT, name)
    img.save(p, "PNG")
    print("saved", name, img.size)

# ============================================================
# TEMPLATES
# ============================================================

def t_teaser(name, eyebrow, title, sub, page="", cta=None, glow=GOLD):
    W,H=1080,1350
    img=base(W,H,glow=glow); d=ImageDraw.Draw(img)
    mountains(d,W,H,H*0.78,color=S1,peaks=5,amp=0.18)
    mountains(d,W,H,H*0.86,color=S2,peaks=7,amp=0.12)
    # vrai logo
    cx,cy=W/2,236
    paste_logo(img, cx, cy, 210)
    d.text((cx, cy+150), eyebrow, font=sans(26,"Bold"), fill=GOLD, anchor="mm")
    # title
    y=cy+170
    y=draw_block(d,title,serif(96,700),0,y,W-160,GOLD,lh=1.0,align="center",anchor_cx=W/2)
    y+=18
    kente_bar(d, W/2-180, y, 360); y+=46
    y=draw_block(d,sub,serif_it(40,500),0,y,W-220,T1,lh=1.25,align="center",anchor_cx=W/2)
    if cta:
        d.rounded_rectangle([W/2-230, H-200, W/2+230, H-128], 36, fill=GOLD)
        d.text((W/2, H-164), cta, font=sans(30,"Bold"), fill=(26,18,6), anchor="mm")
    if page:
        d.text((W-70, H-60), page, font=sans(26,"Medium"), fill=T3, anchor="rm")
    footer(d,W,H)
    save(img,name)

def t_devinette(name, num, categorie, question, indice, reponse_label="RÉPONSE DEMAIN EN STORY", nb_cells=7):
    W,H=1080,1080
    img=base(W,H,glow=KOLA,glow_strength=0.13); d=ImageDraw.Draw(img)
    # top chip
    d.rounded_rectangle([70,70,70+360,70+58], 29, fill=S2, outline=HAIR, width=2)
    d.ellipse([92,90,112,110], fill=KOLA)
    d.text((124,99), f"ÉNIGME #{num}", font=sans(24,"Bold"), fill=T1, anchor="lm")
    d.text((W-70,99), categorie.upper(), font=sans(22,"Bold"), fill=GOLD, anchor="rm")
    # question
    y=230
    y=draw_block(d,question,serif(58,700),90,y,W-180,T1,lh=1.16)
    # tiles row (decor) — adaptive size to fit width
    y+=30
    avail=W-200; gap=16
    s=min(86, int((avail-(nb_cells-1)*gap)/nb_cells))
    total=nb_cells*s+(nb_cells-1)*gap
    cells(d, (W-total)/2, y, nb_cells, s, gap, letters=None)
    y+=int(s*1.18)+74
    # indice
    d.text((90,y), "INDICE", font=sans(22,"Bold"), fill=GOLD, anchor="lm"); y+=44
    draw_block(d,indice,serif_it(34,500),90,y,W-180,T2,lh=1.2)
    # CTA bottom
    d.rounded_rectangle([90,H-150,W-90,H-90], 30, fill=S2, outline=GOLD, width=2)
    d.text((W/2,H-120), "TA RÉPONSE EN COMMENTAIRE", font=sans(26,"Bold"), fill=GOLD, anchor="mm")
    d.text((W/2,H-50), reponse_label, font=sans(20,"Medium"), fill=T3, anchor="mm")
    save(img,name)

def t_reponse(name, num, reponse, mot, explication):
    W,H=1080,1080
    img=base(W,H,glow=SUCCESS,glow_strength=0.12); d=ImageDraw.Draw(img)
    d.text((W/2,150), f"RÉPONSE · DEVINETTE #{num}", font=sans(26,"Bold"), fill=T2, anchor="mm")
    # answer cells filled
    letters=list(mot.upper())
    n=len(letters); s=86; gap=16
    total=n*s+(n-1)*gap
    cells(d, (W-total)/2, 300, n, s, gap, letters=letters, color=SUCCESS)
    draw_block(d,reponse,serif(72,700),0,470,W-160,GOLD,lh=1.05,align="center",anchor_cx=W/2)
    y=620
    draw_block(d,explication,serif_it(36,500),0,y,W-220,T1,lh=1.28,align="center",anchor_cx=W/2)
    footer(d,W,H)
    save(img,name)

def t_proverbe(name, texte, source, slidelabel=None):
    W,H=1080,1080
    img=base(W,H,glow=GOLD,glow_strength=0.15); d=ImageDraw.Draw(img)
    # big quotation mark
    d.text((90,90), "“", font=serif(220,700), fill=GOLD_DP, anchor="la")
    y=320
    y=draw_block(d,texte,serif(66,650),100,y,W-200,T1,lh=1.22)
    y+=40
    kente_bar(d,100,y,300); y+=44
    d.text((100,y), source.upper(), font=sans(24,"Bold"), fill=GOLD, anchor="lm")
    footer(d,W,H)
    if slidelabel:
        d.text((W-70,70), slidelabel, font=sans(22,"Medium"), fill=T3, anchor="rm")
    save(img,name)

def t_sv_cover(name, kicker, title, swipe="GLISSE  >"):
    W,H=1080,1350
    img=base(W,H,glow=GOLD); d=ImageDraw.Draw(img)
    mountains(d,W,H,H*0.84,color=S1,peaks=6,amp=0.12)
    d.text((90,150), kicker.upper(), font=sans(28,"Bold"), fill=GOLD, anchor="lm")
    y=240
    draw_block(d,title,serif(92,700),90,y,W-180,T1,lh=1.05)
    d.rounded_rectangle([90,H-180,90+260,H-118], 31, fill=GOLD)
    d.text((90+130,H-149), swipe, font=sans(28,"Bold"), fill=(26,18,6), anchor="mm")
    footer(d,W,H)
    save(img,name)

def t_sv_slide(name, idx, head, body, big=None):
    W,H=1080,1350
    img=base(W,H,glow=GOLD,glow_strength=0.10); d=ImageDraw.Draw(img)
    d.text((90,130), idx, font=serif(46,700), fill=GOLD_DP, anchor="lm")
    y=210
    if big:
        d.text((90,y), big, font=serif(150,700), fill=GOLD); y+=210
    y=draw_block(d,head,sans(52,"Bold"),90,y,W-180,T1,lh=1.12); y+=24
    draw_block(d,body,serif_it(38,500),90,y,W-180,T2,lh=1.32)
    kente_bar(d,90,H-150,300)
    footer(d,W,H)
    save(img,name)

def t_sv_end(name, punch, cta="ENREGISTRE & PARTAGE", follow="Suis @defi_kilimandjaro"):
    W,H=1080,1350
    img=base(W,H,glow=KOLA,glow_strength=0.14); d=ImageDraw.Draw(img)
    y=300
    y=draw_block(d,punch,serif(70,700),0,y,W-200,GOLD,lh=1.12,align="center",anchor_cx=W/2)
    y+=60
    d.rounded_rectangle([W/2-300,y,W/2+300,y+76],38,fill=GOLD)
    d.text((W/2,y+38), cta, font=sans(28,"Bold"), fill=(26,18,6), anchor="mm")
    y+=120
    d.text((W/2,y), follow, font=sans(30,"Medium"), fill=T1, anchor="mm")
    save(img,name)

def t_reel_cover(name, kicker, title, tag):
    W,H=1080,1920
    img=base(W,H,glow=GOLD,glow_strength=0.18,glow_y=-0.02); d=ImageDraw.Draw(img)
    mountains(d,W,H,H*0.7,color=S1,peaks=5,amp=0.16)
    mountains(d,W,H,H*0.78,color=S2,peaks=7,amp=0.1)
    # logo en haut
    paste_logo(img, W/2, 250, 150)
    # play button
    cx,cy=W/2,620
    d.ellipse([cx-70,cy-70,cx+70,cy+70], outline=T1, width=6)
    d.polygon([(cx-22,cy-34),(cx-22,cy+34),(cx+38,cy)], fill=T1)
    d.text((W/2,cy+150), kicker.upper(), font=sans(30,"Bold"), fill=GOLD, anchor="mm")
    y=cy+220
    y=draw_block(d,title,serif(104,700),0,y,W-160,T1,lh=1.04,align="center",anchor_cx=W/2)
    y+=30
    d.rounded_rectangle([W/2-220,y,W/2+220,y+70],35,fill=KOLA)
    d.text((W/2,y+35), tag, font=sans(28,"Bold"), fill=(255,255,255), anchor="mm")
    footer(d,W,H-40)
    save(img,name)

def t_countdown(name, days, line):
    W,H=1080,1080
    img=base(W,H,glow=GOLD,glow_strength=0.18); d=ImageDraw.Draw(img)
    mountains(d,W,H,H*0.8,color=S1,peaks=6,amp=0.12)
    paste_logo(img, W/2, 150, 120)
    d.text((W/2,258), "COMPTE À REBOURS", font=sans(28,"Bold"), fill=GOLD, anchor="mm")
    d.text((W/2,480), days, font=serif(300,700), fill=GOLD, anchor="mm")
    d.text((W/2,640), "AVANT L'ASCENSION", font=sans(34,"Bold"), fill=T1, anchor="mm")
    draw_block(d,line,serif_it(36,500),0,730,W-220,T2,lh=1.25,align="center",anchor_cx=W/2)
    footer(d,W,H)
    save(img,name)

def t_meme(name, top, a, b):
    W,H=1080,1080
    img=base(W,H,glow=GOLD,glow_strength=0.10); d=ImageDraw.Draw(img)
    draw_block(d,top,sans(40,"Bold"),0,90,W-140,T1,lh=1.15,align="center",anchor_cx=W/2)
    # panel A
    d.rounded_rectangle([80,300,W-80,560],24,fill=S2,outline=SUCCESS,width=3)
    d.text((110,330),"LE MOT EN 3 SECONDES", font=sans(28,"Bold"), fill=SUCCESS, anchor="lm")
    draw_block(d,a,serif_it(34,500),110,380,W-220,T1,lh=1.2)
    # panel B
    d.rounded_rectangle([80,620,W-80,900],24,fill=S2,outline=KOLA,width=3)
    d.text((110,650),"LE DERNIER MOT QUI RÉSISTE", font=sans(28,"Bold"), fill=KOLA, anchor="lm")
    draw_block(d,b,serif_it(34,500),110,700,W-220,T1,lh=1.2)
    footer(d,W,H)
    save(img,name)

# ============================================================
# CONTENU — 14 jours
# ============================================================
if __name__ == "__main__":
    # --- J1 : carrousel teaser (3 slides) ---
    t_teaser("J01_teaser_1.png","BIENTÔT","Défi Kilimandjaro","Le jeu de mots où chaque montagne est un défi à relever.","1/3",glow=GOLD)
    t_teaser("J01_teaser_2.png","LE PRINCIPE","Gravis.\nDevine.\nDéfie.","Des packs de thèmes variés. Plus tu montes, plus c'est dur.","2/3",glow=KOLA)
    t_teaser("J01_teaser_3.png","LA SIGNATURE","Le duel\n1v1","Affronte un autre joueur en temps réel. Le plus rapide gagne.","3/3",cta="SUIS @DEFI_KILIMANDJARO",glow=GOLD)

    # --- J2 : reel cover (gameplay) ---
    t_reel_cover("J02_reel_gameplay.png","Premier aperçu","Relie les lettres.\nForme les mots.","GAMEPLAY")

    # --- J3 : énigme du jour #1 (pack Cuisine) ---
    t_devinette("J03_devinette1.png",1,"Pack · Culture 225","Semoule de manioc fermentée, je fais la fierté des maquis et je me marie au poisson braisé. Qui suis-je ?","Mon nom commence par A — et on me mange partout à Abidjan.",nb_cells=7)

    # --- J4 : carrousel "les packs à thème" ---
    t_sv_cover("J04_sv_1.png","Le principe","Un jeu,\nplusieurs\npacks\nde thèmes")
    t_sv_slide("J04_sv_2.png","01","Tu choisis ton terrain","Culture 225, Nouchi, villes d'Afrique, masques, Coupe du Monde 2026, pays francophones… Chaque pack a son univers.")
    t_sv_slide("J04_sv_3.png","02","Plusieurs packs, un seul fil","Le point commun ? Des montagnes à gravir. Le thème change, le défi reste.")
    t_sv_slide("J04_sv_4.png","03","Toujours plus de packs","De nouveaux thèmes arrivent régulièrement — actu, culture, sport. De quoi ne jamais redescendre.")
    t_sv_end("J04_sv_5.png","Quel pack veux-tu voir en premier ?", cta="DIS-LE EN COMMENTAIRE")

    # --- J5 : proverbe #1 ---
    t_proverbe("J05_proverbe1.png","La sagesse est comme un baobab : personne ne peut l'enlacer à lui seul.","Proverbe akan")

    # --- J6 : reel cover (audio balafon/kora) ---
    t_reel_cover("J06_reel_audio.png","Dans les coulisses","Chaque note est\nsynthétisée,\nzéro fichier audio.","SON · BALAFON")

    # --- J7 : réponse devinette #1 + relance ---
    t_reponse("J07_reponse1.png",1,"L'Attiéké","ATTIEKE","Semoule de manioc fermentée, emblème de la cuisine ivoirienne. Bien joué aux grimpeurs qui ont trouvé !")

    # --- J8 : carrousel concept "la montagne = la difficulté" ---
    t_sv_cover("J08_concept_1.png","Pourquoi une montagne ?","La montagne,\nc'est la\ndifficulté")
    t_sv_slide("J08_concept_2.png","01","Chaque palier monte d'un cran","Plus tu grimpes, plus les mots se corsent. La montagne mesure ta progression.")
    t_sv_slide("J08_concept_3.png","02","Le sommet ultime","Le Kilimandjaro : 5 895 m, plus haut sommet d'Afrique et plus haute montagne isolée du monde. Tout un programme.", big="5895")
    t_sv_slide("J08_concept_4.png","03","Solo ou en duel","Le mode solo se joue hors-ligne. Le défi 1v1, lui, se joue en temps réel contre un autre grimpeur.")
    t_sv_end("J08_concept_5.png","Jusqu'où penses-tu pouvoir grimper ?", cta="DIS-LE EN COMMENTAIRE")

    # --- J9 : reel cover (duel 1v1) ---
    t_reel_cover("J09_reel_duel.png","La signature","Duel 1v1.\nLe plus rapide\ngagne.","TEMPS RÉEL")

    # --- J10 : énigme #2 (pack Coupe du Monde 2026) ---
    t_devinette("J10_devinette2.png",2,"Pack · Coupe du Monde 2026","Pays hôte du Mondial 2026 avec les États-Unis et le Mexique, je porte une feuille d'érable. Qui suis-je ?","Première triple organisation de l'histoire. 6 lettres.",reponse_label="RÉPONSE DIMANCHE EN STORY",nb_cells=6)

    # --- J11 : carrousel "le défi 1v1" ---
    t_sv_cover("J11_sv2_1.png","La signature","Le défi 1v1\nen temps\nréel")
    t_sv_slide("J11_sv2_2.png","01","Même grille, même chrono","Tu affrontes un autre joueur en direct. Le premier à former le mot remporte la manche.")
    t_sv_slide("J11_sv2_3.png","02","Un rival en quelques secondes","Le matchmaking te trouve un adversaire à ton niveau presque instantanément.")
    t_sv_slide("J11_sv2_4.png","03","Grimpe au classement","Chaque victoire te fait monter. Les meilleurs grimpeurs s'affichent en haut de la montagne.")
    t_sv_end("J11_sv2_5.png","Qui sera ton premier adversaire ?", cta="TAGUE-LE EN COMMENTAIRE")

    # --- J12 : proverbe #2 ---
    t_proverbe("J12_proverbe2.png","Quand tu ne sais pas où tu vas, regarde d'où tu viens.","Proverbe africain")

    # --- J13 : meme ---
    t_meme("J13_meme.png","Tout joueur de Défi Kilimandjaro connaît ces deux émotions :","Tu te sens le roi de la montagne. Imparable.","Les mêmes 5 lettres depuis 4 minutes. Le sommet attendra.")

    # --- J14 : compte à rebours / recap ---
    t_countdown("J14_countdown.png","J-?","Le solo arrive bientôt. Active la cloche pour être prévenu en tout premier.")

    print("\nTOTAL —", len([f for f in os.listdir(OUT) if f.endswith('.png')]), "visuels")
