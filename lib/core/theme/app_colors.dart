import 'package:flutter/material.dart';

/// Palette officielle Kilimandjaro — **refonte "Vert Nuit" 2026**.
///
/// Direction : un canvas vert quasi-noir (OLED) qui garde l'ADN montagne/forêt
/// tout en passant en registre *premium*. L'or devient un accent **unique et
/// rare** (fini les deux ors qui se battaient), et un accent **Kola** vif
/// apporte l'énergie (duels, CTA secondaires, badges "nouveau").
///
/// ## Principe de re-skin
/// Les *noms* de tokens historiques sont conservés (donc aucun écran à
/// retoucher) mais leurs *valeurs* sont remappées vers la nouvelle identité.
/// Migrer progressivement vers les tokens sémantiques (section 2).
///
/// ## Règles d'or
/// - Toute couleur affichée DOIT venir d'ici — jamais de hex en dur.
/// - Hiérarchie de texte = 4 niveaux opaques (`textePrimaire→Disabled`),
///   jamais `withValues(alpha:)` sur du texte.
/// - Un seul or (`orSoleil` == `orJour`), un seul accent chaud (`kola`).
abstract final class AppColors {
  // ============================================================
  // SOCLE — canvas & élévation (vert nuit, tous opaques).
  // ============================================================

  /// Canvas principal — vert nuit profond quasi-noir, optimisé OLED.
  /// Fond de tous les écrans. C'est lui qui fait "claquer" l'or.
  static const Color surface = Color(0xFF0C1712);

  /// Surface +1 — sections, headers, séparateurs, fonds de bandeaux.
  static const Color surfaceVariant = Color(0xFF15241C);

  /// Surface +2 — cards élevées, dialogs, conteneurs de contenu.
  /// Vert cendre froid : la chaleur vient de la bordure/accent or posé dessus.
  static const Color surfaceContainer = Color(0xFF1E3328);

  /// Hairline opaque — bordures discrètes de cards/sections. Remplace
  /// progressivement les `orSoleil.withValues(alpha: 0.2-0.3)`.
  static const Color hairline = Color(0xFF2C4034);

  // ============================================================
  // TOKENS LEGACY — remappés vers l'identité Vert Nuit.
  // ============================================================

  /// Vert nuit — alias historique du canvas (scaffolds, headers).
  /// Désormais identique à [surface].
  static const Color vertForet = surface;

  /// Vert vif — succès, niveaux complétés, validations. Émeraude propre.
  static const Color vertClair = Color(0xFF28C76F);

  /// Or Baoulé — **l'unique or** : CTA, titres, score, monnaie, accents.
  /// Or métal chaud (pas de jaune fluo). [orJour] est un alias strict.
  static const Color orSoleil = Color(0xFFE9B949);

  /// Or profond — partenaire de dégradé de [orSoleil] (barres, bandeaux).
  static const Color orChaud = Color(0xFFC18A2A);

  /// Bronze tuile — fond des tuiles-lettres et boutons de jeu (Indice).
  /// Ambre carvé qui devient un bijou sur le canvas sombre.
  static const Color bois = Color(0xFFC68A42);

  /// Bronze foncé — ombres de tuiles, bordures, bouton Effacer.
  static const Color boisFonce = Color(0xFF5E3D1A);

  /// Crème — texte principal sur fond sombre. Alias de [textePrimaire].
  static const Color ivoire = Color(0xFFF4ECD8);

  /// Rouge — alias historique d'erreur. Pointe désormais sur [error].
  static const Color rouge = Color(0xFFE54B35);

  /// Tagline color (variante crème chaude, splash).
  static const Color tagline = Color(0xFFD9A867);

  // --- Écran Sommets : atmosphères par biome (conservées, accordées) ---

  /// Savane / plaine (0–500 m) — ocre chaud.
  static const Color savanneOcre = Color(0xFFE0AC5E);

  /// Savane sombre — bas du dégradé savanne.
  static const Color savanneFonce = Color(0xFFC89A4E);

  /// Brume / roche (2000–4000 m) — gris bleuté froid.
  static const Color rocheBrume = Color(0xFF566069);

  /// Ciel d'altitude (4000 m+) — indigo bogolan clair.
  static const Color cielHauteur = Color(0xFF6E82C8);

  /// Blanc neige — sommet enneigé et ciel d'altitude clair.
  static const Color neigeBlanche = Color(0xFFE8ECF5);

  /// Silhouette verrouillée — gris brumeux.
  static const Color silhouetteVerrouillee = Color(0xFF3C4550);

  /// Halo du sommet en cours (pulsation dorée). Alias de [orSoleil].
  static const Color haloCourant = orSoleil;

  // ============================================================
  // PALETTE 2026 — tokens sémantiques opaques (cible de migration).
  // ============================================================

  // --- Or (accent primaire, une seule teinte) ---

  /// Or Baoulé — accent principal. **Identique à [orSoleil]** : un seul or
  /// dans toute l'app.
  static const Color orJour = orSoleil;

  /// Or crépuscule — bordures actives, fin de dégradé. Bronze à cire perdue.
  static const Color orCrepuscule = Color(0xFFB07E22);

  // --- Kola (accent chaud identitaire — énergie) ---

  /// Rouge Kola — accent vif : duels, CTA secondaires, badges "nouveau",
  /// gamification, niveau récemment débloqué. C'est l'étincelle.
  static const Color kola = Color(0xFFF0533B);

  /// Latérite — alias historique, pointe sur [kola].
  static const Color laterite = kola;

  // --- Texte (échelle opaque, warm/cool maîtrisé) ---

  /// Texte primaire — corps, titres. Crème chaude, contraste ~14:1 sur
  /// [surface].
  static const Color textePrimaire = Color(0xFFF4ECD8);

  /// Texte secondaire — sous-titres, métadonnées. Sauge froide raffinée
  /// (le warm/cool primaire-crème ↔ secondaire-sauge est intentionnel).
  static const Color texteSecondaire = Color(0xFFA6AE9C);

  /// Texte tertiaire — captions, hints. **Usage ≥14pt.**
  static const Color texteTertiaire = Color(0xFF717A6C);

  /// Texte désactivé — états inactifs discrets.
  static const Color texteDisabled = Color(0xFF4C5349);

  // --- États sémantiques (vif + soft pour fonds) ---

  /// Succès vif — émeraude. Alias de [vertClair].
  static const Color success = vertClair;

  /// Succès fond doux — banners de validation, chips success.
  static const Color successSoft = Color(0xFF103024);

  /// Warning vif — ambré chaud. Timer en danger, états en attente.
  static const Color warning = Color(0xFFE5A52E);

  /// Warning fond doux.
  static const Color warningSoft = Color(0xFF2A2008);

  /// Erreur vive — rouge corail. Alias de [rouge].
  static const Color error = rouge;

  /// Erreur fond doux.
  static const Color errorSoft = Color(0xFF2E1410);

  /// Info — indigo bogolan. Tips du griot, états neutres informatifs.
  static const Color info = Color(0xFF5E83E6);

  /// Info fond doux.
  static const Color infoSoft = Color(0xFF16213B);

  // ============================================================
  // Opacités dérivées (legacy, à migrer vers [hairline]/surfaces).
  // ============================================================

  static Color cartesDebloquees = bois.withValues(alpha: 0.22);
  static Color cartesVerrouillees = bois.withValues(alpha: 0.12);
  static Color stats = bois.withValues(alpha: 0.28);
  static Color cheminDore = orSoleil.withValues(alpha: 0.70);
}
