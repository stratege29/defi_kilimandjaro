# DA « Bois & Or » — médaillons, trophée, bouton primaire

Remplacement (2026-09-19) des six PNG livrés sur fond vert chroma non détouré.
Générés avec Higgsfield / GPT Image 2, `--background transparent`, 1k, quality high
(3,5 crédits l'unité, 21 crédits au total).

## Audit d'origine

Détection : bordure opaque à dominante verte (H 72°-162°, S > 35 %) sur les 70 PNG
de `assets/`. Cinq fichiers en fond vert plat + un bouton avec coins chroma (1,254,2) :

| Fichier | Défaut | Affichage |
|---|---|---|
| `badges/oreille_du_village.png` | fond vert plat 512² | profil : chip 18 px + liste 50 px |
| `badges/gardien_de_la_parole.png` | idem | idem |
| `badges/griot_du_feu.png` | idem | idem |
| `badges/ancetre_vivant.png` | idem | idem |
| `duel/trophy_elo.png` | fond vert plat 384² | `duel_result_view` 80 px (victoire) |
| `buttons/button_primary.png` | coins vert chroma | non référencé dans `lib/` (constante seule) |

Hors périmètre mais même famille de défaut : `mountains/hero_ke_mount_kenya.png` a un fond
**noir** opaque (les six autres heros sont détourés).

## Direction artistique

Prolonge les assets existants (`icons/coin`, `hint_kola`, `nav_profile`, `shop/coins_*`) :
icône de jeu casual peinte, relief 3D doux, lumière chaude de bord, aucun contour noir,
objet isolé sur alpha. Palette = `app_colors.dart` : or soleil `#E9B949`, or chaud
`#C18A2A`, bois `#C68A42`, bois foncé `#5E3D1A`, ivoire ; vert clair `#4A9E58` réservé
au bouton (maquette p.2 « Bouton principal — fond vert clair »).

Les quatre titres honorifiques racontent une **progression de matière** autour d'un masque
sculpté (cf. `honorific_title.dart`, badges K1-K4) :

| Palier | Masque | Anneau | Marqueur |
|---|---|---|---|
| Oreille du Village | Baoulé bois clair | bois poli fin | Sankofa or, bas |
| Gardien de la Parole | Dan noyer sombre | bronze gravé adinkra | Gye Nyame bronze |
| Griot du Feu | Sénoufo Kpeliye acajou, front à la feuille d'or | or gravé | halo de flamme |
| Ancêtre Vivant | Akan tout or | or filigrané | plumes ivoire, éclats |

Trophée : bouclier bois rond, rivets or, nœud Nyansapo or, palmes en bas.
Bouton : pilule verte glossy, liseré or à motif adinkra discret.

## Post-traitement (reproductible)

1. Crop sur la bbox alpha (> 8), mise au carré, objet à 92 % du canevas, 512×512 (Lanczos).
   Bouton : bbox + 3 % de marge, largeur 720 → 720×246.
2. `pngquant --quality 70-100 --speed 1 --strip` (poids ÷ 3, palette + alpha, OK Flutter).

## Prompts (anglais, suffixe de style commun)

Suffixe : *Mobile casual-game UI icon, hand-painted 3D-look illustration in the style of
premium match-3 game assets. Warm palette: polished gold #E9B949, antique gold #C18A2A,
carved wood #C68A42 with dark walnut #5E3D1A shadows, ivory highlights. Soft warm rim
lighting, subtle glossy specular, crisp painterly edges, no outline strokes. Centered single
object, generous margins, isolated on a fully TRANSPARENT background, nothing behind the
object, no floor, no shadow on ground, no text, no watermark.*

- **Oreille du Village** — Achievement badge 'Ear of the Village' (tier 1 of 4): a carved
  light-wood West African Baoulé mask with serene closed eyes and fine scarification lines,
  centered inside a thin round ring of light polished wood with a small gold adinkra bird
  symbol (Sankofa) at the bottom of the ring. Simple, humble, natural wood tones, small gold
  accents only.
- **Gardien de la Parole** — Achievement badge 'Keeper of the Word' (tier 2 of 4): a carved
  dark-walnut West African Dan mask with a smooth oval face, calm closed eyes and a high
  forehead, framed by a round ring of aged bronze engraved with small adinkra symbols; a
  small bronze Gye Nyame adinkra symbol sits at the bottom of the ring.
- **Griot du Feu** — Achievement badge 'Griot of Fire' (tier 3 of 4): a carved dark-mahogany
  West African Senufo Kpeliye mask with a gold-leaf forehead, surrounded by a round ring of
  polished gold engraved with adinkra symbols, with a small stylized gold-and-orange flame
  halo rising softly behind the top of the mask.
- **Ancêtre Vivant** — Achievement badge 'Living Ancestor' (tier 4 of 4, the highest): a
  fully golden carved Akan royal mask with serene closed eyes, crowned with two small
  white-and-gold feathers, inside a round ring of polished gold woven with a fine gold
  filigree lattice and adinkra symbols, with a soft radiant gold glow and a few tiny sparkles.
- **Trophée ELO** — Victory trophy emblem for a 1v1 duel result screen: a round carved wooden
  shield medallion with a ring of small gold rivets around the rim and a large polished gold
  Akan adinkra knot symbol (Nyansapo, wisdom knot) embossed in the center, with a small pair
  of gold laurel-like palm fronds at the bottom.
- **Bouton primaire** (`--aspect_ratio 21:9`) — Wide rounded pill-shaped game button
  background, empty (no label): fresh green #4A9E58 with a lighter green top highlight and a
  darker green #2E7A44 bottom edge, thin polished gold #E9B949 border with a very subtle
  carved adinkra pattern along the edge, soft glossy 3D relief, fully transparent outside.

### Lot 2 — écrans de résultat (2026-09-19, 14 crédits)

Remplacent des icônes Material (`Icons.terrain`, `handshake`, `star_rounded`,
`emoji_events`, `workspace_premium`) dans `duel_result_view` et `victory_view`.
Marques de manches et icônes de CTA (18-20 px) restent en Material, volontairement.

- **Défaite duel** `duel/defeat_emblem.png` 512² — Defeat emblem for a 1v1 duel result
  screen, companion piece to a victory trophy: the same round carved wooden shield medallion
  with a ring of small rivets around the rim, but cracked with a deep diagonal split across
  the wood, the central Akan adinkra knot symbol (Nyansapo) tarnished and dull, the rivets
  darkened; muted laterite red-brown #B04A30 and dark walnut tones, no bright gold shine, a
  few small wood splinters at the crack. Somber but dignified, not cartoonish.
- **Match nul** `duel/draw_emblem.png` 512² — Draw / tie emblem for a 1v1 duel result
  screen, companion piece to a victory trophy: a round carved wooden medallion with a ring
  of small rivets, bearing two crossed traditional West African spears with wooden shafts
  and bronze tips, a single kola nut resting at the center of the cross. Balanced,
  symmetrical, calm; warm wood and soft antique gold #C18A2A, no bright glow.
- **Étoile** `icons/star_gold.png` 256² — Single five-pointed star game icon, polished gold
  #E9B949 with a soft antique-gold #C18A2A bevel and a small bright ivory specular highlight
  on the upper-left, slightly rounded points, subtle carved adinkra dots along the edges,
  faint warm glow. Reads clearly at 32 pixels. *(Étoile manquée = même image, matrice
  luminance + opacité 0,22 dans `_StarsRow`.)*
- **Couronne boss** `icons/crown_boss.png` 256² — Small ornate royal crown game icon in the
  style of an Akan gold crown: polished gold #E9B949 band with a carved adinkra pattern,
  three rounded gold points topped with tiny ivory beads, a small red-orange kola-colored gem
  at the center, soft antique-gold #C18A2A shading. Reads clearly at 36 pixels, front view,
  slightly tilted upward.

Commande type :

```bash
higgsfield generate create gpt_image_2 --prompt "<prompt> <suffixe>" \
  --aspect_ratio 1:1 --background transparent --resolution 1k --quality high --wait --json
```

Le CDN Higgsfield se télécharge via `urllib` Python (le `curl` direct est refusé en session).
