import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kilimandjaro_admin/src/app/router.dart';
import 'package:kilimandjaro_admin/src/catalog/catalog_providers.dart';
import 'package:kilimandjaro_admin/src/models/catalog_entry.dart';

/// Écran principal du backoffice — liste tous les packs déclarés dans
/// `catalog/index` Firestore, avec leurs métadonnées (count, version,
/// status, prix cauris).
///
/// Cliquer sur un pack ouvre `PackEditorScreen` pour éditer ses devinettes.
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogIndexProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalogue des packs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
            onPressed: () => ref.invalidate(catalogIndexProvider),
          ),
        ],
      ),
      body: catalog.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, st) => _ErrorView(error: e, onRetry: () {
          ref.invalidate(catalogIndexProvider);
        }),
        data: (entries) {
          if (entries.isEmpty) {
            return const _EmptyState();
          }
          return _CatalogTable(entries: entries);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Création de pack — à venir Phase 2.6'),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Nouveau pack'),
      ),
    );
  }
}

class _CatalogTable extends StatelessWidget {
  const _CatalogTable({required this.entries});
  final List<CatalogEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 32,
            columns: const [
              DataColumn(label: Text('Pack')),
              DataColumn(label: Text('Statut')),
              DataColumn(label: Text('Devinettes'), numeric: true),
              DataColumn(label: Text('Version'), numeric: true),
              DataColumn(label: Text('Prix (♦)'), numeric: true),
              DataColumn(label: Text('Bundle')),
              DataColumn(label: Text('Ordre'), numeric: true),
              DataColumn(label: Text('')),
            ],
            rows: entries.map((e) {
              return DataRow(
                onSelectChanged: (_) =>
                    context.go(AdminRoutes.packEditorPath(e.id)),
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: e.themeColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          e.id,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    _StatusChip(visible: e.visible),
                  ),
                  DataCell(Text('${e.count}')),
                  DataCell(Text('v${e.currentVersion}')),
                  DataCell(Text(
                    e.unlockCostCauris == 0
                        ? 'Gratuit'
                        : '${e.unlockCostCauris}',
                  )),
                  DataCell(
                    Icon(
                      e.bundled ? Icons.check : Icons.close,
                      size: 18,
                      color: e.bundled
                          ? Colors.green
                          : Theme.of(context).disabledColor,
                    ),
                  ),
                  DataCell(Text('${e.ordering}')),
                  DataCell(
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Éditer'),
                      onPressed: () =>
                          context.go(AdminRoutes.packEditorPath(e.id)),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: visible
            ? Colors.green.withOpacity(0.15)
            : Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: visible
              ? Colors.green.withOpacity(0.4)
              : Colors.grey.withOpacity(0.4),
        ),
      ),
      child: Text(
        visible ? 'Actif' : 'Masqué',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: visible ? Colors.green.shade300 : Colors.grey.shade400,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 80,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucun pack dans catalog/index',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Lancer le script tools/scripts/seed_backoffice.mjs\n'
            'pour migrer les packs existants vers Firestore.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isPermission = error is FirebaseException &&
        (error as FirebaseException).code == 'permission-denied';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPermission ? Icons.lock_outline : Icons.error_outline,
            size: 80,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            isPermission
                ? 'Accès refusé.'
                : 'Erreur de chargement.',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(
              isPermission
                  ? 'Ton compte doit avoir le claim role=admin, editor ou moderator.'
                  : error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).disabledColor),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
