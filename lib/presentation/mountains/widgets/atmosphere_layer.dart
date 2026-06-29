import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Biome visuel d'un sommet, dérivé de son altitude.
enum AtmosphereBiome { savanne, foret, roche, altitude }

/// Retourne le biome correspondant à une altitude en mètres.
AtmosphereBiome biomeForAltitude(int altitudeM) {
  if (altitudeM < 500) return AtmosphereBiome.savanne;
  if (altitudeM < 2000) return AtmosphereBiome.foret;
  if (altitudeM < 4000) return AtmosphereBiome.roche;
  return AtmosphereBiome.altitude;
}

/// Couleur principale de la silhouette selon le biome.
///
/// **Savanne** : `boisFonce` (terre rouge sombre du Sahel) au lieu de
/// `savanneFonce` qui blend totalement avec le ciel ocre — contraste 7:1.
Color silhouetteColorForBiome(AtmosphereBiome biome) {
  switch (biome) {
    case AtmosphereBiome.savanne:
      return AppColors.boisFonce;
    case AtmosphereBiome.foret:
      return AppColors.vertForet;
    case AtmosphereBiome.roche:
      return AppColors.rocheBrume;
    case AtmosphereBiome.altitude:
      return AppColors.cielHauteur;
  }
}

/// Gradient de fond animé représentant l'atmosphère selon le biome courant.
///
/// Interpolé via [AnimatedContainer] entre les dégradés de biome.
/// Place cette couche en premier dans le Stack de l'écran Sommets.
class AtmosphereLayer extends StatelessWidget {
  const AtmosphereLayer({required this.biome, this.tint, super.key});

  final AtmosphereBiome biome;

  /// Teinte de skin du pack actif. Quand non-null, les couleurs du biome sont
  /// décalées (lerp ~30 %) vers cette couleur — on garde la logique altitude,
  /// on la colore. `null` = ambiance historique pure.
  final Color? tint;

  /// Intensité du décalage des couleurs de biome vers [tint].
  static const double _tintStrength = 0.32;

  List<Color> get _baseColors {
    switch (biome) {
      case AtmosphereBiome.savanne:
        return [AppColors.savanneOcre, AppColors.savanneFonce];
      case AtmosphereBiome.foret:
        return [AppColors.vertForet, const Color(0xFF0D2510)];
      case AtmosphereBiome.roche:
        return [AppColors.rocheBrume, AppColors.boisFonce];
      case AtmosphereBiome.altitude:
        return [AppColors.cielHauteur, AppColors.neigeBlanche];
    }
  }

  List<Color> get _colors {
    final base = _baseColors;
    final t = tint;
    if (t == null) return base;
    return base
        .map((c) => Color.lerp(c, t, _tintStrength) ?? c)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _colors,
        ),
      ),
    );
  }
}

/// Couche atmosphérique en arrière-plan — astre dominant, cirrus filiformes
/// et étoiles (en altitude). Aucun `MaskFilter.blur` (cause de crash iOS 26)
/// — les halos viennent de `RadialGradient`, parfaitement safe.
///
/// Micro-animation : twinkle des étoiles (opacité oscillante sur 5 étoiles
/// déphasées) en biome altitude uniquement. Cycle 4 s, très peu de CPU.
class ParallaxBgLayer extends StatefulWidget {
  const ParallaxBgLayer({
    required this.scrollFraction,
    required this.biome,
    super.key,
  });

  final double scrollFraction;
  final AtmosphereBiome biome;

  @override
  State<ParallaxBgLayer> createState() => _ParallaxBgLayerState();
}

