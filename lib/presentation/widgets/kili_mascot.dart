import 'package:flutter/material.dart';

/// Poignée pour piloter [KiliMascot] depuis l'extérieur (ex: déclencher le
/// hochement quand le joueur trouve la bonne réponse).
///
/// Usage :
/// ```dart
/// final kili = KiliController();
/// // ... dans l'arbre : KiliMascot(controller: kili)
/// kili.nod(); // Kili hoche la tête
/// ```
class KiliController {
  VoidCallback? _onNod;

  /// Déclenche l'animation de hochement (« nod »), le geste signature du
  /// margouillat (« si j'avais su »). No-op si aucun [KiliMascot] n'est monté.
  void nod() => _onNod?.call();
}

/// Mascotte Kili (le margouillat) animée en **pur Flutter** — aucun runtime
/// tiers. Deux calques empilés et parfaitement calés (même canvas) :
/// - **corps** (`assets/kili/kili.png`) : statique ;
/// - **tête** (`assets/kili/kili_head.png`, découpe orange + gorge) : c'est la
///   SEULE partie qui bouge — elle pivote autour du cou.
///
/// Animations de la tête :
/// - **idle** : oscillation très légère en boucle (Kili « respire ») ;
/// - **nod** : deux hochements ressort déclenchés via [KiliController.nod] (ou
///   au tap si [tapToNod]).
class KiliMascot extends StatefulWidget {
  const KiliMascot({
    super.key,
    this.controller,
    this.size = 120,
    this.tapToNod = true,
  });

  /// Poignée externe pour déclencher le nod. Optionnelle.
  final KiliController? controller;

  /// Largeur logique du sprite (la hauteur suit le ratio de l'image).
  final double size;

  /// Si vrai, taper Kili déclenche un hochement (pratique + attachant).
  final bool tapToNod;

  @override
  State<KiliMascot> createState() => _KiliMascotState();
}

class _KiliMascotState extends State<KiliMascot>
    with TickerProviderStateMixin {
  // Ratio de `assets/kili/kili.png` (1024×757).
  static const double _aspect = 757 / 1024;

  // Pivot = base du cou (attache tête/corps), détecté sur l'image
  // (~x490,y380 sur 1024×757). En Alignment (-1..1) : quasi le centre.
  static const Alignment _neck = Alignment(-0.04, 0);

  late final AnimationController _idle;
  late final AnimationController _nod;

  /// Profil 0→1 du hochement : deux plongées ressort puis tenue.
  late final Animation<double> _nodT;

  @override
  void initState() {
    super.initState();

    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    _nod = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );

    _nodT = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 1).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 1).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
        weight: 22,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 12),
    ]).animate(_nod);

    widget.controller?._onNod = _playNod;
  }

  @override
  void didUpdateWidget(covariant KiliMascot old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._onNod == _playNod) old.controller?._onNod = null;
      widget.controller?._onNod = _playNod;
    }
  }

  void _playNod() {
    if (!mounted) return;
    _nod.forward(from: 0);
  }

  @override
  void dispose() {
    if (widget.controller?._onNod == _playNod) {
      widget.controller?._onNod = null;
    }
    _idle.dispose();
    _nod.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.size / 120;

    final child = SizedBox(
      width: widget.size,
      height: widget.size * _aspect,
      child: RepaintBoundary(
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Corps — statique.
            Image.asset('assets/kili/kili.png', fit: BoxFit.contain),
            // Tête — seule partie animée, pivote sur le cou.
            AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_idle, _nod]),
              builder: (context, head) {
                // idle : oscillation très légère.
                final breathe = Curves.easeInOut.transform(_idle.value);
                final idleRot = 0.012 * breathe;
                final idleDy = 1.2 * k * breathe;

                // nod : deux plongées (rotation snout vers le bas + petit bob).
                final nodRot = 0.07 * _nodT.value;
                final nodDy = 4 * k * _nodT.value;

                return Transform.translate(
                  offset: Offset(0, idleDy + nodDy),
                  child: Transform.rotate(
                    angle: idleRot + nodRot,
                    alignment: _neck,
                    child: head,
                  ),
                );
              },
              child: Image.asset(
                'assets/kili/kili_head.png',
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );

    if (!widget.tapToNod) return child;
    return GestureDetector(
      onTap: _playNod,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}
