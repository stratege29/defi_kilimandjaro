import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/src/models/devinette.dart';
import 'package:kilimandjaro_admin/src/pack_editor/devinette_form_screen.dart';
import 'package:kilimandjaro_admin/src/pack_editor/pack_editor_providers.dart';

/// Tableau filtrable des devinettes d'un pack.
///
/// Filtres :
///   - Recherche texte (matche id, answer, riddle.fr)
///   - Difficulté (1-4 ou toutes)
///   - Status (draft / published / archived / deleted)
///
/// Pagination : pas pour cette version (500 lignes Material DataTable
/// reste fluide). À ajouter avec PaginatedDataTable si on dépasse 2000.
class DevinettesTab extends ConsumerStatefulWidget {
  const DevinettesTab({required this.packId, super.key});

  final String packId;

  @override
  ConsumerState<DevinettesTab> createState() => _DevinettesTabState();
}

class _DevinettesTabState extends ConsumerState<DevinettesTab> {
  String _search = '';
  int? _difficultyFilter;
  DevinetteStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final devinettes = ref.watch(packDevinettesProvider(widget.packId));
    return devinettes.when(
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Erreur: $e')),
      data: (all) {
        final filtered = _applyFilters(all);
        return Column(
          children: [
            _FilterBar(
              total: all.length,
              shown: filtered.length,
              search: _search,
              difficulty: _difficultyFilter,
              status: _statusFilter,
              onSearch: (v) => setState(() => _search = v),
              onDifficulty: (v) => setState(() => _difficultyFilter = v),
              onStatus: (v) => setState(() => _statusFilter = v),
              onAdd: () => DevinetteFormScreen.show(
                context,
                packId: widget.packId,
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const _EmptyState()
                  : _DevinettesTable(devinettes: filtered, packId: widget.packId),
            ),
          ],
        );
      },
    );
  }

  List<Devinette> _applyFilters(List<Devinette> all) {
    return all.where((d) {
      if (_statusFilter != null && d.status != _statusFilter) return false;
      if (_difficultyFilter != null && d.difficulty != _difficultyFilter) {
        return false;
      }
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return d.id.toLowerCase().contains(q) ||
          d.answer.toLowerCase().contains(q) ||
          d.answerNormalized.contains(q) ||
          (d.riddle['fr'] ?? '').toLowerCase().contains(q);
    }).toList();
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.total,
    required this.shown,
    required this.search,
    required this.difficulty,
    required this.status,
    required this.onSearch,
    required this.onDifficulty,
    required this.onStatus,
    required this.onAdd,
  });

  final int total;
  final int shown;
  final String search;
  final int? difficulty;
  final DevinetteStatus? status;
  final ValueChanged<String> onSearch;
  final ValueChanged<int?> onDifficulty;
  final ValueChanged<DevinetteStatus?> onStatus;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher (id, answer, riddle)…',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: onSearch,
            ),
          ),
          DropdownButton<int?>(
            value: difficulty,
            hint: const Text('Difficulté'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Toutes')),
              DropdownMenuItem(value: 1, child: Text('d1')),
              DropdownMenuItem(value: 2, child: Text('d2')),
              DropdownMenuItem(value: 3, child: Text('d3')),
              DropdownMenuItem(value: 4, child: Text('d4')),
            ],
            onChanged: onDifficulty,
          ),
          DropdownButton<DevinetteStatus?>(
            value: status,
            hint: const Text('Statut'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Tous')),
              ...DevinetteStatus.values.map(
                (s) => DropdownMenuItem(value: s, child: Text(s.name)),
              ),
            ],
            onChanged: onStatus,
          ),
          const Spacer(),
          Text(
            '$shown / $total',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nouvelle devinette'),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _DevinettesTable extends StatelessWidget {
  const _DevinettesTable({required this.devinettes, required this.packId});

  final List<Devinette> devinettes;
  final String packId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              showCheckboxColumn: false,
              columns: const [
                DataColumn(label: Text('ID')),
                DataColumn(label: Text('Answer')),
                DataColumn(label: Text('Difficulty'), numeric: true),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Riddle (fr)')),
                DataColumn(label: Text('Tags')),
                DataColumn(label: Text('')),
              ],
              rows: devinettes.map((d) {
                return DataRow(
                  onSelectChanged: (_) => DevinetteFormScreen.show(
                    context,
                    packId: packId,
                    deviId: d.id,
                  ),
                  cells: [
                    DataCell(Text(
                      d.id,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    )),
                    DataCell(Text(
                      d.answer,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    )),
                    DataCell(_DifficultyChip(level: d.difficulty)),
                    DataCell(_StatusChip(status: d.status)),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Text(
                          d.riddle['fr'] ?? '—',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: d.tags
                              .take(4)
                              .map(
                                (t) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline
                                          .withOpacity(0.5),
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    t,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => DevinetteFormScreen.show(
                          context,
                          packId: packId,
                          deviId: d.id,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({required this.level});

  final int level;

  static const _colors = {
    1: Color(0xFF66BB6A), // vert
    2: Color(0xFFFFB74D), // orange
    3: Color(0xFFE57373), // rouge clair
    4: Color(0xFFAB47BC), // violet
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[level] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        'd$level',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final DevinetteStatus status;

  static const _colors = {
    DevinetteStatus.draft: Color(0xFF42A5F5), // bleu
    DevinetteStatus.published: Color(0xFF66BB6A), // vert
    DevinetteStatus.archived: Color(0xFFBDBDBD), // gris
    DevinetteStatus.deleted: Color(0xFFEF5350), // rouge
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[status]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.name,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_off_outlined, size: 60),
            SizedBox(height: 12),
            Text('Aucune devinette ne correspond aux filtres.'),
          ],
        ),
      ),
    );
  }
}
