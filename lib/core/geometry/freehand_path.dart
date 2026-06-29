import 'dart:ui';

/// Géométrie pure pour le bonus « À main levée ».
///
/// Détermine si le tracé brut du doigt (le `_trail` de `CircularGrid`) se
/// croise lui-même. Le trail tremble (jitter du doigt), on le **simplifie**
/// donc avant le test : un léger tremblement ne casse pas le bonus, mais une
/// vraie boucle ou un retour-en-arrière (slide-back, qui repasse sur le trait)
/// crée une auto-intersection détectée ici.
///
/// Aucune dépendance Flutter widget (juste `dart:ui` `Offset`) → testable en
/// unitaire pur.
abstract final class FreehandPath {
  FreehandPath._();

  /// Vrai si la polyligne [points] possède deux segments **non adjacents** qui
  /// se croisent (ou se touchent). Les points sont d'abord simplifiés
  /// ([simplifyTolerance] px) pour absorber le jitter. Moins de 4 points
  /// simplifiés ⇒ aucune auto-intersection géométriquement possible ⇒ `false`.
  ///
  /// Tolérance à 14px (vérifié sur device) : absorbe non seulement le
  /// tremblement fin mais aussi les petits **dépassements/corrections** très
  /// courants (le doigt dépasse une tuile de ~15-20px puis revient) — sans ces
  /// derniers, le bonus serait quasi inatteignable. Un vrai retour-en-arrière
  /// ou une boucle (segments amples qui se recroisent) reste détecté.
  static bool isSelfIntersecting(
    List<Offset> points, {
    double simplifyTolerance = 14.0,
  }) {
    final pts = _simplify(points, simplifyTolerance);
    final n = pts.length;
    if (n < 4) return false;
    // Segment [i] relie pts[i] → pts[i+1] (i ∈ [0, n-2]). On compare chaque
    // segment aux segments NON adjacents (j ≥ i+2) : les segments adjacents
    // partagent un point d'extrémité et « se touchent » légitimement.
    for (var i = 0; i < n - 1; i++) {
      for (var j = i + 2; j < n - 1; j++) {
        if (_segmentsIntersect(pts[i], pts[i + 1], pts[j], pts[j + 1])) {
          return true;
        }
      }
    }
    return false;
  }

  /// Supprime les points trop proches du précédent (< [tolerance] px). Même
  /// logique que `_GoldenPathPainter._simplify` (golden_path.dart), avec une
  /// tolérance volontairement plus haute ici pour absorber le tremblement du
  /// doigt sans pénaliser le joueur.
  static List<Offset> _simplify(List<Offset> input, double tolerance) {
    if (input.length <= 2) return input;
    final tol2 = tolerance * tolerance;
    final out = <Offset>[input.first];
    for (var i = 1; i < input.length - 1; i++) {
      final last = out.last;
      final dx = input[i].dx - last.dx;
      final dy = input[i].dy - last.dy;
      if (dx * dx + dy * dy >= tol2) out.add(input[i]);
    }
    out.add(input.last);
    return out;
  }

  /// Intersection de deux segments [p1,p2] et [p3,p4] via le signe des
  /// orientations (produits vectoriels). Le contact en un point partagé est
  /// traité comme une intersection — le trait « se touche ».
  static bool _segmentsIntersect(Offset p1, Offset p2, Offset p3, Offset p4) {
    final d1 = _cross(p4 - p3, p1 - p3);
    final d2 = _cross(p4 - p3, p2 - p3);
    final d3 = _cross(p2 - p1, p3 - p1);
    final d4 = _cross(p2 - p1, p4 - p1);

    // Cas général : extrémités de chaque segment de part et d'autre de l'autre.
    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }

    // Cas colinéaires / touchants : une extrémité posée sur l'autre segment.
    if (d1 == 0 && _onSegment(p3, p4, p1)) return true;
    if (d2 == 0 && _onSegment(p3, p4, p2)) return true;
    if (d3 == 0 && _onSegment(p1, p2, p3)) return true;
    if (d4 == 0 && _onSegment(p1, p2, p4)) return true;
    return false;
  }

  static double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

  /// Vrai si [p] (supposé colinéaire à [a]→[b]) est dans la bbox de [a,b].
  static bool _onSegment(Offset a, Offset b, Offset p) {
    return p.dx >= (a.dx < b.dx ? a.dx : b.dx) &&
        p.dx <= (a.dx > b.dx ? a.dx : b.dx) &&
        p.dy >= (a.dy < b.dy ? a.dy : b.dy) &&
        p.dy <= (a.dy > b.dy ? a.dy : b.dy);
  }
}
