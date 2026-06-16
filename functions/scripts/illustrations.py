# -*- coding: utf-8 -*-
"""Illustrations de marque (vectoriel plat) — Défi Kilimandjaro."""
import os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 1080, 1350
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "illustrations")
os.makedirs(OUT, exist_ok=True)

GOLD=(233,185,73); CREAM=(244,236,216); NIGHT=(12,23,18); KOLA=(240,83,59)

def sky(top, bottom, horizon=0.62):
    arr = np.zeros((H, W, 3), np.float32)
    hz = int(H*horizon)
    for y in range(H):
        if y < hz:
            t = y/hz
            for i in range(3): arr[y,:,i] = top[i]*(1-t)+bottom[i]*t
        else:
            for i in range(3): arr[y,:,i] = bottom[i]
    return arr

def sun(img, cx, cy, r, col):
    d = ImageDraw.Draw(img, "RGBA")
    for k in range(6,0,-1):          # halo
        a = int(18*(k/6))
        d.ellipse([cx-r*k*0.5, cy-r*k*0.5, cx+r*k*0.5, cy+r*k*0.5], fill=(col[0],col[1],col[2],a))
    d.ellipse([cx-r,cy-r,cx+r,cy+r], fill=col)

def finish(arr):
    return Image.fromarray(np.clip(arr,0,255).astype(np.uint8)).convert("RGB")

# ---------- Abidjan skyline ----------
def abidjan():
    img = finish(sky((26,30,68),(243,150,70),0.60)); d=ImageDraw.Draw(img)
    sun(img, W*0.7, H*0.50, 70, (255,214,120))
    hz=int(H*0.60)
    # lagune
    d.rectangle([0,hz,W,H], fill=(30,52,66))
    # reflet soleil
    dd=ImageDraw.Draw(img,"RGBA")
    dd.rectangle([int(W*0.66),hz,int(W*0.74),H], fill=(255,214,120,40))
    # skyline silhouette
    sil=(14,28,30)
    bld=[(40,360,150),(150,250,120),(210,420,170),(300,300,90),(360,500,130),
         (470,330,110),(540,460,150),(640,280,120),(700,540,160),(800,360,120),
         (880,470,140),(960,300,120)]
    for x,hh,wdt in bld:
        d.rectangle([x,hz-hh,x+wdt,hz], fill=sil)
        for wy in range(hz-hh+20, hz-10, 34):       # fenêtres
            for wx in range(x+12, x+wdt-10, 26):
                if (wx+wy)%3: d.rectangle([wx,wy,wx+8,wy+12], fill=(233,185,73,180) if False else (212,160,70))
    # La Pyramide (forme triangulaire)
    d.polygon([(300,hz),(360,hz-320),(420,hz)], fill=sil)
    img.save(os.path.join(OUT,"ILL_abidjan.png")); print("abidjan")

# ---------- Baobab ----------
def baobab():
    img = finish(sky((40,26,60),(247,130,60),0.70)); d=ImageDraw.Draw(img)
    sun(img, W*0.5, H*0.52, 110, (255,196,96))
    hz=int(H*0.70); d.rectangle([0,hz,W,H], fill=(36,26,22))
    sil=(20,16,14)
    # baobab : tronc épais + couronne ramifiée
    cx=W*0.5
    d.polygon([(cx-70,hz),(cx-45,hz-360),(cx+45,hz-360),(cx+70,hz)], fill=sil)
    # branches
    for ang in (-65,-40,-15,15,40,65):
        a=math.radians(ang); x2=cx+math.sin(a)*260; y2=(hz-360)-math.cos(a)*160
        d.line([(cx,hz-340),(x2,y2)], fill=sil, width=22)
        for ang2 in (-25,0,25):
            b=math.radians(ang+ang2); x3=x2+math.sin(b)*90; y3=y2-math.cos(b)*70
            d.line([(x2,y2),(x3,y3)], fill=sil, width=12)
    # acacias lointains
    for ax in (W*0.18, W*0.82):
        d.line([(ax,hz),(ax,hz-70)],fill=sil,width=8); d.ellipse([ax-50,hz-90,ax+50,hz-66],fill=sil)
    img.save(os.path.join(OUT,"ILL_baobab.png")); print("baobab")

