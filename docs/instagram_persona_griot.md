# Personnage & voix de marque — « Tonton Kili », le griot du sommet

Mascotte récurrente de @defi_kilimandjaro. Réponse au chantier #3 du benchmark
(`docs/instagram_benchmark_2026.md`) : *un personnage > un catalogue* (cf. @quipoquiz
272 abos vs Duolingo). Aucun concurrent de la niche africaine n'a de mascotte forte
→ **terrain vacant à occuper**.

## Qui est-il
**Tonton Kili** — le vieux griot perché sur le Kilimandjaro, gardien malicieux de la
mémoire (devinettes, nouchi, culture 225, foot). C'est *le tonton du quartier* qui sait
tout, te chambre gentiment et te pousse à prouver ce que tu vaux. Pas un prof : un aîné
complice. Il incarne l'âme du jeu : « défie tes connaissances, seul ou contre un pote ».

- **Archétype** : le Sage farceur (Trickster-Mentor). Mi-griot, mi-tonton d'Abidjan.
- **Rôle éditorial** : il *lance le défi* (hook), *valide ou chambre* (réponse), *célèbre*
  la culture, *récompense* (cauris). Il est la VOIX derrière chaque rubrique.

## Personnalité (5 traits)
1. **Malicieux** — il te taquine, jamais il n'humilie.
2. **Fier de la culture** — il célèbre le 225/l'Afrique sans folkloriser.
3. **Défiant** — il provoque gentiment : « Vas-y, montre-moi ».
4. **Chaleureux** — « on est ensemble », tutoiement, complicité.
5. **Vif** — punchy, va droit au but (il connaît la valeur des 3 premières secondes).

## Voix & ton
- **Tutoiement** systématique. Phrases courtes. Rythme oral.
- **Nouchi dosé** : assez pour l'authenticité, pas trop pour rester accessible aux
  non-Abidjanais (le wedge, pas le plafond). Mots-piliers OK : *mogo, go, enjailler,
  daron·ne, on est ensemble, dêh*.
- **Provoque, ne méprise jamais.** Le défi est une invitation, pas un jugement.
- **Registre** : oral malicieux > corporate. Jamais d'emoji DESSINÉ (tofu) ; emojis OK en légende.

**Signature verbale**
- Ouverture (hook) : *« Vas-y… »*, *« Ne scrolle pas. »*, *« Montre-moi. »*
- Validation : *« Voilà un vrai mogo. »*, *« Tu connais tes classiques. »*
- Chambrage doux : *« Tu as cherché, hein ? »*, *« Ta daronne fait mieux. »*
- Sign-off récurrent : **« — Tonton Kili »** (et/ou *« On est ensemble. »*).

## Présence par surface
| Surface | Comment il apparaît |
|---|---|
| **Hooks reels (0-3s)** | Il *parle* : carte « TONTON KILI » + sa punchline défiante (couche `gen_hook.py`). |
| **Légendes** | Voix à la 1ʳᵉ pers. par moments + sign-off « — Tonton Kili ». |
| **Stories** | Il pose l'énigme du matin / chambre le soir à la réponse. |
| **Mosaïque** | Garde la signature lettres ; Tonton Kili = le « narrateur » du mot caché. |
| **Réponses commentaires** | 1ʳᵉ semaine : il répond en personnage (chaleureux, taquin) = levier croissance #1. |

## Identité visuelle
- **v1 (maintenant, drawable PIL)** : emblème = **sommet stylisé** (triangle Vert Nuit +
  liseré or) + label typographique « TONTON KILI ». Sert de « locuteur » sur les cartes hook.
- **v2 (à commander)** : illustration mascotte = vieux griot, bonnet/kente, kora ou
  bâton, assis sur un pic enneigé, regard malicieux. Palette « Vert Nuit » + or + kola.
  → brief illustrateur à part ; ne bloque pas le déploiement v1.

## Banque de hooks par rubrique (alimente `gen_hook.py`)
Voix Tonton Kili, pattern-interrupt avant le titre de rubrique :
- **Le VS** : « Ne reste pas neutre. » · « Choisis ton camp ou assume. » · « Y'a pas de match nul. »
- **Complète** : « Finis la phrase. Si tu peux. » · « Bloqué dès la 1ʳᵉ ligne ? » · « 9 sur 10 sèchent ici. »
- **Explique à ta daronne** : « Ta daronne capte rien. Et toi ? » · « Traduis-moi ça, le bilingue. » · « Vrai 225 = tu décodes. »
- **D'où ça sort ?** : « Tu dis ce mot chaque jour… » · « L'origine va te retourner. » · « Tu le diras plus jamais pareil. »
- **Gameplay / énigme** : « 3 secondes. Montre-moi. » · « Trop facile pour toi ? » · « Vrai ivoirien = tu trouves. »

## Garde-fous (ce que Tonton Kili ne fait JAMAIS)
- Pas de mépris, pas de cliché « sagesse africaine » carte postale, pas de moralisme.
- Pas de mots crus/sensibles (cf. blocklist contenu).
- Reste un AÎNÉ : pas de vannes méchantes, pas de politique, pas de religion.
- N'annonce pas la réponse sur les rubriques participation (no-reveal).

*Alternatives de nom écartées : « Le Vieux Père » (trop sévère), « Zé le griot »,
« Griot Kili ». Retenu : Tonton Kili (chaleureux + ownable + évoque le sommet).*
