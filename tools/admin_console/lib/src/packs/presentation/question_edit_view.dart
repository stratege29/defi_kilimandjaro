import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kilimandjaro_admin/src/packs/data/packs_repository.dart';
import 'package:kilimandjaro_admin/src/packs/domain/question.dart';
import 'package:kilimandjaro_admin/src/packs/domain/question_validators.dart';

/// Formulaire de création / édition d'une question.
///
/// - `questionId == "_new"` → mode création.
/// - Sinon → chargement de la question existante.
///
/// Logique critique :
///   - L'id n'est éditable QUE pendant la création (immuable après).
///   - `answer_normalized` et `letters_pool` sont auto-calculés en live à
///     partir du champ `answer` (impossibles à éditer directement).
///   - Validation côté client AVANT toute écriture Firestore.
/// Formulaire de création / édition d'une question.
class QuestionEditView extends ConsumerStatefulWidget {
  /// Construit le formulaire pour la question `questionId` du pack `packId`.
  /// `questionId == '_new'` ouvre l'éditeur en mode création.
  const QuestionEditView({
    required this.packId,
    required this.questionId,
    super.key,
  });

  /// Id du pack parent.
  final String packId;

  /// Id de la question à éditer (ou `_new` pour création).
  final String questionId;

  /// `true` si la vue est en mode création (id non encore persisté).
  bool get isCreate => questionId == '_new';

  @override
  ConsumerState<QuestionEditView> createState() =>
      _QuestionEditViewState();
}

class _QuestionEditViewState extends ConsumerState<QuestionEditView> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _country = TextEditingController(text: 'ci');
  final _answer = TextEditingController();
  final _riddle = TextEditingController();
  final _explanation = TextEditingController();
  final _tags = TextEditingController();
  int _difficulty = 3;
  bool _loaded = false;
  bool _saving = false;
  Question? _existing;
  String? _serverError;

  Future<void> _load() async {
    if (_loaded) return;
    if (widget.isCreate) {
      _id.text = '${widget.packId}_';
      _loaded = true;
      setState(() {});
      return;
    }
    final repo = ref.read(packsRepositoryProvider);
    final q = await repo.getQuestion(widget.packId, widget.questionId);
    if (q == null) {
      setState(() {
        _serverError = 'Question introuvable.';
        _loaded = true;
      });
      return;
    }
    _existing = q;
    _id.text = q.id;
    _country.text = q.country;
    _answer.text = q.answer;
    _riddle.text = q.riddleFr;
    _explanation.text = q.explanationFr;
    _tags.text = q.tags.join(', ');
    _difficulty = q.difficulty;
    setState(() => _loaded = true);
  }

  String get _canonicalAnswer => canonicalizeAnswer(_answer.text);
  String get _normalized => normalizeAnswer(_canonicalAnswer);
  List<String> get _pool => lettersPoolFromAnswer(_canonicalAnswer);

  List<String> _parseTags() {
    return _tags.text
        .split(RegExp(r'[,\s]+'))
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final canonical = _canonicalAnswer;
    final pool = _pool;
    final tags = _parseTags();
    final tagErr = validateTags(tags);
    if (tagErr != null) {
      setState(() => _serverError = tagErr);
      return;
    }
    final poolErr = validateLettersPool(canonical, pool);
    if (poolErr != null) {
      setState(() => _serverError = poolErr);
      return;
    }
    setState(() {
      _saving = true;
      _serverError = null;
    });
    try {
      final q = Question(
        id: _id.text.trim(),
        pack: widget.packId,
        country: _country.text.trim(),
        answer: canonical,
        answerNormalized: _normalized,
        lettersPool: pool,
        riddleFr: _riddle.text.trim(),
        explanationFr: _explanation.text.trim(),
        difficulty: _difficulty,
        estimatedTimeS: estimatedTimeForDifficulty(_difficulty),
        tags: tags,
        createdAt: _existing?.createdAt,
        updatedAt: _existing?.updatedAt,
      );

      // Garde-fou pour la création : refus si l'id existe déjà.
      if (widget.isCreate) {
        final existing = await ref
            .read(packsRepositoryProvider)
            .getQuestion(widget.packId, q.id);
        if (existing != null) {
          setState(() {
            _serverError = 'Cet id existe déjà — choisis un autre id.';
            _saving = false;
          });
          return;
        }
      }

      await ref
          .read(packsRepositoryProvider)
          .upsertQuestion(q, isCreate: widget.isCreate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isCreate ? 'Question créée.' : 'Question mise à jour.',
            ),
          ),
        );
        context.go('/packs/${widget.packId}/questions');
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _serverError = '$e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _id.dispose();
    _country.dispose();
    _answer.dispose();
    _riddle.dispose();
    _explanation.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _load();
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.go(
                      '/packs/${widget.packId}/questions',
                    ),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Text(
                    widget.isCreate
                        ? 'Nouvelle question'
                        : 'Édition · ${widget.questionId}',
                    style: theme.textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _id,
                readOnly: !widget.isCreate,
                decoration: InputDecoration(
                  labelText: 'id',
                  helperText: widget.isCreate
                      ? 'Format : ${widget.packId}_001 '
                          '(immuable après création).'
                      : 'Immuable.',
                ),
                validator: (v) => validateId(v, pack: widget.packId),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _answer,
                      decoration: const InputDecoration(
                        labelText: 'answer',
                        helperText:
                            '4 à 8 lettres A-Z (accents auto-strippés).',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (_) => validateAnswer(_canonicalAnswer),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _country,
                      decoration: const InputDecoration(
                        labelText: 'country',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().length != 2) {
                          return 'Code pays (2 lettres).';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AutoComputedPreview(
                canonical: _canonicalAnswer,
                normalized: _normalized,
                pool: _pool,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _riddle,
                decoration: const InputDecoration(
                  labelText: 'Énoncé (fr)',
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                validator: validateRiddleFr,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _explanation,
                decoration: const InputDecoration(
                  labelText: 'Explication (fr)',
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                validator: validateExplanationFr,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Difficulté '),
                  const SizedBox(width: 12),
                  for (final d in [1, 2, 3, 4, 5])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ChoiceChip(
                        label: Text('$d'),
                        selected: _difficulty == d,
                        onSelected: (s) {
                          if (s) setState(() => _difficulty = d);
                        },
                      ),
                    ),
                  const SizedBox(width: 16),
                  Text(
                    'estimated_time_s = '
                    '${estimatedTimeForDifficulty(_difficulty)}s',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'Tags (séparés par virgules ou espaces)',
                  helperText: 'ex: cuisine, tradition, akan',
                ),
              ),
              if (_serverError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.18),
                    border: Border.all(color: Colors.redAccent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_serverError!),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(widget.isCreate ? 'Créer' : 'Sauvegarder'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => context.go(
                              '/packs/${widget.packId}/questions',
                            ),
                    child: const Text('Annuler'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoComputedPreview extends StatelessWidget {
  const _AutoComputedPreview({
    required this.canonical,
    required this.normalized,
    required this.pool,
  });

  final String canonical;
  final String normalized;
  final List<String> pool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aperçu auto-calculé',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          _row('answer (canonique)', canonical.isEmpty ? '—' : canonical),
          _row('answer_normalized', normalized.isEmpty ? '—' : normalized),
          _row(
            'letters_pool',
            pool.isEmpty ? '—' : pool.join(' '),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 180,
              child: Text(
                k,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            Expanded(
              child: SelectableText(
                v,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      );
}
