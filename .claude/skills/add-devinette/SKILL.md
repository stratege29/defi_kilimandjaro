---
name: add-devinette
description: Add a new cultural Ivorian riddle (devinette) to the game content database. Validates format, checks for duplicates, generates the JSON entry in the right world file, and updates the index.
disable-model-invocation: true
---

# Add Devinette

Add a new cultural devinette to Kilimandjaro: $ARGUMENTS

## Steps

1. **Parse the input**. The user provides at minimum: word, world, riddle. Possibly: explanation, proverb, difficulty, country.

2. **Validate the answer word**:
   - Length 4-8 letters (grille circulaire constraint)
   - Uppercase letters only, no accents (FOUTOU not foutoû)
   - Check it doesn't already exist: `grep -ri '"answer": "WORD"' assets/data/devinettes/`
   - If duplicate found, abort and report

3. **Determine the target file**:
   - `village_des_or` → `assets/data/devinettes/village_des_or.json`
   - `foret_sacree` → `assets/data/devinettes/foret_sacree.json`
   - `lagune_des_saveurs` → `assets/data/devinettes/lagune_des_saveurs.json`
   - `monts_des_legendes` → `assets/data/devinettes/monts_des_legendes.json`
   - `cote_ivoire` → `assets/data/devinettes/cote_ivoire.json`

4. **Build the JSON entry** with this exact schema:
   ```json
   {
     "id": "<world>_<3-digit incrementing number>",
     "world": "<world>",
     "country": "ci",
     "answer": "WORD_UPPERCASE",
     "answer_normalized": "word_lowercase",
     "letters_pool": ["W","O","R","D"],  // EXACT letters including duplicates
     "riddle": "<text from user>",
     "explanation": "<2-4 sentences cultural explanation>",
     "proverb": "<single line proverb>",
     "image_svg": null,
     "difficulty": <1-5>,
     "estimated_time_s": <15-45>,
     "tags": ["<tag1>", "<tag2>"]
   }
   ```

5. **Insert into the file** in alphabetical order by `id`. Update the next-available number.

6. **Update `assets/data/devinettes/_index.json`** counts.

7. **Validate**: run `dart run scripts/validate_devinettes.dart <world>` if the script exists.

8. **Report**: show the inserted JSON and confirm count update.

## Constraints

- Never invent cultural facts. If the user gives only the word + world, ASK for explanation/proverb/source rather than guess.
- Never use stereotypes or folkloric clichés.
- Lettres dupliquées MUST be in `letters_pool` (e.g. FOUTOU = `["F","O","U","T","O","U"]`, not `["F","O","U","T"]`).
- If the word contains a non-A-Z character (apostrophe, dash), reject and ask the user to provide an alternative.
