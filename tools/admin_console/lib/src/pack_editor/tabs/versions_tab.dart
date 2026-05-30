import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kilimandjaro_admin/src/models/pack_version.dart';
import 'package:kilimandjaro_admin/src/pack_editor/pack_editor_providers.dart';
import 'package:kilimandjaro_admin/src/services/admin_functions_service.dart';

/// Historique des versions publiées + bouton rollback vers une version
/// archivée.
class VersionsTab extends ConsumerWidget {
  const VersionsTab({required this.packId, super.key});

  final String packId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(packVersionsProvider(packId));
    return versions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Erreur: $e')),
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyState();
        }
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final v = list[i];
                return _VersionTile(
                  packId: packId,
                  version: v,
                  onRollback: () =>
                      _confirmRollback(context, ref, packId, v.number),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmRollback(
    BuildContext context,
    WidgetRef ref,
    String packId,
    int toVersion,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Restaurer v$toVersion ?'),
        content: Text(
          'La version active sera archivée et v$toVersion redeviendra '
          'pointée par content_packs/$packId.\n\n'
          'Les clients verront le pack basculer au prochain sync OTA.\n'
          'Aucun .json.gz n\'est régénéré.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Rollback en cours…'),
          ],
        ),
      ),
    );

    try {
      final service = ref.read(adminFunctionsServiceProvider);
      final result =
          await service.rollbackPack(packId: packId, toVersion: toVersion);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Rollback OK : v${result.fromVersion} → v${result.toVersion} '
            '(catalog v${result.catalogVersion})',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } on AdminFunctionException catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Rollback échoué : ${e.message}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.packId,
    required this.version,
    required this.onRollback,
  });

  final String packId;
  final PackVersion version;
  final VoidCallback onRollback;

  static final _dateFormat = DateFormat('dd MMM yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final isActive = version.status == PackVersionStatus.active;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      leading: CircleAvatar(
        backgroundColor: isActive
            ? Colors.green.withOpacity(0.2)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
          'v${version.number}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.green : null,
          ),
        ),
      ),
      title: Row(
        children: [
          _StatusBadge(status: version.status),
          const SizedBox(width: 12),
          if (version.count != null)
            Text(
              '${version.count} devinettes',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(width: 12),
          if (version.sizeBytes != null)
            Text(
              _formatBytes(version.sizeBytes!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (version.publishedAt != null)
              Text(
                'Publié ${_dateFormat.format(version.publishedAt!)}'
                '${version.publishedBy != null ? ' par ${version.publishedBy}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            if (version.hashSha256 != null)
              SelectableText(
                'SHA256 ${version.hashSha256!.substring(0, 16)}…',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
      trailing: isActive
          ? Chip(
              label: const Text('Active'),
              backgroundColor: Colors.green.withOpacity(0.15),
              labelStyle: const TextStyle(color: Colors.green),
            )
          : version.status == PackVersionStatus.archived
              ? OutlinedButton.icon(
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Restaurer'),
                  onPressed: onRollback,
                )
              : null,
    );
  }

  String _formatBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final PackVersionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      PackVersionStatus.active => Colors.green,
      PackVersionStatus.archived => Colors.grey,
      PackVersionStatus.draft => Colors.blue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
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
            Icon(Icons.history_toggle_off, size: 60),
            SizedBox(height: 12),
            Text(
              'Aucune version publiée pour ce pack.\n'
              'Lance "Publier" pour créer v1.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
