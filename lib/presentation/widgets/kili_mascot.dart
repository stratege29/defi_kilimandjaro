import 'dart:async';
import 'dart:math' as math;

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' as rive;

/// Humeur de fond de Kili — pilote la boucle jouée par le rig Rive (propriété
/// `mood` du view model `Kili`, l'index de l'enum EST la valeur envoyée).
enum KiliMood {
  /// Respiration, tête qui flâne, queue en vague lente, clignements.
  idle,

  /// Petits sauts de joie, queue qui frétille, regard pétillant.
  happy,

  /// Tête basse, paupières mi-closes, queue tombante.
  sad,

  /// Tête posée, yeux fermés, grande respiration et « Zzz ».
  sleep,
}

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
  VoidCallback? _onCheer;

  /// Déclenche le hochement (« nod ») — les pompes du margouillat, son geste
  /// signature (« si j'avais su »). No-op si aucun [KiliMascot] n'est monté.
  void nod() => _onNod?.call();

  /// Déclenche le saut de victoire (anticipation, saut, réception écrasée).
  /// Sur le rendu de repli (sans Rive), retombe sur un hochement.
  void cheer() => _onCheer?.call();
}

/// Chemin du rig Rive, généré par `tools/rive/kili/gen_kili.py` + CLI Rive.
const String _kiliRiv = 'assets/kili/kili.riv';

/// Fichier Rive de Kili, chargé une seule fois et partagé par toutes les
/// instances de [KiliMascot]. `null` si le runtime natif ou le décodage
/// échoue — les widgets basculent alors sur le rig pur Flutter.
final kiliRiveFileProvider = FutureProvider<rive.File?>((ref) async {
  try {
    if (!await rive.RiveNative.init()) return null;
    final file = await rive.File.asset(
      _kiliRiv,
      riveFactory: rive.Factory.rive,
    );
    if (file != null) ref.onDispose(file.dispose);
    return file;
  } on Object catch (e) {
    debugPrint('[Kili] rig Rive indisponible, repli pur Flutter : $e');
    return null;
  }
});

/// Mascotte Kili (le margouillat).
///
/// Rendu principal : rig **Rive** (`assets/kili/kili.riv`) — maillage déformé
/// (queue en vague, poitrine qui respire), tête sur os, clignements, humeurs
/// ([mood]) et one-shots ([KiliController.nod], [KiliController.cheer]).
/// Le regard suit le doigt n'importe où à l'écran ([followFinger]) et, au
/// repos, Kili jette de temps en temps un coup d'œil de côté.
///
/// Replis, dans l'ordre :
/// - animations désactivées par le système (accessibilité) → image fixe ;
/// - Rive en cours de chargement ou indisponible → rig pur Flutter à deux
///   calques (corps statique + tête qui pivote), identique à l'ancienne
///   version.
///
/// L'emprise de mise en page reste celle du PNG (1024×757) : la marge de saut
/// du rig déborde au-dessus sans décaler le layout des écrans existants.
class KiliMascot extends ConsumerStatefulWidget {
  const KiliMascot({
    super.key,
    this.controller,
    this.size = 120,
    this.tapToNod = true,
    this.mood = KiliMood.idle,
    this.followFinger = true,
  });

  /// Poignée externe pour déclencher nod/cheer. Optionnelle.
  final KiliController? controller;

  /// Largeur logique du sprite (la hauteur suit le ratio de l'image).
  final double size;

  /// Si vrai, taper Kili déclenche un hochement (pratique + attachant).
  final bool tapToNod;

  /// Boucle de fond jouée entre deux one-shots.
  final KiliMood mood;

  /// Si vrai, les iris suivent le doigt (ou la souris) partout à l'écran.
  final bool followFinger;

  @override
  ConsumerState<KiliMascot> createState() => _KiliMascotState();
}