class _ParallaxBgLayerState extends State<ParallaxBgLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _twinkle;

  @override
  void initState() {
    super.initState();
    _twinkle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _twinkle,
          builder: (_, __) {
            return CustomPaint(
              painter: _AtmospherePainter(
                scrollFraction: widget.scrollFraction,
                biome: widget.biome,
                twinklePhase: _twinkle.value,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  const _AtmospherePainter({
    required this.scrollFraction,
    required this.biome,
    required this.twinklePhase,
  });

  final double scrollFraction;
  final AtmosphereBiome biome;

  /// Valeur 0..1 fournie par l'`AnimationController` — pilote le twinkle
  /// des étoiles. Ignorée pour les biomes sans étoiles.
  final double twinklePhase;

  /// Décalage vertical lié au scroll du PageView (effet parallax).
  double _scrollDy(double h) => scrollFraction * h * 0.04;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final dy = _scrollDy(h);

    switch (biome) {
      case AtmosphereBiome.savanne:
        _paintAstre(
          canvas,
          cx: w * 0.80,
          cy: h * 0.20 + dy,
          innerR: w * 0.058,
          haloR: w * 0.13,
          innerColor: const Color(0xFFFCD34D),
          haloColor: const Color(0xFFF0C040),
        );
        _paintCirrus(canvas, [
          _Cirrus(cx: w * 0.28, cy: h * 0.30 + dy, rx: w * 0.21, opacity: 0.40),
          _Cirrus(cx: w * 0.65, cy: h * 0.39 + dy, rx: w * 0.16, opacity: 0.32),
          _Cirrus(cx: w * 0.20, cy: h * 0.46 + dy, rx: w * 0.11, opacity: 0.25),
        ], rgb: const Color(0xFFFEF3C7));
      case AtmosphereBiome.foret:
        _paintAstre(
          canvas,
          cx: w * 0.75,
          cy: h * 0.16 + dy,
          innerR: w * 0.038,
          haloR: w * 0.16,
          innerColor: const Color(0xB3F0C040),
          haloColor: const Color(0x33F0C040),
        );
        _paintCirrus(canvas, [
          _Cirrus(cx: w * 0.32, cy: h * 0.27 + dy, rx: w * 0.19, opacity: 0.22),
          _Cirrus(cx: w * 0.70, cy: h * 0.34 + dy, rx: w * 0.15, opacity: 0.20),
        ], rgb: const Color(0xFFE8E8F5));
      case AtmosphereBiome.roche:
        _paintAstre(
          canvas,
          cx: w * 0.78,
          cy: h * 0.14 + dy,
          innerR: w * 0.04,
          haloR: w * 0.10,
          innerColor: const Color(0xD9F5EAD0),
          haloColor: const Color(0x40F5EAD0),
        );
        _paintCirrus(canvas, [
          _Cirrus(cx: w * 0.25, cy: h * 0.24 + dy, rx: w * 0.20, opacity: 0.35),
          _Cirrus(cx: w * 0.63, cy: h * 0.30 + dy, rx: w * 0.17, opacity: 0.30),
          _Cirrus(cx: w * 0.18, cy: h * 0.37 + dy, rx: w * 0.11, opacity: 0.22),
        ], rgb: const Color(0xFFE8E8F5));
      case AtmosphereBiome.altitude:
        _paintStars(canvas, w, h, dy);
        _paintAstre(
          canvas,
          cx: w * 0.75,
          cy: h * 0.14 + dy,
          innerR: w * 0.04,
          haloR: w * 0.10,
          innerColor: const Color(0xEBF5EAD0),
          haloColor: const Color(0x40F5EAD0),
          crater: true,
        );
        _paintCirrus(canvas, [
          _Cirrus(cx: w * 0.30, cy: h * 0.34 + dy, rx: w * 0.20, opacity: 0.22),
        ], rgb: const Color(0xFFE8E8F5));
    }
  }

  /// Dessine l'astre (soleil ou lune) : un halo radial diffus + un disque
  /// intérieur net. L'option [crater] ajoute un petit point d'ombre pour
  /// signifier la lune.
  void _paintAstre(
    Canvas canvas, {
    required double cx,
    required double cy,
    required double innerR,
    required double haloR,
    required Color innerColor,
    required Color haloColor,
    bool crater = false,
  }) {
    final center = Offset(cx, cy);
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[haloColor, haloColor.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: haloR));
    canvas
      ..drawCircle(center, haloR, haloPaint)
      ..drawCircle(center, innerR, Paint()..color = innerColor);

    if (crater) {
      // Petit point d'ombre lunaire (décalé haut-gauche).
      canvas.drawCircle(
        Offset(cx - innerR * 0.3, cy - innerR * 0.25),
        innerR * 0.22,
        Paint()..color = const Color(0x66D4D4D8),
      );
    }
  }

  /// Dessine des cirrus filiformes : ellipses très plates, horizontales.
  void _paintCirrus(
    Canvas canvas,
    List<_Cirrus> cirruses, {
    required Color rgb,
  }) {
    for (final c in cirruses) {
      final paint = Paint()
        ..color = rgb.withValues(alpha: c.opacity)
        ..style = PaintingStyle.fill;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c.cx, c.cy),
          width: c.rx * 2,
          height: c.rx * 0.08, // très plat : ratio ~1:25
        ),
        paint,
      );
    }
  }

  /// Dessine 15 étoiles. 5 d'entre elles "twinkle" (opacité oscillante
  /// déphasée), les 10 autres sont statiques.
  void _paintStars(Canvas canvas, double w, double h, double dy) {
    final stars = <_Star>[
      _Star(
        cx: w * 0.11,
        cy: h * 0.06 + dy,
        r: 1.3,
        baseAlpha: 0.95,
        twinklePhase: 0,
      ),
      _Star(cx: w * 0.22, cy: h * 0.03 + dy, r: 0.9, baseAlpha: 0.85),
      _Star(
        cx: w * 0.34,
        cy: h * 0.08 + dy,
        r: 1.1,
        baseAlpha: 0.90,
        twinklePhase: 0.25,
      ),
      _Star(cx: w * 0.45, cy: h * 0.04 + dy, r: 0.8, baseAlpha: 0.80),
      _Star(cx: w * 0.57, cy: h * 0.07 + dy, r: 1, baseAlpha: 0.88),
      _Star(
        cx: w * 0.67,
        cy: h * 0.05 + dy,
        r: 1.3,
        baseAlpha: 0.95,
        twinklePhase: 0.50,
      ),
      _Star(cx: w * 0.90, cy: h * 0.03 + dy, r: 1.1, baseAlpha: 0.90),
      _Star(cx: w * 0.97, cy: h * 0.08 + dy, r: 0.9, baseAlpha: 0.85),
      _Star(
        cx: w * 0.15,
        cy: h * 0.12 + dy,
        r: 0.8,
        baseAlpha: 0.78,
        twinklePhase: 0.75,
      ),
      _Star(cx: w * 0.39, cy: h * 0.13 + dy, r: 0.7, baseAlpha: 0.75),
      _Star(
        cx: w * 0.74,
        cy: h * 0.13 + dy,
        r: 1,
        baseAlpha: 0.88,
        twinklePhase: 0.15,
      ),
      _Star(cx: w * 0.86, cy: h * 0.16 + dy, r: 0.8, baseAlpha: 0.80),
      _Star(cx: w * 0.28, cy: h * 0.18 + dy, r: 0.6, baseAlpha: 0.70),
      _Star(cx: w * 0.59, cy: h * 0.20 + dy, r: 0.7, baseAlpha: 0.72),
      _Star(cx: w * 0.52, cy: h * 0.25 + dy, r: 0.5, baseAlpha: 0.65),
    ];

    const paintColor = Color(0xFFFAFAF9);
    for (final s in stars) {
      var alpha = s.baseAlpha;
      if (s.twinklePhase != null) {
        // Opacité ∈ [baseAlpha − 0.45, baseAlpha], cycle 4 s, déphasé par étoile.
        final phased = (twinklePhase + s.twinklePhase!) % 1.0;
        final wave = 0.5 + 0.5 * math.sin(phased * 2 * math.pi);
        alpha = (s.baseAlpha - 0.45 * (1 - wave)).clamp(0.0, 1.0);
      }
      canvas.drawCircle(
        Offset(s.cx, s.cy),
        s.r,
        Paint()..color = paintColor.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_AtmospherePainter old) =>
      old.scrollFraction != scrollFraction ||
      old.biome != biome ||
      old.twinklePhase != twinklePhase;
}

class _Cirrus {
  const _Cirrus({
    required this.cx,
    required this.cy,
    required this.rx,
    required this.opacity,
  });
  final double cx;
  final double cy;
  final double rx;
  final double opacity;
}

class _Star {
  const _Star({
    required this.cx,
    required this.cy,
    required this.r,
    required this.baseAlpha,
    this.twinklePhase,
  });
  final double cx;
  final double cy;
  final double r;
  final double baseAlpha;

  /// Si non-null : déphasage de l'oscillation (0..1). Si null : statique.
  final double? twinklePhase;
}
