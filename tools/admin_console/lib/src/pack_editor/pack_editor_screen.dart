import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kilimandjaro_admin/src/app/router.dart';
import 'package:kilimandjaro_admin/src/catalog/catalog_providers.dart';
import 'package:kilimandjaro_admin/src/pack_editor/bulk_import_dialog.dart';
import 'package:kilimandjaro_admin/src/pack_editor/pack_editor_providers.dart';
import 'package:kilimandjaro_admin/src/pack_editor/publish_dialog.dart';
import 'package:kilimandjaro_admin/src/pack_editor/tabs/devinettes_tab.dart';
import 'package:kilimandjaro_admin/src/pack_editor/tabs/metadata_tab.dart';
import 'package:kilimandjaro_admin/src/pack_editor/tabs/versions_tab.dart';

/// Éditeur d'un pack — 3 onglets fonctionnels.
///
///   - Métadonnées : catalog + meta + i18n (read-only Phase 2.4, édition 2.5)
///   - Devinettes  : DataTable filtrable
///   - Versions    : historique + bouton rollback (via CF rollbackPack)
///
/// AppBar : back vers /catalog, theme color + version chip, boutons
/// Import JSON et Publier (à câbler en Phase 2.6).
class PackEditorScreen extends ConsumerWidget {
  const PackEditorScreen({required this.packId, super.key});

  final String packId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(catalogEntryProvider(packId));
    final meta = ref.watch(packMetaProvider(packId)).valueOrNull;
    final pendingChanges = meta?.pendingChanges ?? 0;

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
              if (pendingChanges > 0) ...[
                const SizedBox(width: 8),
                Chip(
                  avatar: const Icon(Icons.fiber_manual_record,
                      size: 12, color: Colors.orange),
                  label: Text('$pendingChanges en attente'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.orange.withOpacity(0.15),
                  labelStyle: const TextStyle(color: Colors.orange),
                ),
              ],
            ],
          ),
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Import JSON'),
              onPressed: () =>
                  BulkImportDialog.show(context, packId: packId),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.publish, size: 18),
              label: const Text('Publier'),
              onPressed: () => PublishDialog.show(context, packId: packId),
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
            MetadataTab(packId: packId),
            DevinettesTab(packId: packId),
            VersionsTab(packId: packId),
          ],
        ),
      ),
    );
  }
}
