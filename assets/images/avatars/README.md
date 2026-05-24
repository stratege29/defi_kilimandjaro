# Avatars de profil — Brief designer

Catalogue fini de 24 avatars sélectionnables par le joueur dans son profil.
Référencés depuis `lib/domain/avatars/avatar_catalog.dart`.

## Specs techniques

- **Format** : SVG, fond transparent
- **Source** : 1024×1024
- **Export final** : 512×512 viewBox, scalable (les @2x / @3x sont gérés via DPR Flutter à partir d'un seul fichier)
- **Naming** : exactement `<id>.svg` — id = celui défini dans `AvatarCatalog`
- **Poids cible** : < 60 Ko / fichier (SVG-8 + dithering OK)

## Style anchor (à coller dans chaque prompt)

```
Flat vector mascot illustration, bold 3px black outline, soft cel shading,
vibrant West African palette (#C8843A terracotta, #F0C040 sunset gold,
#1A3A20 forest green, #4A70B0 indigo, #B84030 laterite red), friendly oversized
expressive eyes, single centered subject, square 1:1, transparent background
SVG, 1024x1024 source, playful kid-friendly tone, consistent line weight
across the set.
```

## Liste

| id | Catégorie | unlockMinElo | Description courte |
|---|---|---|---|
| `griot_classique` | Griot | — | Vieux griot, turban indigo, kora |
| `vieux_sage` | Griot | — | Boubou royal, barbe blanche, canne |
| `tortue_savante` | Griot | — | Tortue à lunettes, parchemin |
| `griot_moderne` | Griot | 2000 | Casque rose, lunettes, kora électrique |
| `masque_baoule_lune` | Masque | — | Kplekple lune Baoulé or & noir |
| `masque_dan` | Masque | — | Masque Dan bois sombre, fibres raphia |
| `masque_senoufo_kpelie` | Masque | 1500 | Kpélié, scarifications, antennes |
| `gbaka_conducteur` | Vie quot. | — | Chauffeur de gbaka, casquette |
| `vendeuse_attieke` | Vie quot. | — | Vendeuse attiéké, calebasse sur tête |
| `maman_bebe` | Vie quot. | — | Mère portant bébé au dos |
| `case_kawai` | Vie quot. | — | Case ronde mignonne, fumée en cœur |
| `grand_marche` | Vie quot. | — | Marchande derrière pyramide de fruits |
| `cabosse_cacao` | Aliment | — | Cabosse cacao anthropomorphe |
| `mangue_souriante` | Aliment | — | Mangue avec bras qui fait un cœur |
| `igname_dansante` | Aliment | — | Igname en train de danser |
| `piment_furieux` | Aliment | — | Piment rouge furieux, fumée aux oreilles |
| `tamtam_tete` | Instrument | — | Djembé anthropomorphe, mailloches croisées |
| `balafon_baby` | Instrument | — | Petit balafon avec notes flottantes |
| `calebasse_tete` | Instrument | — | Personnage à tête de calebasse |
| `elephant_ivoire` | Faune | — | Éléphanteau, oreilles motif kente |
| `hippo_jovial` | Faune | — | Hippo qui rit, nénuphar sur tête |
| `toucan_bavard` | Faune | — | Toucan multicolore avec bulle |
| `panthere_royale` | Faune | 3000 | Panthère noire collier rouge royal |
| `squelette_ancetre` | Wildcard | 2500 | Squelette ancestral mignon, fleurs |

## Workflow d'intégration

1. Designer livre les 24 SVG dans `assets/images/avatars/`
2. `flutter pub get` (déclaré dans `pubspec.yaml`)
3. Rien à faire côté code — le catalogue les référence déjà
4. Ajouter les traductions dans `assets/data/i18n/{fr,en}.json` sous la clé `avatar.<id>`

## Fallback en attendant les assets

Si un SVG manque, le widget `_AvatarTile` affiche un placeholder gris.
Sécurise toujours `errorBuilder` sur `Image.asset` côté Flutter.
