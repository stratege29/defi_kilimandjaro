import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/src/services/admin_functions_service.dart';

/// Dialog de publication d'un pack.
///
/// Flow :
///   1. Au montage : appelle automatiquement `validatePackDraft`
///   2. Affiche {valid, errors, warnings, total}
///   3. Si valid → bouton "Publier v(N+1)" actif
///   4. Click → appelle `publishPack`, affiche résultat (hash, version, size)
///   5. Close dialog
class PublishDialog extends ConsumerStatefulWidget {
  const PublishDialog({required this.packId, super.key});

  final String packId;

  @override
  ConsumerState<PublishDialog> createState() => _PublishDialogState();

  static Future<void> show(BuildContext context, {required String packId}) {
    return showDialog<void>(
      context: context,
      builder: (_) => PublishDialog(packId: packId),
    );
  }
}

class _PublishDialogState extends ConsumerState<PublishDialog> {
  ValidatePackDraftResult? _validation;
  PublishPackResult? _publishResult;
  AdminFunctionException? _error;

  bool _validating = false;
  bool _publishing = false;
  bool _initialized = false;

  Future<void> _validate() async {
    setState(() {
      _validating = true;
      _error = null;
      _validation = null;
    });
    try {
      final service = ref.read(adminFunctionsServiceProvider);
      final result = await service.validatePackDraft(packId: widget.packId);
      setState(() => _validation = result);
    } on AdminFunctionException catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  Future<void> _publish() async {
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final service = ref.read(adminFunctionsServiceProvider);
      final result = await service.publishPack(packId: widget.packId);
      setState(() => _publishResult = result);
    } on AdminFunctionException catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _validate());
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(packId: widget.packId),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
            const Divider(height: 1),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_publishResult != null) {
      return _PublishSuccess(result: _publishResult!);
    }
    if (_error != null) {
      return _ErrorView(error: _error!);
    }
    if (_validating || _validation == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Validation en cours…'),
          ],
        ),
      );
    }
    return _ValidationView(result: _validation!);
  }

  Widget _buildActions() {
    final canPublish = _validation?.valid == true &&
        _publishResult == null &&
        !_publishing;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _publishing
                ? null
                : () => Navigator.of(context).pop(),
            child: Text(_publishResult != null ? 'Fermer' : 'Annuler'),
          ),
          const SizedBox(width: 8),
          if (_publishResult == null) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Revalider'),
              onPressed: (_validating || _publishing) ? null : _validate,
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: _publishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.publish, size: 18),
              label: Text(_publishing ? 'Publication…' : 'Publier maintenant'),
              onPressed: canPublish ? _publish : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.packId});
  final String packId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.publish, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Publier $packId',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Génère un nouveau .json.gz, upload Storage, met à jour le manifest.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidationView extends StatelessWidget {
  const _ValidationView({required this.result});
  final ValidatePackDraftResult result;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(
              result.valid ? Icons.check_circle : Icons.error,
              color: result.valid ? Colors.green : Colors.red,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.valid
                        ? 'Validation OK — prêt à publier'
                        : 'Validation échouée — ${result.errors.length} erreur(s)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${result.total} devinette(s) analysée(s)'
                    '${result.warnings.isNotEmpty ? ' • ${result.warnings.length} warning(s)' : ''}',
                  ),
                ],
              ),
            ),
          ],
        ),
        if (result.errors.isNotEmpty) ...[
          const SizedBox(height: 16),
          _IssuesList(
            title: 'Erreurs (bloquantes)',
            issues: result.errors,
            color: Colors.red,
          ),
        ],
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          _IssuesList(
            title: 'Warnings (non bloquants)',
            issues: result.warnings,
            color: Colors.orange,
          ),
        ],
      ],
    );
  }
}

class _IssuesList extends StatelessWidget {
  const _IssuesList({
    required this.title,
    required this.issues,
    required this.color,
  });

  final String title;
  final List<ValidationIssue> issues;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '$title (${issues.length})',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: issues.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final issue = issues[i];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      issue.code,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  title: Text(
                    issue.deviId,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  subtitle: Text(
                    issue.message,
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PublishSuccess extends StatelessWidget {
  const _PublishSuccess({required this.result});
  final PublishPackResult result;

  String _formatBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Publication réussie — v${result.version}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Kv('Devinettes', '${result.count}'),
              _Kv('Taille gzippée', _formatBytes(result.sizeBytes)),
              _Kv('Catalog version', 'v${result.catalogVersion}'),
              const SizedBox(height: 8),
              _Kv('Storage path', result.storagePath, mono: true),
              const SizedBox(height: 6),
              _Kv('Hash SHA256',
                  '${result.hashSha256.substring(0, 32)}…\n${result.hashSha256.substring(32)}',
                  mono: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Les clients verront cette version au prochain sync OTA '
          '(manuel ou background fetch iOS).',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v, {this.mono = false});
  final String k;
  final String v;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              k,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: TextStyle(
                fontSize: mono ? 11 : 13,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final AdminFunctionException error;

  @override
  Widget build(BuildContext context) {
    final hasValidationErrors = error.validationErrors.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(
              Icons.error,
              color: Theme.of(context).colorScheme.error,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '[${error.code}]',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    error.message,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (hasValidationErrors) ...[
          const SizedBox(height: 16),
          _IssuesList(
            title: 'Erreurs de validation',
            issues: error.validationErrors,
            color: Theme.of(context).colorScheme.error,
          ),
        ],
      ],
    );
  }
}
