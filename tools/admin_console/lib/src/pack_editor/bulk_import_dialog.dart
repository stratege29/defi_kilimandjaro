import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/src/services/admin_functions_service.dart';

/// Dialog d'import en masse de devinettes depuis un JSON.
///
/// Use case principal : coller un batch Gemini (tableau JSON) et l'importer
/// sans CLI. Les devinettes arrivent en `status=draft`. Il faudra publier
/// ensuite via PublishDialog pour les rendre visibles aux clients.
class BulkImportDialog extends ConsumerStatefulWidget {
  const BulkImportDialog({required this.packId, super.key});

  final String packId;

  @override
  ConsumerState<BulkImportDialog> createState() => _BulkImportDialogState();

  static Future<void> show(BuildContext context, {required String packId}) {
    return showDialog<void>(
      context: context,
      builder: (_) => BulkImportDialog(packId: packId),
    );
  }
}

class _BulkImportDialogState extends ConsumerState<BulkImportDialog> {
  final _jsonCtrl = TextEditingController();
  BulkImportMode _mode = BulkImportMode.append;

  bool _importing = false;
  BulkImportResult? _result;
  AdminFunctionException? _error;
  String? _parseError;
  int _parsedCount = 0;

  @override
  void dispose() {
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    setState(() {
      _result = null;
      _error = null;
      _parseError = null;
      _parsedCount = 0;
    });
    if (text.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) {
        setState(
            () => _parseError = 'JSON doit être un tableau (List), pas ${decoded.runtimeType}');
        return;
      }
      setState(() => _parsedCount = decoded.length);
    } on FormatException catch (e) {
      setState(() => _parseError = 'JSON invalide : ${e.message}');
    }
  }

  Future<void> _import() async {
    setState(() {
      _importing = true;
      _error = null;
      _result = null;
    });
    try {
      final decoded = jsonDecode(_jsonCtrl.text) as List<dynamic>;
      final list = decoded
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      final service = ref.read(adminFunctionsServiceProvider);
      final result = await service.bulkImportDevinettes(
        packId: widget.packId,
        devinettes: list,
        mode: _mode,
      );
      setState(() => _result = result);
    } on AdminFunctionException catch (e) {
      setState(() => _error = e);
    } on FormatException catch (e) {
      setState(() => _parseError = e.message);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
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
    if (_result != null) return _ImportSuccess(result: _result!);
    if (_error != null) return _ImportError(error: _error!);
    return _buildEditor();
  }

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<BulkImportMode>(
                  segments: const [
                    ButtonSegment(
                      value: BulkImportMode.append,
                      icon: Icon(Icons.add, size: 16),
                      label: Text('Append (ajoute)'),
                    ),
                    ButtonSegment(
                      value: BulkImportMode.replace,
                      icon: Icon(Icons.swap_horiz, size: 16),
                      label: Text('Replace (vide drafts existants)'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) =>
                      setState(() => _mode = s.first),
                ),
              ),
              const SizedBox(width: 16),
              if (_parsedCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_parsedCount devinette(s) détectée(s)',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _jsonCtrl,
              maxLines: null,
              expands: true,
              onChanged: _onTextChanged,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText:
                    '[\n  {\n    "id": "${widget.packId}_999",\n'
                    '    "pack": "${widget.packId}",\n'
                    '    "answer": "WORD",\n'
                    '    "riddle": { "fr": "..." },\n'
                    '    "explanation": { "fr": "..." },\n'
                    '    "difficulty": 1,\n    "tags": ["..."]\n  },\n  ...\n]',
                hintStyle: TextStyle(
                  fontFamily: 'monospace',
                  color: Theme.of(context).disabledColor,
                ),
              ),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          if (_parseError != null) ...[
            const SizedBox(height: 8),
            Text(
              _parseError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.paste, size: 18),
                tooltip: 'Coller depuis le clipboard',
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    _jsonCtrl.text = data!.text!;
                    _onTextChanged(_jsonCtrl.text);
                  }
                },
              ),
              const SizedBox(width: 8),
              Text(
                'Mode: ${_mode == BulkImportMode.append ? "Append — ajoute aux drafts existants (les drafts homonymes sont remplacés)" : "Replace — supprime TOUS les drafts existants puis insère"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final canImport = _parsedCount > 0 &&
        _parseError == null &&
        !_importing &&
        _result == null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed:
                _importing ? null : () => Navigator.of(context).pop(),
            child: Text(_result != null ? 'Fermer' : 'Annuler'),
          ),
          const SizedBox(width: 8),
          if (_result == null)
            FilledButton.icon(
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload, size: 18),
              label: Text(_importing
                  ? 'Import…'
                  : 'Importer $_parsedCount devinette(s)'),
              onPressed: canImport ? _import : null,
            ),
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
          const Icon(Icons.upload_file, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import en masse — $packId',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Text(
                  'Colle un tableau JSON. Les devinettes arrivent en status=draft.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportSuccess extends StatelessWidget {
  const _ImportSuccess({required this.result});
  final BulkImportResult result;

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
                'Import OK : ${result.accepted} acceptées'
                '${result.rejected.isNotEmpty ? ", ${result.rejected.length} rejetées" : ""}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Mode : ${result.mode} • draft_version : ${result.draftVersion}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (result.rejected.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Rejetées (${result.rejected.length})',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: result.rejected.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = result.rejected[i];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor:
                              Colors.orange.withOpacity(0.2),
                          child: Text(
                            '${r.index}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        title: Text(
                          r.id ?? '(pas d\'id)',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        subtitle: Text(
                          r.error,
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Prochain pas : appelle "Publier" pour faire passer ces drafts '
          'en published et générer la nouvelle version OTA.',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _ImportError extends StatelessWidget {
  const _ImportError({required this.error});
  final AdminFunctionException error;

  @override
  Widget build(BuildContext context) {
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
      ],
    );
  }
}
