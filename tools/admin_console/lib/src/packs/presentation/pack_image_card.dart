// Carte "Image du pack" affichée sur `PackEditView`. Affiche preview de
// l'image courante, déclenche le pipeline pick+optimize, propose la
// confirmation puis l'upload.
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/src/packs/domain/pack.dart';
import 'package:kilimandjaro_admin/src/packs/presentation/pack_image_controller.dart';

/// Carte UI pour l'image du pack — preview + actions.
class PackImageCard extends ConsumerWidget {
  const PackImageCard({required this.pack, super.key});

  final Pack pack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ctrl = ref.watch(packImageControllerProvider(pack.id).notifier);
    final state = ref.watch(packImageControllerProvider(pack.id));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Image du pack', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CurrentImage(pack: pack),
                const SizedBox(width: 16),
                Expanded(
                  child: _RightPanel(
                    pack: pack,
                    state: state,
                    controller: ctrl,
                  ),
                ),
              ],
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (state.lastUploadedSizeBytes != null) ...[
              const SizedBox(height: 12),
              Text(
                'Image mise à jour — '
                '${_formatBytes(state.lastUploadedSizeBytes!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.greenAccent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Image courante (Firestore) ou preview optimisée locale (in-memory).
// ---------------------------------------------------------------------------

class _CurrentImage extends ConsumerWidget {
  const _CurrentImage({required this.pack});

  final Pack pack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(packImageControllerProvider(pack.id));
    final preview = state.preview;

    // Priorité : preview locale > image distante > placeholder.
    final Widget content;
    if (preview != null) {
      content = Image.memory(
        Uint8List.fromList(preview.bytes),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (pack.imageUrl != null && pack.imageUrl!.isNotEmpty) {
      content = Image.network(
        pack.imageUrl!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const _Placeholder(),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    } else {
      content = const _Placeholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 128,
        height: 128,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: content,
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 36,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panneau de droite — actions / preview metadata
// ---------------------------------------------------------------------------

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.pack,
    required this.state,
    required this.controller,
  });

  final Pack pack;
  final PackImageState state;
  final PackImageController controller;

  @override
  Widget build(BuildContext context) {
    final hasImage = pack.imageUrl != null && pack.imageUrl!.isNotEmpty;
    final theme = Theme.of(context);

    if (state.phase == PackImagePhase.previewing && state.preview != null) {
      final p = state.preview!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aperçu optimisé',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${p.width}×${p.height} px · ${_formatBytes(p.sizeBytes)} · '
            'WebP qualité 80',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: state.isBusy
                    ? null
                    : () => _confirmUpload(context),
                icon: state.phase == PackImagePhase.uploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload, size: 18),
                label: const Text("Confirmer l'upload"),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: state.isBusy ? null : controller.cancelPreview,
                child: const Text('Annuler'),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImage) ...[
          Text(
            'image_path',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white60,
            ),
          ),
          SelectableText(
            pack.imagePath ?? '—',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
          if (pack.imageHash != null) ...[
            const SizedBox(height: 4),
            Text(
              'image_hash',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white60,
              ),
            ),
            SelectableText(
              '${pack.imageHash!.substring(0, 12)}…',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 12),
        ] else ...[
          Text(
            "Aucune image n'a encore été uploadée. L'app utilise le PNG "
            'bundlé en fallback.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: state.isBusy ? null : controller.pickAndOptimize,
              icon: state.phase == PackImagePhase.optimizing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate, size: 18),
              label: Text(hasImage ? "Changer l'image" : 'Uploader une image'),
            ),
            if (hasImage)
              OutlinedButton.icon(
                onPressed: state.isBusy
                    ? null
                    : () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text("Supprimer l'image"),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Formats acceptés : PNG, JPG, WebP. Minimum 256×256, max 10 Mo. '
          'Conversion automatique en WebP 512×512 (qualité 80).',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
        ),
      ],
    );
  }

  Future<void> _confirmUpload(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await controller.confirmUpload(pack.id);
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Image uploadée.')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer l'image du pack ?"),
        content: const Text(
          "L'image sera retirée de Cloud Storage et les champs `image_*` "
          "effacés du document Firestore. L'app utilisera le PNG bundlé "
          'en fallback. Cette action est immédiate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final path = pack.imagePath;
    if (path == null || path.isEmpty) return;
    final ok = await controller.deleteExistingImage(
      packId: pack.id,
      storagePath: path,
    );
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Image supprimée.')),
      );
    }
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}
