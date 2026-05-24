import 'dart:ui' as ui;

import 'package:defi_kilimandjaro/audio/audio_controller.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Superposition inter-rounds affichée pendant la phase [DuelPhase.roundEnd].
///
/// Affiche le score de la manche qui vient de se terminer, avec animation
/// de compteur sur le score du gagnant. Durée ~3 s (accord serveur).
/// La transition vers le [DuelPhase.countdown] suivant est serveur-driven.
///
/// **Audio** : à l'apparition de l'overlay, joue le cue procédural
/// correspondant au résultat de la manche (kora ascendant si gagnée,
/// balafon grave si perdue, accord suspendu si nulle). Une seule fois
/// par instance, fire-and-forget.
class DuelRoundEndOverlay extends ConsumerStatefulWidget {
  const DuelRoundEndOverlay({
    required this.session,
    required this.gameBackground,
    super.key,
  });

  final DuelSession session;

  /// Contenu gameplay derrière l'overlay (sera flouté).
  final Widget gameBackground;

  @override
  ConsumerState<DuelRoundEndOverlay> createState() =>
      _DuelRoundEndOverlayState();
}

class _DuelRoundEndOverlayState extends ConsumerState<DuelRoundEndOverlay> {
  @override
  void initState() {
    super.initState();
    // Cue audio joué une seule fois à l'apparition de l'overlay.
    // Décalé d'une frame pour ne pas bloquer le premier paint sur la
    // lecture (même si fire-and-forget — par prudence).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playRoundEndCue();
    });
  }

  /// Détermine le résultat de la manche courante et déclenche le cue
  /// audio correspondant via [AudioController]. Fire-and-forget.
  void _playRoundEndCue() {
    final selfUid = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
    final self = widget.session.players[selfUid];
    final opponent = widget.session.opponentOf(selfUid);
    final roundIdx = widget.session.currentRound;
    final selfRound = self?.rounds[roundIdx];
    final opponentRound = opponent?.rounds[roundIdx];

    final winnerUid = _roundWinnerUid(
      selfUid: selfUid,
      opponentUid: opponent?.uid,
      selfRound: selfRound,
      opponentRound: opponentRound,
    );

    final audio = ref.read(audioControllerProvider.notifier);
    if (winnerUid == null) {
      audio.playRoundDraw().ignore();
    } else if (winnerUid == selfUid) {
      audio.playRoundWon().ignore();
    } else {
      audio.playRoundLost().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final gameBackground = widget.gameBackground;

    final selfUid =
        ref.watch(firebaseAuthProvider).currentUser?.uid ?? '';
    final self = session.players[selfUid];
    final opponent = session.opponentOf(selfUid);

    final roundIdx = session.currentRound;

    // Résultat du round terminé (roundIdx est déjà avancé — on regarde
    // le dernier round joué, c'est-à-dire currentRound - 1 pendant roundEnd).
    // En fait le serveur reste sur le même roundIdx pendant roundEnd,
    // et l'avance après. On lit donc le round courant.
    final selfRound = self?.rounds[roundIdx];
    final opponentRound = opponent?.rounds[roundIdx];

    // Détermine le gagnant du round (null = personne n'a trouvé).
    final roundWinnerUid = _roundWinnerUid(
      selfUid: selfUid,
      opponentUid: opponent?.uid,
      selfRound: selfRound,
      opponentRound: opponentRound,
    );

    final selfWonRound = roundWinnerUid == selfUid;
    final opponentWonRound = roundWinnerUid == opponent?.uid;
    final draw = roundWinnerUid == null;

    // Score global (manches gagnées).
    final selfScore = self?.roundsWon ?? 0;
    final opponentScore = opponent?.roundsWon ?? 0;

    // Difficulté du round suivant (si encore des rounds à venir).
    final hasNextRound = roundIdx + 1 < session.totalRounds;
    final nextRound =
        hasNextRound ? session.rounds[roundIdx + 1] : null;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Fond gameplay flouté.
          _BlurredBackground(child: gameBackground),

          // Couche sombre.
          ColoredBox(color: Colors.black.withValues(alpha: 0.65)),

          // Contenu central.
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Titre de la manche.
                    _RoundEndTitle(
                      selfWon: selfWonRound,
                      opponentWon: opponentWonRound,
                      draw: draw,
                    ),
                    const SizedBox(height: 24),

                    // Score animé.
                    Semantics(
                      label:
                          'Score : Toi $selfScore - Adversaire $opponentScore',
                      child: _AnimatedScore(
                        selfScore: selfScore,
                        opponentScore: opponentScore,
                        selfWonThisRound: selfWonRound,
                        opponentWonThisRound: opponentWonRound,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Temps du round.
                    _RoundTimeRow(
                      selfRound: selfRound,
                      opponentRound: opponentRound,
                    ),

                    const SizedBox(height: 20),

                    // Prochaine manche.
                    if (nextRound != null)
                      _NextRoundHint(roundData: nextRound)
                    else
                      const _FinalRoundHint(),

                    const SizedBox(height: 12),

                    // Indicateur progression.
                    _RoundProgressDots(
                      currentRound: roundIdx,
                      totalRounds: session.totalRounds,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Renvoie l'uid du gagnant du round ou null si personne n'a trouvé.
  static String? _roundWinnerUid({
    required String selfUid,
    required String? opponentUid,
    required RoundResult? selfRound,
    required RoundResult? opponentRound,
  }) {
    final selfFound = selfRound?.found ?? false;
    final opponentFound = opponentRound?.found ?? false;

    if (!selfFound && !opponentFound) return null;
    if (selfFound && !opponentFound) return selfUid;
    if (!selfFound && opponentFound) return opponentUid;

    // Les deux ont trouvé — le plus rapide gagne.
    final selfMs = selfRound!.timeTakenMs ?? 0;
    final opponentMs = opponentRound!.timeTakenMs ?? 0;
    return selfMs <= opponentMs ? selfUid : opponentUid;
  }
}

// ---------------------------------------------------------------------------
// Sous-widgets privés
// ---------------------------------------------------------------------------

class _BlurredBackground extends StatelessWidget {
  const _BlurredBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: const ColoredBox(color: Colors.transparent),
        ),
      ],
    );
  }
}

