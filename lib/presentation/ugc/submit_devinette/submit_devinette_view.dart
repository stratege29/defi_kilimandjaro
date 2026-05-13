import 'package:defi_kilimandjaro/data/repositories/submission_repository.dart';
import 'package:defi_kilimandjaro/presentation/ugc/submit_devinette/submit_devinette_controller.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Écran de soumission d'une devinette communautaire.
///
/// Validation locale (cf. controller) puis appel à la Cloud Function
/// `submitDevinette`. UI volontairement minimale — la maquette finale
/// peut être polie ensuite par flutter-ui-expert.
class SubmitDevinetteView extends ConsumerStatefulWidget {
  const SubmitDevinetteView({super.key});

  @override
  ConsumerState<SubmitDevinetteView> createState() =>
      _SubmitDevinetteViewState();
}

class _SubmitDevinetteViewState extends ConsumerState<SubmitDevinetteView> {
  final _formKey = GlobalKey<FormState>();
  final _answerCtrl = TextEditingController();
  final _riddleCtrl = TextEditingController();
  final _explanationCtrl = TextEditingController();
  final _proverbCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  String _world = 'village_des_or';
  int _difficulty = 1;
  String _lang = 'fr';

  static const _worldOptions = <String>[
    'village_des_or',
    'foret_sacree',
    'lagune_des_saveurs',
    'monts_des_legendes',
  ];

  static const _langOptions = <String>['fr', 'en'];

  bool _langInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // context.locale relies on the EasyLocalization InheritedWidget, which is
    // only safe to read here or in build(). Seed _lang on first run so the
    // dropdown defaults to the user's active locale.
    if (!_langInitialized) {
      _lang = context.locale.languageCode;
      _langInitialized = true;
    }
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    _riddleCtrl.dispose();
    _explanationCtrl.dispose();
    _proverbCtrl.dispose();
    _tagsCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  void _onSubmit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final draft = SubmissionDraft(
      world: _world,
      country: 'ci',
      lang: _lang,
      answer: _answerCtrl.text.trim(),
      riddle: _riddleCtrl.text.trim(),
      explanation: _explanationCtrl.text.trim(),
      proverb: _proverbCtrl.text.trim(),
      difficulty: _difficulty,
      tags: _tagsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(5)
          .toList(),
      authorDisplayName: _displayNameCtrl.text.trim().isEmpty
          ? null
          : _displayNameCtrl.text.trim(),
    );
    ref.read(submitDevinetteControllerProvider.notifier).submit(draft);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(submitDevinetteControllerProvider);

    ref.listen<SubmitDevinetteState>(
      submitDevinetteControllerProvider,
      (prev, next) {
        if (next.success != null && prev?.success != next.success) {
          _formKey.currentState?.reset();
          _answerCtrl.clear();
          _riddleCtrl.clear();
          _explanationCtrl.clear();
          _proverbCtrl.clear();
          _tagsCtrl.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Devinette soumise — en attente de modération.'),
            ),
          );
        }
        if (next.errorMessage != null &&
            prev?.errorMessage != next.errorMessage) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(next.errorMessage!)),
          );
        }
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Proposer une devinette')),
      body: AbsorbPointer(
        absorbing: state.submitting,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _world,
                decoration: const InputDecoration(labelText: 'Monde'),
                items: _worldOptions
                    .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                    .toList(),
                onChanged: (v) => setState(() => _world = v ?? _world),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _lang,
                decoration: const InputDecoration(labelText: 'Langue'),
                items: _langOptions
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) => setState(() => _lang = v ?? _lang),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _answerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Réponse (3–20 caractères, sans accent)',
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) {
                  if (v == null || v.trim().length < 3) {
                    return '3 caractères minimum';
                  }
                  if (v.trim().length > 20) return '20 caractères max';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _riddleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Devinette (20–280 caractères)',
                ),
                maxLines: 3,
                validator: (v) =>
                    (v == null || v.trim().length < 20) ? '20 min' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _explanationCtrl,
                decoration: const InputDecoration(
                  labelText: 'Explication (30–500 caractères)',
                ),
                maxLines: 4,
                validator: (v) =>
                    (v == null || v.trim().length < 30) ? '30 min' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _proverbCtrl,
                decoration: const InputDecoration(
                  labelText: 'Proverbe (5–140 caractères)',
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 5) ? '5 min' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Difficulté'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 5,
                      divisions: 4,
                      value: _difficulty.toDouble(),
                      label: '$_difficulty',
                      onChanged: (v) =>
                          setState(() => _difficulty = v.round()),
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _tagsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tags (séparés par virgule, max 5)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _displayNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Pseudonyme (optionnel)',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: state.submitting ? null : _onSubmit,
                child: state.submitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Envoyer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