# ---------- Kilimandjaro ----------
def kilimandjaro():
    img = finish(sky((38,30,72),(250,170,120),0.72)); d=ImageDraw.Draw(img)
    sun(img, W*0.28, H*0.30, 60, (255,224,150))
    hz=int(H*0.72)
    # massif
    peak=(W*0.5, H*0.20)
    d.polygon([(W*0.5-560,hz),(peak[0],peak[1]),(W*0.5+560,hz)], fill=(28,40,40))
    d.polygon([(W*0.5-180,hz*0.46),(peak[0],peak[1]),(W*0.5+180,hz*0.46),(W*0.5+90,hz*0.52),(peak[0],peak[1]+40),(W*0.5-90,hz*0.52)], fill=CREAM)  # neige
    # collines
    d.rectangle([0,hz,W,H], fill=(30,42,30))
    d.polygon([(0,hz),(W*0.3,hz-90),(W*0.6,hz),(0,hz)], fill=(24,34,26))
    d.polygon([(W*0.5,hz),(W*0.8,hz-70),(W,hz),(W,hz)], fill=(24,34,26))
    # acacia premier plan
    sil=(16,22,18); ax=W*0.8
    d.line([(ax,H*0.92),(ax,H*0.78)],fill=sil,width=12); d.ellipse([ax-80,H*0.74,ax+80,H*0.80],fill=sil)
    img.save(os.path.join(OUT,"ILL_kilimandjaro.png")); print("kilimandjaro")

# ---------- Masque ----------
def masque():
    arr=np.zeros((H,W,3),np.float32); arr[:]=NIGHT
    # halo radial doré
    yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
    dd=np.sqrt(((xx-W/2)/(W*0.5))**2+((yy-H*0.45)/(H*0.5))**2)
    a=np.clip(1-dd,0,1)**2*0.22
    for i in range(3): arr[:,:,i]+= (GOLD[i]-arr[:,:,i])*a
    img=finish(arr); d=ImageDraw.Draw(img)
    cx,cy=W/2,H*0.46; bz=(198,138,66); bz2=(150,100,48)
    # visage allongé
    d.ellipse([cx-150,cy-300,cx+150,cy+300], fill=bz)
    d.ellipse([cx-150,cy-300,cx+150,cy+40], fill=bz2)  # ombre haut
    # cornes/projections
    d.polygon([(cx-150,cy-220),(cx-300,cy-360),(cx-120,cy-150)], fill=bz)
    d.polygon([(cx+150,cy-220),(cx+300,cy-360),(cx+120,cy-150)], fill=bz)
    # arête nez
    d.polygon([(cx-22,cy-120),(cx+22,cy-120),(cx+14,cy+150),(cx-14,cy+150)], fill=CREAM)
    # yeux (fentes)
    d.ellipse([cx-95,cy-60,cx-35,cy-20], fill=NIGHT)
    d.ellipse([cx+35,cy-60,cx+95,cy-20], fill=NIGHT)
    # bouche
    d.rounded_rectangle([cx-60,cy+180,cx+60,cy+230],20, fill=NIGHT)
    # scarifications
    for off in (-1,1):
        for k in range(3):
            d.line([(cx+off*(40+k*22),cy-10),(cx+off*(40+k*22),cy+150)], fill=bz2, width=4)
    img.save(os.path.join(OUT,"ILL_masque.png")); print("masque")

# ---------- Dakar (côte + Monument Renaissance) ----------
def dakar():
    img=finish(sky((28,38,82),(243,175,108),0.58)); d=ImageDraw.Draw(img)
    sun(img,W*0.52,H*0.48,80,(255,222,142)); hz=int(H*0.58)
    d.rectangle([0,hz,W,H],fill=(26,64,84)); sil=(16,30,34)
    d.polygon([(0,hz),(W*0.34,hz),(W*0.24,hz-70),(0,hz-34)],fill=sil)  # colline
    mx=W*0.18
    d.line([(mx,hz-70),(mx,hz-250)],fill=sil,width=42); d.ellipse([mx-30,hz-310,mx+30,hz-250],fill=sil)
    d.line([(mx,hz-210),(mx+95,hz-330)],fill=sil,width=22)            # bras levé
    for x,hh,wdt in [(W*0.46,190,82),(W*0.57,270,92),(W*0.69,150,82),(W*0.79,310,104),(W*0.91,210,92)]:
        d.rectangle([x,hz-hh,x+wdt,hz],fill=sil)
    img.save(os.path.join(OUT,"ILL_dakar.png")); print("dakar")

