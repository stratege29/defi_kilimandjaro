# Mascotte — Le Griot

## Signature visuelle (CANON — ne jamais dévier)

- **Style** : cartoon mascot 2D, contour noir épais (~3 px), aplats vifs, ombrage minimal façon sticker mobile premium (référence : Royal Match king, Brawl Stars, WhatsApp stickers).
- **Personnage** : sage griot ouest-africain, peau brune chaude (#8B4513-ish), barbe blanche pleine, sourcils expressifs, grands yeux ronds amicaux.
- **Costume** : turban et tunique bleu cobalt **#1E5BBA** avec ombrages bleu plus foncé **#1842A0**, encolure ivoire/crème.
- **Halo** : disque solide jaune soleil **#FAB81F** légèrement décentré derrière le personnage (sticker round-frame).
- **Fond** : transparent autour du halo jaune. Le halo est **dans** l'asset, pas en code.
- **Cadrage** : 512×512 carré, personnage occupe 80–90 % du disque, head-room généreux pour les bras levés.

## Mapping des poses (fichiers à déposer ici)

| Fichier | Pose | Usage Flutter |
|---|---|---|
| `griot_idle.png` | clin d'œil + pouce levé | Carte devinette, HUD, avatar profil par défaut |
| `griot_victory.png` | poings levés en triomphe | Écran 04 Victoire |
| `griot_hint.png` | index levé + main sur cœur | Tooltip indice, bouton aide |
| `griot_point.png` | pointe du doigt | Onboarding, tutoriels, FTUE |
| `griot_welcome.png` | bras grands ouverts | Écran d'accueil après authentification |
| `griot_sad.png` | **À générer** — voir prompt B4 ci-dessous |
| `griot_summit.png` | **À générer** — voir prompt B6 ci-dessous |

## Note sur la divergence palette

Le griot porte du **bleu cobalt + halo jaune** alors que la palette de marque est verrouillée sur vert forêt + or + bois. C'est **volontaire** : la mascotte doit *trancher* sur le fond vert forêt du Hub pour devenir un point focal instantané (cf. Duo le hibou vert sur fond crème, Bing Bunny rose sur fond bleu). Dans le code, ne jamais teinter la mascotte avec `ColorFilter` — toujours `Image.asset` brut.

---

## Prompts Gemini — poses restantes (B4, B6)

### Tokens à coller en haut de session

```
MASCOT_LOCK: "Cartoon mascot 2D, thick black outline ~3px, flat vivid fills, minimal cell-shading. Same character: West-African elder griot, warm brown skin, full white beard, expressive round eyes. Cobalt blue #1E5BBA turban and robe with darker #1842A0 shadow folds, cream collar. Solid sun-yellow #FAB81F circular halo background behind the character. Square 512x512 PNG, character fills 80% of the yellow disc, transparent corners around the disc. Premium mobile sticker quality (Royal Match / WhatsApp sticker tier). NO text, NO watermark."
```

> **Méthode** : passer une des 5 poses approuvées (ex. `griot_idle.png`) en image de référence à Gemini, puis appliquer le prompt ci-dessous. Sans la référence, Gemini fait dériver le visage.

---

### B4 — Pose consolation (échec, non-punitive)

> Apply MASCOT_LOCK. Same griot character (use reference image). Pose: gentle, empathetic, slightly tilted head, soft compassionate smile (not sad — understanding), one hand on his own chest, the other open palm toward the viewer in a "courage, my friend" gesture. Eyes warm and reassuring, eyebrows slightly raised in kindness. The yellow halo background remains identical to the reference. 512x512 transparent PNG.

**Filename de sortie** : `griot_sad.png`

---

### B6 — Pose hero sommet Kilimandjaro (boss final)

> Apply MASCOT_LOCK but for this hero shot the canvas is 1024x1024 and the yellow halo is replaced by an open scene. Same griot character (use reference image), full body, profile three-quarter, planting his sculpted wooden staff like a flag at the snowy summit of Kilimanjaro at sunrise. Golden sun-yellow #FAB81F sunburst behind the summit (echoing the mascot's halo color), ivory snow #F5EAD0 underfoot, deep forest green #1A3A20 sky, gold-lit clouds below the summit. Wind blowing his cobalt blue #1E5BBA robe. Cinematic heroic mascot pose, same cartoon outline style as the other poses. 1024x1024 transparent corners (sky stays opaque).

**Filename de sortie** : `griot_summit.png`
