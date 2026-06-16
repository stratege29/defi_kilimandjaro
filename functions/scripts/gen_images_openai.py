#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Génère les images de marque via l'API OpenAI (gpt-image-1), dans un STYLE unique
et cohérent. À LANCER SUR TA MACHINE (accès réseau + clé requis).

Prérequis :
  pip install openai
  export OPENAI_API_KEY=sk-...        # JAMAIS dans le code / le chat / git

Usage :
  python3 functions/scripts/gen_images_openai.py            # toutes les images
  python3 functions/scripts/gen_images_openai.py abidjan baobab   # une sélection

Sortie : docs/instagram_assets/ai/<nom>.png  (1024x1536, ~2:3)
Coût indicatif gpt-image-1 « high » ~0,16 $/image · « medium » ~0,06 $.
"""
import os, sys, base64

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(REPO_ROOT, "docs/instagram_assets/ai")
os.makedirs(OUT, exist_ok=True)

MODEL = os.environ.get("OPENAI_IMAGE_MODEL", "gpt-image-1")
SIZE = os.environ.get("OPENAI_IMAGE_SIZE", "1024x1536")
QUALITY = os.environ.get("OPENAI_IMAGE_QUALITY", "high")  # low | medium | high

# --- LE STYLE SIGNATURE (à ajuster si tu veux faire évoluer la patte) ---
STYLE = (
    "Modern editorial vector illustration with a subtle risograph grain and warm "
    "golden-hour light. Cohesive brand palette: deep night green (#0C1712), warm gold "
    "(#E9B949), terracotta and cream. Subtle African textile patterns (kente, adinkra) "
    "woven softly into the background. Authentic West African mood, premium, warm and "
    "optimistic. Bold simple shapes, clean composition, vertical framing with calm empty "
    "space toward the bottom. No text, no letters, no logo, no watermark, no signature."
)

# (nom de fichier, sujet)
SPECS = {
    "abidjan":     "Aerial view of Abidjan skyline and the Ébrié lagoon at golden hour, the Plateau district towers reflecting on the water",
    "dakar":       "Coastal Dakar Senegal at sunset, the African Renaissance Monument on a green hill above the ocean, distant skyline",
    "lagos":       "Lagos Nigeria skyline at dusk over the lagoon, dense modern towers with warm lit windows",
    "marrakech":   "Marrakech medina and the Koutoubia minaret at sunset, warm red city, palm trees",
    "yamoussoukro":"The Basilica of Our Lady of Peace in Yamoussoukro, its grand white dome and colonnade under a soft sky",
    "kilimandjaro":"Mount Kilimanjaro, snow-capped peak rising above the savanna at dawn, a lone acacia tree in the foreground",
    "baobab":      "A lone majestic baobab tree silhouette at sunset over the African savanna, big warm sun",
    "balafon":     "Close-up of a traditional African balafon, wooden xylophone with gourd resonators and two mallets, warm studio light",
    "masque":      "A stylized Senufo Ivorian ceremonial mask, frontal symmetrical, elegant museum lighting",
    "attieke":     "An appetizing plate of attiéké, Ivorian fermented cassava couscous, with grilled fish, tomato and onion, top-down",
    "alloco":      "An appetizing plate of alloco, Ivorian fried sweet plantains, with spicy onion sauce, top-down",
    "player":      "A joyful young West African person smiling while playing a word puzzle game on a smartphone, cozy warm lighting",
    "friends":     "A group of West African friends laughing together around a smartphone, warm celebratory mood",
    "duel":        "Two climbers racing up opposite slopes of a single snowy peak toward a flag at the summit, dynamic, sunrise",
}

def main(keys):
    try:
        from openai import OpenAI
    except ImportError:
        sys.exit("Installe le SDK : pip install openai")
    if not os.environ.get("OPENAI_API_KEY"):
        sys.exit("OPENAI_API_KEY manquant (export OPENAI_API_KEY=sk-...).")
    client = OpenAI()
    keys = keys or list(SPECS.keys())
    for k in keys:
        if k not in SPECS:
            print("inconnu:", k); continue
        prompt = f"{SPECS[k]}. {STYLE}"
        print(f"… génération {k}")
        res = client.images.generate(model=MODEL, prompt=prompt, size=SIZE, quality=QUALITY, n=1)
        data = res.data[0]
        raw = base64.b64decode(data.b64_json) if getattr(data, "b64_json", None) else None
        if raw is None:
            # fallback URL (selon modèle)
            import urllib.request
            raw = urllib.request.urlopen(data.url).read()
        path = os.path.join(OUT, f"{k}.png")
        with open(path, "wb") as f:
            f.write(raw)
        print("   ->", path)
    print(f"\nTerminé. Images dans {OUT}")
    print("Dis-le moi : j'applique le voile + texte et je les ajoute à la file.")

if __name__ == "__main__":
    main(sys.argv[1:])