# ---------- Lagos (skyline nocturne, tons froids) ----------
def lagos():
    img=finish(sky((18,22,52),(64,86,148),0.55)); d=ImageDraw.Draw(img)
    sun(img,W*0.8,H*0.28,40,(220,230,255)); hz=int(H*0.62)
    d.rectangle([0,hz,W,H],fill=(20,40,60)); sil=(12,22,34)
    for x,hh,wdt in [(20,420,110),(120,300,90),(190,520,130),(310,360,90),(380,600,140),
                     (510,420,110),(600,540,130),(720,360,100),(810,640,150),(930,420,110)]:
        d.rectangle([x,hz-hh,x+wdt,hz],fill=sil)
        for wy in range(hz-hh+18,hz-10,30):
            for wx in range(x+10,x+wdt-8,22):
                if (wx+wy)%3: d.rectangle([wx,wy,wx+7,wy+10],fill=(170,205,150))
    img.save(os.path.join(OUT,"ILL_lagos.png")); print("lagos")

# ---------- Marrakech (ville rouge + Koutoubia) ----------
def marrakech():
    img=finish(sky((96,42,62),(243,142,80),0.60)); d=ImageDraw.Draw(img)
    sun(img,W*0.3,H*0.44,72,(255,202,122)); hz=int(H*0.60)
    d.rectangle([0,hz,W,H],fill=(150,80,55)); sil=(120,60,45); dark=(92,46,36)
    for x in range(0,W,92): d.rectangle([x,hz-52,x+80,hz],fill=dark)
    mx=W*0.62
    d.rectangle([mx,hz-430,mx+92,hz],fill=sil); d.rectangle([mx+22,hz-510,mx+70,hz-430],fill=sil)
    d.polygon([(mx+8,hz-510),(mx+46,hz-552),(mx+84,hz-510)],fill=GOLD)
    px=W*0.2; d.line([(px,hz),(px,hz-170)],fill=dark,width=14)
    for a in (-55,-22,22,55):
        ar=math.radians(a); d.line([(px,hz-170),(px+math.sin(ar)*95,hz-170-math.cos(ar)*64)],fill=dark,width=8)
    img.save(os.path.join(OUT,"ILL_marrakech.png")); print("marrakech")

# ---------- Yamoussoukro (basilique) ----------
def yamoussoukro():
    img=finish(sky((44,74,124),(206,214,186),0.62)); d=ImageDraw.Draw(img)
    sun(img,W*0.76,H*0.3,55,(255,242,196)); hz=int(H*0.62)
    d.rectangle([0,hz,W,H],fill=(62,92,56)); st=(226,221,206)
    cx=W*0.5
    for off in (-1,1):
        for k in range(5):
            x=cx+off*(150+k*72); d.rectangle([x-12,hz-160,x+12,hz],fill=st)
    d.rectangle([cx-200,hz-300,cx+200,hz-150],fill=st)
    d.pieslice([cx-200,hz-520,cx+200,hz-120],180,360,fill=st)
    d.ellipse([cx-28,hz-558,cx+28,hz-502],fill=GOLD)
    d.line([(cx,hz-558),(cx,hz-606)],fill=GOLD,width=8); d.line([(cx-18,hz-588),(cx+18,hz-588)],fill=GOLD,width=8)
    img.save(os.path.join(OUT,"ILL_yamoussoukro.png")); print("yamoussoukro")

