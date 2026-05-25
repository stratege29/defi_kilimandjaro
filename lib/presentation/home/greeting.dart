/// Salutations ivoiriennes contextualisées par heure et par jour.
///
/// Le Hub d'Accueil affiche `{salutation} {prénom} !`. La salutation
/// tourne selon `(heure de la journée, jour de l'année)` pour donner
/// une couleur multi-langue : baoulé/akan, dioula/mandé, bété.
library;

class _Greeting {
  const _Greeting(this.text, this.language);
  final String text;
  final String language;
}

const _morning = <_Greeting>[
  _Greeting('Akwaba', 'baoulé'),
  _Greeting('I ni sɔgɔma', 'dioula'),
  _Greeting("N'douba", 'bété'),
  _Greeting('Anuanom', 'akan'),
];

const _afternoon = <_Greeting>[
  _Greeting('Akwaba', 'baoulé'),
  _Greeting('I ni wula', 'dioula'),
  _Greeting('Bonjour', 'français'),
  _Greeting('Anuanom', 'akan'),
];

const _evening = <_Greeting>[
  _Greeting('I ni su', 'dioula'),
  _Greeting('Bonsoir', 'français'),
  _Greeting('Akwaba', 'baoulé'),
];

const _night = <_Greeting>[
  _Greeting('Akwaba', 'baoulé'),
  _Greeting('Bonsoir', 'français'),
];

/// Texte de salutation pour un moment donné.
///
/// Tourne sur la liste correspondant au créneau via le jour de l'année,
/// de manière déterministe pour tous les joueurs du jour.
String greetingFor(DateTime now) {
  final hour = now.hour;
  final List<_Greeting> pool;
  if (hour >= 5 && hour < 12) {
    pool = _morning;
  } else if (hour >= 12 && hour < 18) {
    pool = _afternoon;
  } else if (hour >= 18 && hour < 22) {
    pool = _evening;
  } else {
    pool = _night;
  }
  final dayOfYear = now.difference(DateTime(now.year)).inDays;
  return pool[dayOfYear.abs() % pool.length].text;
}