class _KiliMascotState extends ConsumerState<KiliMascot>
    with SingleTickerProviderStateMixin {
  // Ratio de `assets/kili/kili.png` (1024×757) : l'emprise de layout.
  static const double _aspect = 757 / 1024;

  // Artboard Rive : même largeur, 90 px de marge au-dessus (cf. TOP dans
  // gen_kili.py) pour que le saut de victoire ne soit pas coupé.
  static const double _riveTop = 90 / 1024;
  static const double _riveAspect = 847 / 1024;

  rive.RiveWidgetController? _rive;
  rive.ViewModelInstance? _vmi;
  rive.ViewModelInstanceNumber? _moodProp;
  rive.ViewModelInstanceTrigger? _nodProp;
  rive.ViewModelInstanceTrigger? _cheerProp;
  rive.ViewModelInstanceNumber? _lookXProp;
  rive.ViewModelInstanceNumber? _lookYProp;

  // --- Regard -------------------------------------------------------------
  // Milieu des deux yeux dans l'emprise 1024×757 (yeux ~x158 et ~x392, y~180).
  static const Offset _eyesAt = Offset(275 / 1024, 180 / 757);

  /// Distance (px logiques) à partir de laquelle le regard est au maximum :
  /// en deçà, l'iris ne dévie qu'en proportion — un doigt posé sur Kili ne
  /// le fait pas loucher.
  static const double _lookReach = 140;

  /// Raideur du lissage exponentiel (1/s) : ~0,1 s pour rattraper le doigt.
  static const double _lookStiffness = 14;

  late final Ticker _lookTicker;
  Offset _look = Offset.zero;
  Offset _lookTarget = Offset.zero;
  Duration _lastTick = Duration.zero;
  bool _fingerDown = false;
  bool _routeAdded = false;
  Timer? _lookTimer;
  final math.Random _rng = math.Random();

  /// Signal de hochement pour le rig de repli (incrémenté à chaque nod).
  final ValueNotifier<int> _fallbackNod = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _lookTicker = createTicker(_onLookTick);
    _attach(widget.controller);
  }

  @override
  void didUpdateWidget(covariant KiliMascot old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _detach(old.controller);
      _attach(widget.controller);
    }
    if (old.mood != widget.mood) {
      _moodProp?.value = widget.mood.index.toDouble();
    }
    if (old.followFinger != widget.followFinger) _syncPointerRoute();
  }

  /// (Dés)abonne ce widget du flux global des pointeurs : un doigt n'importe
  /// où à l'écran — pas seulement sur Kili — oriente le regard.
  void _syncPointerRoute() {
    final want = widget.followFinger && _lookXProp != null;
    if (want == _routeAdded) return;
    final router = GestureBinding.instance.pointerRouter;
    if (want) {
      router.addGlobalRoute(_onPointer);
      _scheduleGlance();
    } else {
      router.removeGlobalRoute(_onPointer);
      _lookTimer?.cancel();
    }
    _routeAdded = want;
  }

  void _onPointer(PointerEvent e) {
    if (!mounted) return;
    if (e is PointerDownEvent ||
        e is PointerMoveEvent ||
        e is PointerHoverEvent) {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final eyes = box.localToGlobal(
        Offset(box.size.width * _eyesAt.dx, box.size.height * _eyesAt.dy),
      );
      final d = e.position - eyes;
      final dist = d.distance;
      if (dist < 1) return;
      _fingerDown = e is! PointerHoverEvent;
      _lookTimer?.cancel();
      _setLookTarget(d / dist * math.min(dist / _lookReach, 1));
    } else if (e is PointerUpEvent || e is PointerCancelEvent) {
      _fingerDown = false;
      // Kili garde les yeux une fraction de seconde là où était le doigt,
      // puis revient face au joueur.
      _lookTimer?.cancel();
      _lookTimer = Timer(const Duration(milliseconds: 700), () {
        _setLookTarget(Offset.zero);
        _scheduleGlance();
      });
    }
  }

  /// Coups d'œil spontanés au repos : un regard de côté toutes les 3 à 7 s,
  /// tenu ~1 s. Rien pendant le sommeil (yeux fermés) ni sous le doigt.
  void _scheduleGlance() {
    _lookTimer?.cancel();
    _lookTimer = Timer(Duration(milliseconds: 3000 + _rng.nextInt(4000)), () {
      if (!mounted || _fingerDown) return;
      if (widget.mood != KiliMood.sleep) {
        _setLookTarget(
          Offset(_rng.nextDouble() * 1.6 - 0.8, _rng.nextDouble() * 0.9 - 0.5),
        );
      }
      _lookTimer = Timer(Duration(milliseconds: 700 + _rng.nextInt(700)), () {
        if (!mounted || _fingerDown) return;
        _setLookTarget(Offset.zero);
        _scheduleGlance();
      });
    });
  }

  void _setLookTarget(Offset t) {
    _lookTarget = Offset(t.dx.clamp(-1.0, 1.0), t.dy.clamp(-1.0, 1.0));
    if (!_lookTicker.isActive) {
      _lastTick = Duration.zero;
      unawaited(_lookTicker.start());
    }
  }

  void _onLookTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final k = 1 - math.exp(-_lookStiffness * dt);
    _look += (_lookTarget - _look) * k;
    if ((_lookTarget - _look).distance < 0.002) {
      _look = _lookTarget;
      _lookTicker.stop();
    }
    _lookXProp?.value = _look.dx;
    _lookYProp?.value = _look.dy;
  }

  void _attach(KiliController? c) {
    c?._onNod = _nod;
    c?._onCheer = _cheer;
  }

  void _detach(KiliController? c) {
    if (c?._onNod == _nod) c?._onNod = null;
    if (c?._onCheer == _cheer) c?._onCheer = null;
  }

  void _nod() {
    if (!mounted) return;
    if (_nodProp != null) {
      _nodProp!.trigger();
    } else {
      _fallbackNod.value++;
    }
  }

  void _cheer() {
    if (!mounted) return;
    if (_cheerProp != null) {
      _cheerProp!.trigger();
    } else {
      _fallbackNod.value++;
    }
  }

  /// Instancie artboard + state machine + view model pour CE widget (le
  /// fichier, lui, est partagé). Idempotent.
  rive.RiveWidgetController? _ensureRive(rive.File file) {
    if (_rive != null) return _rive;
    try {
      final c = rive.RiveWidgetController(file);
      final vmi = c.dataBind(rive.DataBind.auto());
      _rive = c;
      _vmi = vmi;
      _moodProp = vmi.number('mood')?..value = widget.mood.index.toDouble();
      _nodProp = vmi.trigger('nod');
      _cheerProp = vmi.trigger('cheer');
      _lookXProp = vmi.number('lookX');
      _lookYProp = vmi.number('lookY');
      // Pas de setState ici : on est dans build ; l'abonnement est différé.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncPointerRoute();
      });
    } on Object catch (e) {
      debugPrint('[Kili] instanciation Rive impossible : $e');
    }
    return _rive;
  }

  @override
  void dispose() {
    _detach(widget.controller);
    if (_routeAdded) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    }
    _lookTimer?.cancel();
    _lookTicker.dispose();
    _lookXProp?.dispose();
    _lookYProp?.dispose();
    _moodProp?.dispose();
    _nodProp?.dispose();
    _cheerProp?.dispose();
    _vmi?.dispose();
    _rive?.dispose();
    _fallbackNod.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size;
    final Widget content;

    if (MediaQuery.disableAnimationsOf(context)) {
      content = Image.asset(AppAssets.kiliBody, fit: BoxFit.contain);
    } else {
      final file = ref.watch(kiliRiveFileProvider).valueOrNull;
      final controller = file == null ? null : _ensureRive(file);
      content = controller == null
          ? _KiliFlutterRig(size: w, nodSignal: _fallbackNod)
          : Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: 0,
                  right: 0,
                  top: -w * _riveTop,
                  height: w * _riveAspect,
                  child: rive.RiveWidget(
                    controller: controller,
                    hitTestBehavior: rive.RiveHitTestBehavior.none,
                  ),
                ),
              ],
            );
    }

    final child = SizedBox(
      width: w,
      height: w * _aspect,
      child: RepaintBoundary(child: content),
    );

    if (!widget.tapToNod) return child;
    return GestureDetector(
      onTap: _nod,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}

