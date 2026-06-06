// Miroir EXACT de functions/src/utils/normalize.ts — uniquement pour l'aperçu
// live dans le formulaire. La source de vérité reste le serveur (upsertDevinette
// recalcule answer_normalized + letters_pool ; les valeurs envoyées sont ignorées).
const DIACRITICS = {
  à: 'a', â: 'a', ä: 'a', á: 'a', ã: 'a',
  ç: 'c',
  è: 'e', é: 'e', ê: 'e', ë: 'e',
  ì: 'i', î: 'i', ï: 'i', í: 'i',
  ò: 'o', ô: 'o', ö: 'o', ó: 'o', õ: 'o',
  ù: 'u', û: 'u', ü: 'u', ú: 'u',
  ÿ: 'y', ý: 'y',
  ñ: 'n',
};

export function normalize(input) {
  const lower = (input || '').toLowerCase();
  let out = '';
  for (const ch of lower) out += DIACRITICS[ch] ?? ch;
  return out;
}

export function lettersPoolFromAnswer(answer) {
  const upper = normalize(answer).toUpperCase();
  const out = [];
  for (const ch of upper) {
    if (ch >= 'A' && ch <= 'Z') out.push(ch);
  }
  return out;
}
