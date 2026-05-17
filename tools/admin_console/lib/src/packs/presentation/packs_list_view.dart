import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kilimandjaro_admin/src/packs/data/packs_repository.dart';
import 'package:kilimandjaro_admin/src/packs/domain/pack.dart';
import 'package:kilimandjaro_admin/src/packs/domain/question_validators.dart';

/// Liste tous les packs (collection `content_packs`).
/// Bouton "+ Nouveau pack" → dialog → upsert vide → route vers édition.
/// Écran principal listant tous les packs de contenu.
class PacksListView extends ConsumerWidget {
  /// Constructeur const standard.
  const PacksListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(packsListProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Packs de contenu',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showCreatePackDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Nouveau pack'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: packs.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur : $e')),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(
                    child: Text(
                      'Aucun pack — lance le script de migration ou crée '
                      'le premier pack via le bouton ci-dessus.',
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) =>
                      _PackRow(pack: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreatePackDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Nouveau pack'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'pack_id',
                    helperText: 'ex: histoire_ci, contes_baoule',
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () {
                  final id = controller.text.trim();
                  final err = validatePackId(id);
                  if (err != null) {
                    setState(() => error = err);
                    return;
                  }
                  Navigator.of(ctx).pop(id);
                },
                child: const Text('Créer'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    final repo = ref.read(packsRepositoryProvider);
    final existing = await repo.getPack(result);
    if (existing != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Le pack "$result" existe déjà.')),
        );
      }
      return;
    }
    await repo.upsertPack(
      Pack(
        id: result,
        name: result,
        description: '',
        country: 'ci',
        enabled: false,
        freeChoiceEligible: false,
        priceEur: 2.99,
        priceCauris: 2000,
        currentVersion: 0,
        count: 0,
        hashSha256: '',
        sizeBytes: 0,
        storagePath: '',
        downloadUrl: '',
        lastPublishedAt: null,
      ),
    );
    if (context.mounted) context.go('/packs/$result');
  }
}

class _PackRow extends StatelessWidget {
  const _PackRow({required this.pack});
  final Pack pack;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMd().add_Hm();
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => context.go('/packs/${pack.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        pack.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(width: 12),
                      _StatusChip(enabled: pack.enabled),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pack.id,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (pack.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      pack.description,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      _MetaChip(
                        icon: Icons.tag,
                        label: 'v${pack.currentVersion}',
                      ),
                      const SizedBox(width: 8),
                      _MetaChip(
                        icon: Icons.help_outline,
                        label: '${pack.count} questions',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pack.lastPublishedAt == null
                        ? 'Jamais publié'
                        : 'Publié ${df.format(pack.lastPublishedAt!)}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.enabled});
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final color = enabled ? Colors.green : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        enabled ? 'enabled' : 'disabled',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 14),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