/// Rig de repli en **pur Flutter** (aucun runtime tiers). Deux calques
/// empilés et parfaitement calés (même canvas) :
/// - **corps** (`assets/kili/kili.png`) : statique ;
/// - **tête** (`assets/kili/kili_head.png`) : pivote autour du cou.
///
/// idle = oscillation très légère ; nod = deux hochements ressort à chaque
/// incrément de [nodSignal].
class _KiliFlutterRig extends StatefulWidget {
  const _KiliFlutterRig({required this.size, required this.nodSignal});

  final double size;
  final ValueListenable<int> nodSignal;

  @override
  State<_KiliFlutterRig> createState() => _KiliFlutterRigState();
}

class _KiliFlutterRigState extends State<_KiliFlutterRig>
    with TickerProviderStateMixin {
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

    final dip = Tween<double>(
      begin: 0,
      end: 1,
    ).chain(CurveTween(curve: Curves.easeOut));
    final rise = Tween<double>(
      begin: 1,
      end: 0,
    ).chain(CurveTween(curve: Curves.easeInOut));
    _nodT = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: dip, weight: 22),
      TweenSequenceItem(tween: rise, weight: 22),
      TweenSequenceItem(tween: dip, weight: 22),
      TweenSequenceItem(tween: rise, weight: 22),
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 12),
    ]).animate(_nod);

    widget.nodSignal.addListener(_playNod);
  }

  @override
  void didUpdateWidget(covariant _KiliFlutterRig old) {
    super.didUpdateWidget(old);
    if (old.nodSignal != widget.nodSignal) {
      old.nodSignal.removeListener(_playNod);
      widget.nodSignal.addListener(_playNod);
    }
  }

  void _playNod() {
    if (!mounted) return;
    unawaited(_nod.forward(from: 0));
  }

  @override
  void dispose() {
    widget.nodSignal.removeListener(_playNod);
    _idle.dispose();
    _nod.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.size / 120;

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        // Corps — statique.
        Image.asset(AppAssets.kiliBody, fit: BoxFit.contain),
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
          child: Image.asset(AppAssets.kiliHead, fit: BoxFit.contain),
        ),
      ],
    );
  }
}