# ---------- Balafon ----------
def balafon():
    arr=np.zeros((H,W,3),np.float32); arr[:]=NIGHT
    yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
    a=np.clip(1-np.sqrt(((xx-W/2)/(W*0.5))**2+((yy-H*0.46)/(H*0.5))**2),0,1)**2*0.22
    for i in range(3): arr[:,:,i]+=(GOLD[i]-arr[:,:,i])*a
    img=finish(arr); d=ImageDraw.Draw(img); cx,cy=W/2,H*0.46
    n=9; bw=72; gap=14; total=n*bw+(n-1)*gap; x0=cx-total/2
    for i in range(n):
        x=x0+i*(bw+gap); blen=300-i*16
        d.rounded_rectangle([x,cy-blen/2,x+bw,cy+blen/2],10,fill=(198,138,66))
        d.rounded_rectangle([x,cy-blen/2,x+bw,cy-blen/2+blen*0.42],10,fill=(216,162,90))
        d.ellipse([x+6,cy+blen/2+12,x+bw-6,cy+blen/2+78],fill=(150,100,48))
    d.line([(cx-70,cy-220),(cx-24,cy-130)],fill=CREAM,width=9); d.ellipse([cx-36,cy-142,cx-8,cy-114],fill=GOLD)
    d.line([(cx+70,cy-220),(cx+24,cy-130)],fill=CREAM,width=9); d.ellipse([cx+8,cy-142,cx+36,cy-114],fill=GOLD)
    img.save(os.path.join(OUT,"ILL_balafon.png")); print("balafon")

# ---------- Chaîne de montagnes (54 sommets) ----------
def peaks():
    img=finish(sky((34,28,66),(245,162,102),0.70)); d=ImageDraw.Draw(img)
    sun(img,W*0.5,H*0.40,70,(255,212,132)); hz=int(H*0.70)
    layers=[((20,40,40),hz-140,170,5),((30,54,48),hz-50,240,6),((40,66,54),hz+40,320,7)]
    for col,by,amp,n in layers:
        pts=[(0,H)]
        for i in range(n+1):
            px=i*W/n; py=by-(amp if i%2 else amp*0.45)
            pts.append((px,py))
        pts.append((W,H)); d.polygon(pts,fill=col)
    # neige sur le pic central avant
    cxp=W*0.5; d.polygon([(cxp-70,hz-150),(cxp,hz-320),(cxp+70,hz-150)],fill=CREAM)
    d.line([(cxp,hz-320),(cxp,hz-380)],fill=GOLD,width=7); d.polygon([(cxp,hz-380),(cxp+46,hz-366),(cxp,hz-352)],fill=KOLA)
    img.save(os.path.join(OUT,"ILL_peaks.png")); print("peaks")

# ---------- Duel (deux grimpeurs vers le sommet) ----------
def duel():
    img=finish(sky((30,30,70),(242,150,92),0.72)); d=ImageDraw.Draw(img)
    sun(img,W*0.5,H*0.27,60,(255,222,142)); hz=int(H*0.72)
    d.polygon([(W*0.5-540,H),(W*0.5,H*0.17),(W*0.5+540,H)],fill=(26,40,40))
    d.polygon([(W*0.5-120,H*0.42),(W*0.5,H*0.17),(W*0.5+120,H*0.42)],fill=CREAM)
    fx=W*0.5; d.line([(fx,H*0.17),(fx,H*0.11)],fill=GOLD,width=7); d.polygon([(fx,H*0.11),(fx+46,H*0.125),(fx,H*0.14)],fill=KOLA)
    def climber(x,y,c):
        d.ellipse([x-15,y-44,x+15,y-14],fill=c); d.line([(x,y-14),(x,y+32)],fill=c,width=13)
        d.line([(x,y+32),(x-22,y+64)],fill=c,width=9); d.line([(x,y+32),(x+22,y+64)],fill=c,width=9)
        d.line([(x,y-4),(x-28,y-24)],fill=c,width=8); d.line([(x,y-4),(x+28,y-26)],fill=c,width=8)
    climber(W*0.34,H*0.60,(232,93,158)); climber(W*0.66,H*0.64,(61,163,93))
    img.save(os.path.join(OUT,"ILL_duel.png")); print("duel")

if __name__ == "__main__":
    abidjan(); baobab(); kilimandjaro(); masque()
    dakar(); lagos(); marrakech(); yamoussoukro(); balafon(); peaks(); duel()
    print("done", len([f for f in os.listdir(OUT) if f.endswith('.png')]))