class _RoundEndTitle extends StatelessWidget {
  const _RoundEndTitle({
    required this.selfWon,
    required this.opponentWon,
    required this.draw,
  });

  final bool selfWon;
  final bool opponentWon;
  final bool draw;

  @override
  Widget build(BuildContext context) {
    final String title;
    final Color color;

    if (draw) {
      title = 'Manche nulle';
      color = AppColors.texteSecondaire;
    } else if (selfWon) {
      title = 'Manche gagnée !';
      color = AppColors.orJour;
    } else {
      title = 'Manche perdue';
      color = AppColors.laterite;
    }

    return Column(
      children: [
        if (selfWon)
          const _GoldenPulse()
        else if (draw)
          const Icon(Icons.remove_circle_outline, size: 40, color: AppColors.texteSecondaire)
        else
          const Icon(Icons.arrow_downward, size: 40, color: AppColors.laterite),
        const SizedBox(height: 8),
        Semantics(
          label: title,
          child: Text(
            title.toUpperCase(),
            style: AppTypography.headingXl.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _GoldenPulse extends StatefulWidget {
  const _GoldenPulse();

  @override
  State<_GoldenPulse> createState() => _GoldenPulseState();
}

class _GoldenPulseState extends State<_GoldenPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Icon(
          Icons.star_rounded,
          size: 48,
          color: AppColors.orJour,
          shadows: [
            Shadow(
              color: AppColors.orJour.withValues(alpha: 0.6),
              blurRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Score animé avec compteur 0→N en 500 ms sur le côté gagnant.
class _AnimatedScore extends StatefulWidget {
  const _AnimatedScore({
    required this.selfScore,
    required this.opponentScore,
    required this.selfWonThisRound,
    required this.opponentWonThisRound,
  });

  final int selfScore;
  final int opponentScore;
  final bool selfWonThisRound;
  final bool opponentWonThisRound;

  @override
  State<_AnimatedScore> createState() => _AnimatedScoreState();
}

class _AnimatedScoreState extends State<_AnimatedScore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<int> _selfAnim;
  late final Animation<int> _opponentAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    // Le score affiché part de (total - 1) pour le gagnant, montant jusqu'à total.
    // Pour le perdant reste stable.
    _selfAnim = IntTween(
      begin: widget.selfWonThisRound
          ? (widget.selfScore - 1).clamp(0, 99)
          : widget.selfScore,
      end: widget.selfScore,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _opponentAnim = IntTween(
      begin: widget.opponentWonThisRound
          ? (widget.opponentScore - 1).clamp(0, 99)
          : widget.opponentScore,
      end: widget.opponentScore,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ScoreDigit(
              value: _selfAnim.value,
              label: 'Toi',
              highlighted: widget.selfWonThisRound,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '-',
                style: AppTypography.displayLg.copyWith(
                  color: AppColors.texteSecondaire,
                ),
              ),
            ),
            _ScoreDigit(
              value: _opponentAnim.value,
              label: 'Adv.',
              highlighted: widget.opponentWonThisRound,
            ),
          ],
        );
      },
    );
  }
}

class _ScoreDigit extends StatelessWidget {
  const _ScoreDigit({
    required this.value,
    required this.label,
    required this.highlighted,
  });

  final int value;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppColors.orJour : AppColors.textePrimaire;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: AppTypography.displayLg.copyWith(
            color: color,
            fontSize: 64,
          ),
        ),
        Text(label, style: AppTypography.labelSm.copyWith(color: color)),
      ],
    );
  }
}

