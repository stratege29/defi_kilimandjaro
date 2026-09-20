import 'package:flutter/foundation.dart';

/// Bibliothèque Flutter qui émet les erreurs de chargement d'images
/// (`ImageStreamCompleter.reportError`).
const String imageResourceServiceLibrary = 'image resource service';

/// `true` si l'erreur framework doit remonter en NON-fatal dans Crashlytics.
///
/// `silent == true` : Flutter signale l'erreur pour information seulement,
/// typiquement un asset image dont le chargement échoue après disposition du
/// widget (plus aucun listener sur le stream). Idem pour tout ce qui vient du
/// service image : l'app ne plante pas, l'UI a déjà affiché son fallback.
/// Tout le reste reste fatal (comportement historique).
bool isNonFatalFlutterError(FlutterErrorDetails details) {
  return details.silent || details.library == imageResourceServiceLibrary;
}
