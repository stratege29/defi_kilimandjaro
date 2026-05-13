/**
 * Normalisation de chaînes (réplique de la convention Dart côté client).
 * Garde un mapping aligné avec `tool/migrate_devinettes_v2.dart` afin que
 * `answerNormalized` soit identique des deux côtés.
 */
const DIACRITICS: Record<string, string> = {
  à: "a", â: "a", ä: "a", á: "a", ã: "a",
  ç: "c",
  è: "e", é: "e", ê: "e", ë: "e",
  ì: "i", î: "i", ï: "i", í: "i",
  ò: "o", ô: "o", ö: "o", ó: "o", õ: "o",
  ù: "u", û: "u", ü: "u", ú: "u",
  ÿ: "y", ý: "y",
  ñ: "n",
};

export function normalize(input: string): string {
  const lower = input.toLowerCase();
  let out = "";
  for (const ch of lower) {
    out += DIACRITICS[ch] ?? ch;
  }
  return out;
}

/** Le `lettersPool` côté serveur : strict multiset des lettres de `answer`. */
export function lettersPoolFromAnswer(answer: string): string[] {
  const upper = answer.toUpperCase();
  const out: string[] = [];
  for (const ch of upper) {
    if (ch >= "A" && ch <= "Z") out.push(ch);
  }
  return out;
}
