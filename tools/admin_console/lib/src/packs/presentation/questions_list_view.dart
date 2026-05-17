import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kilimandjaro_admin/src/packs/data/packs_repository.dart';
import 'package:kilimandjaro_admin/src/packs/domain/question.dart';

/// Liste paginée des questions d'un pack avec filtres (difficulté + tag).
/// L'écran délègue la création / l'édition à `QuestionEditView`.
/// Liste paginée des questions d'un pack avec filtres.
class QuestionsListView extends ConsumerStatefulWidget {
  /// Construit l'écran pour les questions du pack `packId`.
  const QuestionsListView({required this.packId, super.key});

  /// Id du pack parent.
  final String packId;

  @override
  ConsumerState<QuestionsListView> createState() =>
      _QuestionsListViewState();
}

class _QuestionsListViewState extends ConsumerState<QuestionsListView> {
  int? _difficultyFilter;
  String? _tagFilter;
  String _search = '';
  static const int _pageSize = 20;
  int _page = 0;

  List<Question> _filter(List<Question> all) {
    final s = _search.toLowerCase();
    return all.where((q) {
      if (_difficultyFilter != null && q.difficulty != _difficultyFilter) {
        return false;
      }
      if (_tagFilter != null && !q.tags.contains(_tagFilter)) return false;
      if (s.isEmpty) return true;
      return q.id.toLowerCase().contains(s) ||
          q.answer.toLowerCase().contains(s) ||
          q.riddleFr.toLowerCase().contains(s);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final qs = ref.watch(questionsProvider(widget.packId));
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.go('/packs/${widget.packId}'),
                icon: const Icon(Icons.arrow_back),
              ),
              Text(
                'Questions · ${widget.packId}',
                style: theme.textTheme.headlineSmall,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => context.go(
                  '/packs/${widget.packId}/questions/_new',
                ),
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle question'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          qs.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Erreur : $e'),
            data: (all) {
              final tags = {for (final q in all) ...q.tags}.toList()..sort();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _filtersBar(tags, all.length),
                  const SizedBox(height: 16),
                  Expanded(child: _table(_filter(all))),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filtersBar(List<String> allTags, int total) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Recherche (id / réponse / énoncé)',
              isDense: true,
            ),
            onChanged: (v) => setState(() {
              _search = v;
              _page = 0;
            }),
          ),
        ),
        DropdownButton<int?>(
          value: _difficultyFilter,
          hint: const Text('Difficulté'),
          items: [
            const DropdownMenuItem<int?>(child: Text('Toutes')),
            for (final d in [1, 2, 3, 4, 5])
              DropdownMenuItem<int?>(value: d, child: Text('$d / 5')),
          ],
          onChanged: (v) => setState(() {
            _difficultyFilter = v;
            _page = 0;
          }),
        ),
        DropdownButton<String?>(
          value: _tagFilter,
          hint: const Text('Tag'),
          items: [
            const DropdownMenuItem<String?>(child: Text('Tous')),
            for (final t in allTags)
              DropdownMenuItem<String?>(value: t, child: Text(t)),
          ],
          onChanged: (v) => setState(() {
            _tagFilter = v;
            _page = 0;
          }),
        ),
        Text('total $total'),
      ],
    );
  }

  Widget _table(List<Question> filtered) {
    if (filtered.isEmpty) {
      return const Center(child: Text('Aucune question.'));
    }
    final pages = (filtered.length / _pageSize).ceil();
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, filtered.length);
    final slice = filtered.sublist(start, end);
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: slice.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final q = slice[i];
              return ListTile(
                title: Row(
                  children: [
                    SizedBox(
                      width: 200,
                      child: Text(
                        q.id,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: Text(
                        q.answer,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text('d${q.difficulty}'),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        q.riddleFr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => context.go(
                        '/packs/${widget.packId}/questions/${q.id}',
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () => _confirmDelete(q),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (pages > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _page > 0 ? () => setState(() => _page--) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Page ${_page + 1} / $pages'),
              IconButton(
                onPressed:
                    _page < pages - 1 ? () => setState(() => _page++) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _confirmDelete(Question q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la question ?'),
        content: Text('Suppression définitive de "${q.id}" (${q.answer}).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(packsRepositoryProvider)
        .deleteQuestion(widget.packId, q.id);
  }
}
