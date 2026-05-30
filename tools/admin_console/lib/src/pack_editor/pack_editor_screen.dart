import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kilimandjaro_admin/src/app/router.dart';
import 'package:kilimandjaro_admin/src/catalog/catalog_providers.dart';

/// Éditeur d'un pack — squelette Phase 2.1.
///
/// Onglets prévus (à implémenter dans les phases suivantes) :
///   - 1. Métadonnées (i18n FR/EN, prix cauris, theme color, ordering)
///   - 2. Devinettes  (DataTable filtrable + édition unitaire — Phase 2.4)
///   - 3. Versions   (historique versions/{N} + bouton rollback — Phase 2.4)
class PackEditorScreen extends ConsumerWidget {
  const PackEditorScreen({required this.packId, super.key});

  final String packId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(catalogEntryProvider(packId));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(AdminRoutes.catalog),
          ),
          title: Row(
            children: [
              if (entry != null) ...[
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: entry.themeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(packId),
              const SizedBox(width: 8),
              if (entry != null)
                Chip(
                  label: Text('v${entry.currentVersion}'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Import JSON'),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bulk import — à venir Phase 2.6'),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.publish, size: 18),
              label: const Text('Publier'),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PublishDialog — à venir Phase 2.6'),
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.info_outline), text: 'Métadonnées'),
              Tab(icon: Icon(Icons.quiz_outlined), text: 'Devinettes'),
              Tab(icon: Icon(Icons.history), text: 'Versions'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MetadataPlaceholder(packId: packId),
            _DevinettesPlaceholder(packId: packId),
            _VersionsPlaceholder(packId: packId),
          ],
        ),
      ),
    );
  }
}

class _MetadataPlaceholder extends StatelessWidget {
  const _MetadataPlaceholder({required this.packId});
  final String packId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction, size: 60),
          const SizedBox(height: 12),
          Text('Métadonnées de $packId'),
          const SizedBox(height: 8),
          const Text(
            'i18n FR/EN, prix cauris, theme color, ordering\n'
            'À implémenter en Phase 2.4',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DevinettesPlaceholder extends StatelessWidget {
  const _DevinettesPlaceholder({required this.packId});
  final String packId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction, size: 60),
          const SizedBox(height: 12),
          Text('Devinettes de $packId'),
          const SizedBox(height: 8),
          const Text(
            'DataTable filtrable + édition unitaire\n'
            'À implémenter en Phase 2.4 / 2.5',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _VersionsPlaceholder extends StatelessWidget {
  const _VersionsPlaceholder({required this.packId});
  final String packId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction, size: 60),
          const SizedBox(height: 12),
          Text('Versions de $packId'),
          const SizedBox(height: 8),
          const Text(
            'Historique + rollback\n'
            'À implémenter en Phase 2.4',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