class _RoundTimeRow extends StatelessWidget {
  const _RoundTimeRow({
    required this.selfRound,
    required this.opponentRound,
  });

  final RoundResult? selfRound;
  final RoundResult? opponentRound;

  String _formatMs(int? ms) {
    if (ms == null) return '--';
    return '${(ms / 1000).toStringAsFixed(1)} s';
  }

  @override
  Widget build(BuildContext context) {
    final selfTime = (selfRound?.found ?? false)
        ? _formatMs(selfRound?.timeTakenMs)
        : '--';
    final opponentTime = (opponentRound?.found ?? false)
        ? _formatMs(opponentRound?.timeTakenMs)
        : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.orJour.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _TimeCell(label: 'Toi', value: selfTime),
          Container(
            width: 1,
            height: 36,
            color: AppColors.texteSecondaire.withValues(alpha: 0.3),
          ),
          _TimeCell(label: 'Adversaire', value: opponentTime),
        ],
      ),
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: AppTypography.headingMd),
        const SizedBox(height: 2),
        Text(label, style: AppTypography.bodySm),
      ],
    );
  }
}

class _NextRoundHint extends StatelessWidget {
  const _NextRoundHint({required this.roundData});

  final RoundData roundData;

  String get _difficultyLabel => switch (roundData.difficulty) {
        'easy' => 'Facile',
        'medium' => 'Moyen',
        'hard' => 'Difficile',
        _ => roundData.difficulty,
      };

  int get _letterCount => roundData.answer.length;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Prochaine manche : $_difficultyLabel ($_letterCount lettres)',
        style: AppTypography.bodySm.copyWith(color: AppColors.textePrimaire),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _FinalRoundHint extends StatelessWidget {
  const _FinalRoundHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Derniere manche — le classement final arrive',
        style: AppTypography.bodySm.copyWith(color: AppColors.textePrimaire),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _RoundProgressDots extends StatelessWidget {
  const _RoundProgressDots({
    required this.currentRound,
    required this.totalRounds,
  });

  final int currentRound;
  final int totalRounds;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Manche ${currentRound + 1} sur $totalRounds terminée',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(totalRounds, (i) {
          final done = i <= currentRound;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: done ? 24 : 12,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: done
                    ? AppColors.orJour
                    : AppColors.texteDisabled,
              ),
            ),
          );
        }),
      ),
    );
  }
}
