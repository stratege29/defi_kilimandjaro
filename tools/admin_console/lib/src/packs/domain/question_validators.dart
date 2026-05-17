// Validators côté client pour préserver l'invariant des questions
// format_version=3. Cf. CLAUDE.md / contexte produit :
//
//   - answer : MAJUSCULES ASCII sans accent, longueur 4..8
//   - answer_normalized : lowercase ASCII (sans accent)
//   - letters_pool : multiset strict des lettres de answer
//   - difficulty : 1..5
//   - estimated_time_s déterministe selon difficulty
//   - tags : strings non vides
//
// Les validators ne font AUCUN I/O et sont purs — testables sans Firestore.

const Map<String, String> _diacritics = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
  'À': 'A', 'Â': 'A', 'Ä': 'A', 'Á': 'A', 'Ã': 'A',
  'ç': 'c', 'Ç': 'C',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
  'ì': 'i', 'î': 'i', 'ï': 'i', 'í': 'i',
  'Ì': 'I', 'Î': 'I', 'Ï': 'I', 'Í': 'I',
  'ò': 'o', 'ô': 'o', 'ö': 'o', 'ó': 'o', 'õ': 'o',
  'Ò': 'O', 'Ô': 'O', 'Ö': 'O', 'Ó': 'O', 'Õ': 'O',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Ú': 'U',
  'ÿ': 'y', 'ý': 'y', 'Ÿ': 'Y', 'Ý': 'Y',
  'ñ': 'n', 'Ñ': 'N',
};

/// Supprime accents/diacritiques. Conserve la casse.
String stripDiacritics(String input) {
  final buf = StringBuffer();
  for (final ch in input.split('')) {
    buf.write(_diacritics[ch] ?? ch);
  }
  return buf.toString();
}

/// Normalise une réponse pour la stocker dans `answer_normalized`.
/// Réplique strictement la convention TS `functions/src/utils/normalize.ts`.
String normalizeAnswer(String input) {
  return stripDiacritics(input.toLowerCase());
}

/// Réponse canonique : MAJUSCULES ASCII A-Z uniquement.
/// Toute lettre hors A-Z (accents préalablement strippés, ponctuation,
/// chiffres, espaces) est rejetée — la fonction supprime silencieusement
/// ces caractères afin que l'utilisateur voie la transformation et la
/// valide via `validateAnswer`.
String canonicalizeAnswer(String input) {
  final stripped = stripDiacritics(input).toUpperCase();
  final buf = StringBuffer();
  for (final ch in stripped.split('')) {
    final code = ch.codeUnitAt(0);
    if (code >= 0x41 && code <= 0x5A) buf.write(ch);
  }
  return buf.toString();
}

/// Calcule le `letters_pool` à partir d'une réponse canonique.
/// Le pool est strict (multiset, ordre préservé).
List<String> lettersPoolFromAnswer(String canonicalAnswer) {
  return canonicalAnswer.split('');
}

/// Temps estimé déterministe pour une difficulté donnée.
int estimatedTimeForDifficulty(int difficulty) {
  switch (difficulty) {
    case 1:
      return 20;
    case 2:
      return 25;
    case 3:
      return 30;
    case 4:
      return 35;
    case 5:
      return 40;
    default:
      return 30;
  }
}

/// Valide une réponse canonique. Retourne `null` si OK, sinon un message
/// d'erreur i18n-prêt (FR pour l'instant).
String? validateAnswer(String canonicalAnswer) {
  if (canonicalAnswer.isEmpty) return 'La réponse est requise.';
  if (canonicalAnswer.length < 4) {
    return 'La réponse doit faire au moins 4 lettres (actuellement '
        '${canonicalAnswer.length}).';
  }
  if (canonicalAnswer.length > 8) {
    return 'La réponse doit faire au plus 8 lettres (actuellement '
        '${canonicalAnswer.length}).';
  }
  for (final ch in canonicalAnswer.split('')) {
    final code = ch.codeUnitAt(0);
    if (code < 0x41 || code > 0x5A) {
      return 'La réponse doit être composée uniquement de lettres A-Z.';
    }
  }
  return null;
}

/// Valide la cohérence du couple `(answer, lettersPool)`.
String? validateLettersPool(String canonicalAnswer, List<String> pool) {
  if (pool.length != canonicalAnswer.length) {
    return 'letters_pool doit contenir exactement '
        '${canonicalAnswer.length} lettres (actuellement ${pool.length}).';
  }
  final expected = [...canonicalAnswer.split('')]..sort();
  final actual = [...pool]..sort();
  for (var i = 0; i < expected.length; i++) {
    if (expected[i] != actual[i]) {
      return 'letters_pool doit contenir exactement les mêmes lettres '
          'que la réponse (multiset strict).';
    }
  }
  return null;
}

/// Valide la difficulté (1..5).
String? validateDifficulty(int? difficulty) {
  if (difficulty == null) return 'La difficulté est requise.';
  if (difficulty < 1 || difficulty > 5) {
    return 'La difficulté doit être comprise entre 1 et 5.';
  }
  return null;
}

/// Valide l'énoncé `riddle.fr`. Retourne `null` si OK.
String? validateRiddleFr(String? text) {
  if (text == null || text.trim().isEmpty) {
    return "L'énoncé en français est requis.";
  }
  if (text.trim().length < 10) {
    return "L'énoncé doit faire au moins 10 caractères.";
  }
  if (text.length > 280) {
    return "L'énoncé doit faire au plus 280 caractères.";
  }
  return null;
}

/// Valide l'explication `explanation.fr`. Retourne `null` si OK.
String? validateExplanationFr(String? text) {
  if (text == null || text.trim().isEmpty) {
    return "L'explication en français est requise.";
  }
  if (text.trim().length < 20) {
    return "L'explication doit faire au moins 20 caractères.";
  }
  if (text.length > 500) {
    return "L'explication doit faire au plus 500 caractères.";
  }
  return null;
}

/// Valide un id de question. Si `pack` est fourni, l'id doit le préfixer.
String? validateId(String? id, {String? pack}) {
  if (id == null || id.trim().isEmpty) return "L'id est requis.";
  if (!RegExp(r'^[a-z0-9_]+$').hasMatch(id)) {
    return "L'id doit contenir uniquement [a-z0-9_].";
  }
  if (pack != null && pack.isNotEmpty && !id.startsWith('${pack}_')) {
    return "L'id doit commencer par \"${pack}_\".";
  }
  return null;
}

/// Valide un id de pack.
String? validatePackId(String? packId) {
  if (packId == null || packId.trim().isEmpty) {
    return "L'id du pack est requis.";
  }
  if (!RegExp(r'^[a-z][a-z0-9_]{1,40}$').hasMatch(packId)) {
    return "L'id du pack doit commencer par une lettre minuscule et "
        'contenir uniquement [a-z0-9_].';
  }
  return null;
}

/// Valide la liste de tags d'une question.
String? validateTags(List<String> tags) {
  if (tags.length > 8) return 'Maximum 8 tags par question.';
  for (final t in tags) {
    if (t.isEmpty) return 'Les tags ne peuvent pas être vides.';
    if (t.length > 24) return 'Chaque tag doit faire au plus 24 caractères.';
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(t)) {
      return 'Tags : caractères autorisés [a-z0-9_-].';
    }
  }
  return null;
}
