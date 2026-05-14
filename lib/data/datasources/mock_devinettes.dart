import 'package:defi_kilimandjaro/domain/entities/devinette.dart';

/// Mock devinette FOUTOU pour validation visuelle de l'écran de jeu (Phase 1.2).
///
/// Cf. plan.md §2 Phase 1 et devinette-curator.md pour le format complet.
const Devinette foutouDevinette = Devinette(
  id: 'village_or_001',
  world: 'village_des_or',
  country: 'ci',
  answer: 'FOUTOU',
  answerNormalized: 'foutou',
  lettersPool: ['F', 'O', 'U', 'T', 'O', 'U'],
  riddleByLang: <String, String>{
    'fr': 'Dans le mortier on me pile, on me pétrit...',
  },
  explanationByLang: <String, String>{
    'fr': 'Le foutou est une pâte pilée, plat emblématique ivoirien à base '
        "d'igname, banane plantain ou manioc.",
  },
  proverbByLang: <String, String>{
    'fr': 'Ensemble on pile mieux.',
  },
  difficulty: 1,
  estimatedTimeS: 25,
  tags: ['cuisine', 'tradition'],
);
