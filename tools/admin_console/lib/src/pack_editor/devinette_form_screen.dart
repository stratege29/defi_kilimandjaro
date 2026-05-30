import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/src/models/devinette.dart';
import 'package:kilimandjaro_admin/src/pack_editor/pack_editor_providers.dart';
import 'package:kilimandjaro_admin/src/services/admin_functions_service.dart';

/// Formulaire d'édition unitaire d'une devinette.
///
/// Modes :
///   - création : `deviId` null, `nextId` calculé depuis le pack
///   - édition  : `deviId` fourni, charge le doc Firestore en initial state
///
/// Comportements :
///   - answer en UPPER ; answer_normalized + letters_pool recalculés à la volée
///   - Preview live de la grille circulaire (cercle de lettres)
///   - Tags chips avec autocomplete depuis catalog/tags_whitelist
///   - Save → CF upsertDevinette (crée en status=draft)
class DevinetteFormScreen extends ConsumerStatefulWidget {
  const DevinetteFormScreen({
    required this.packId,
    this.deviId,
    super.key,
  });

  final String packId;
  final String? deviId;

  @override
  ConsumerState<DevinetteFormScreen> createState() =>
      _DevinetteFormScreenState();

  /// Push helper pour ouvrir le form en modal pleine page.
  static Future<bool?> show(
    BuildContext context, {
    required String packId,
    String? deviId,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => DevinetteFormScreen(packId: packId, deviId: deviId),
      ),
    );
  }
}

class _DevinetteFormScreenState extends ConsumerState<DevinetteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();
  final _riddleFrCtrl = TextEditingController();
  final _riddleEnCtrl = TextEditingController();
  final _explanationFrCtrl = TextEditingController();
  final _explanationEnCtrl = TextEditingController();

  int _difficulty = 1;
  int _estimatedTimeS = 25;
  String _country = 'ci';
  List<String> _tags = [];

  bool _loading = true;
  bool _saving = false;
  String? _saveError;
  bool _initialized = false;

  @override
  void dispose() {
    _idCtrl.dispose();
    _answerCtrl.dispose();
    _riddleFrCtrl.dispose();
    _riddleEnCtrl.dispose();
    _explanationFrCtrl.dispose();
    _explanationEnCtrl.dispose();
    super.dispose();
  }

  Future<void> _initFromExisting() async {
    final id = widget.deviId;
    if (id == null) {
      // Création : calcule le prochain ID disponible
      final snap = await FirebaseFirestore.instance
          .collection('packs')
          .doc(widget.packId)
          .collection('devinettes')
          .orderBy('id', descending: true)
          .limit(1)
          .get();
      var nextNum = 1;
      if (snap.docs.isNotEmpty) {
        final lastId = snap.docs.first.id;
        final m = RegExp(r'_(\d+)$').firstMatch(lastId);
        if (m != null) {
          nextNum = int.parse(m.group(1)!) + 1;
        }
      }
      _idCtrl.text =
          '${widget.packId}_${nextNum.toString().padLeft(3, '0')}';
      setState(() => _loading = false);
      return;
    }
    // Édition : charge le doc existant
    final doc = await FirebaseFirestore.instance
        .collection('packs')
        .doc(widget.packId)
        .collection('devinettes')
        .doc(id)
        .get();
    if (!doc.exists) {
      setState(() {
        _loading = false;
        _saveError = 'Devinette $id introuvable.';
      });
      return;
    }
    final d = Devinette.fromDoc(doc);
    _idCtrl.text = d.id;
    _answerCtrl.text = d.answer;
    _riddleFrCtrl.text = d.riddle['fr'] ?? '';
    _riddleEnCtrl.text = d.riddle['en'] ?? '';
    _explanationFrCtrl.text = d.explanation['fr'] ?? '';
    _explanationEnCtrl.text = d.explanation['en'] ?? '';
    _difficulty = d.difficulty;
    _estimatedTimeS = d.estimatedTimeS;
    _country = d.country;
    _tags = List<String>.from(d.tags);
    setState(() => _loading = false);
  }

  // ---- Logique de normalisation (alignée sur les CFs serveur) -----------

  static const Map<String, String> _diacritics = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
    'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'î': 'i', 'ï': 'i', 'í': 'i',
    'ò': 'o', 'ô': 'o', 'ö': 'o', 'ó': 'o', 'õ': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
    'ÿ': 'y', 'ý': 'y',
    'ñ': 'n',
  };

  String _normalize(String input) {
    final lower = input.toLowerCase();
    final buf = StringBuffer();
    for (final ch in lower.split('')) {
      buf.write(_diacritics[ch] ?? ch);
    }
    return buf.toString();
  }

  List<String> _lettersPoolFromAnswer(String answer) {
    final out = <String>[];
    final upper = _normalize(answer).toUpperCase();
    for (final ch in upper.split('')) {
      if (ch.codeUnitAt(0) >= 65 && ch.codeUnitAt(0) <= 90) {
        out.add(ch);
      }
    }
    return out;
  }

  // ---- Save ------------------------------------------------------------

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final service = ref.read(adminFunctionsServiceProvider);
      final result = await service.upsertDevinette(
        packId: widget.packId,
        devinette: {
          'id': _idCtrl.text.trim(),
          'pack': widget.packId,
          'country': _country,
          'answer': _answerCtrl.text.trim().toUpperCase(),
          'riddle': {
            if (_riddleFrCtrl.text.trim().isNotEmpty)
              'fr': _riddleFrCtrl.text.trim(),
            if (_riddleEnCtrl.text.trim().isNotEmpty)
              'en': _riddleEnCtrl.text.trim(),
          },
          'explanation': {
            if (_explanationFrCtrl.text.trim().isNotEmpty)
              'fr': _explanationFrCtrl.text.trim(),
            if (_explanationEnCtrl.text.trim().isNotEmpty)
              'en': _explanationEnCtrl.text.trim(),
          },
          'difficulty': _difficulty,
          'estimated_time_s': _estimatedTimeS,
          'tags': _tags,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.created
                ? 'Devinette ${result.deviId} créée en draft.'
                : 'Devinette ${result.deviId} mise à jour.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } on AdminFunctionException catch (e) {
      setState(() => _saveError = '[${e.code}] ${e.message}');
    } catch (e) {
      setState(() => _saveError = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- UI --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      _initialized = true;
      _initFromExisting();
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          widget.deviId == null
              ? 'Nouvelle devinette'
              : 'Éditer ${widget.deviId}',
        ),
        actions: [
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save, size: 18),
            label: Text(_saving ? 'Sauvegarde…' : 'Enregistrer (draft)'),
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildFormPane(),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _buildPreviewPane(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFormPane() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_saveError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .errorContainer
                    .withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _saveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _idCtrl,
                  enabled: widget.deviId == null,
                  decoration: const InputDecoration(
                    labelText: 'ID',
                    border: OutlineInputBorder(),
                    helperText: 'Format <packId>_NNN',
                  ),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (!RegExp(r'^[a-z][a-z0-9_]*_\d{3,4}$').hasMatch(value)) {
                      return 'Format invalide';
                    }
                    if (!value.startsWith('${widget.packId}_')) {
                      return 'Doit commencer par ${widget.packId}_';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<String>(
                  initialValue: _country,
                  decoration: const InputDecoration(
                    labelText: 'Pays',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ci', child: Text('CI')),
                    DropdownMenuItem(value: 'sn', child: Text('SN')),
                    DropdownMenuItem(value: 'ml', child: Text('ML')),
                    DropdownMenuItem(value: 'cm', child: Text('CM')),
                    DropdownMenuItem(value: 'bj', child: Text('BJ')),
                  ],
                  onChanged: (v) => setState(() => _country = v ?? 'ci'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _answerCtrl,
            decoration: const InputDecoration(
              labelText: 'Answer (MAJUSCULES, 4-12 lettres)',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'[a-zA-ZÀ-ÿ]'),
              ),
            ],
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final value = (v ?? '').trim();
              if (value.length < 4 || value.length > 12) {
                return 'Entre 4 et 12 lettres';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          _NormalizedPreview(answer: _answerCtrl.text, normalize: _normalize),
          const SizedBox(height: 24),
          _SectionLabel('Riddle (énigme)'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _riddleFrCtrl,
            decoration: const InputDecoration(
              labelText: 'Riddle FR',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            validator: (v) {
              if ((v ?? '').trim().isEmpty) {
                return 'Au moins le FR requis pour publish';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _riddleEnCtrl,
            decoration: const InputDecoration(
              labelText: 'Riddle EN (optionnel)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          _SectionLabel('Explanation (contexte culturel)'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _explanationFrCtrl,
            decoration: const InputDecoration(
              labelText: 'Explanation FR',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _explanationEnCtrl,
            decoration: const InputDecoration(
              labelText: 'Explanation EN (optionnel)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          _SectionLabel('Difficulté & timing'),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Difficulté'),
              Expanded(
                child: Slider(
                  value: _difficulty.toDouble(),
                  min: 1,
                  max: 4,
                  divisions: 3,
                  label: 'd$_difficulty',
                  onChanged: (v) => setState(() => _difficulty = v.toInt()),
                ),
              ),
              Text('d$_difficulty', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          Row(
            children: [
              const Text('Temps estimé '),
              Expanded(
                child: Slider(
                  value: _estimatedTimeS.toDouble(),
                  min: 10,
                  max: 90,
                  divisions: 16,
                  label: '${_estimatedTimeS}s',
                  onChanged: (v) => setState(() => _estimatedTimeS = v.toInt()),
                ),
              ),
              Text('${_estimatedTimeS}s',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 24),
          _SectionLabel('Tags'),
          const SizedBox(height: 8),
          _TagsEditor(
            tags: _tags,
            onChanged: (t) => setState(() => _tags = t),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPreviewPane() {
    final answer = _answerCtrl.text.trim();
    final lettersPool = _lettersPoolFromAnswer(answer);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('Preview'),
            const SizedBox(height: 16),
            Center(
              child: _CircularGridPreview(letters: lettersPool),
            ),
            const SizedBox(height: 24),
            _PreviewField(
              label: 'Lettres (multiset)',
              value: lettersPool.isEmpty ? '—' : lettersPool.join(' '),
            ),
            const SizedBox(height: 12),
            _PreviewField(
              label: 'Riddle FR',
              value: _riddleFrCtrl.text.trim().isEmpty
                  ? '(vide)'
                  : _riddleFrCtrl.text.trim(),
              italic: true,
            ),
            const SizedBox(height: 12),
            _PreviewField(
              label: 'Tags',
              value: _tags.isEmpty ? '(aucun)' : _tags.join(' · '),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('JSON Firestore (preview)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  SelectableText(
                    '{\n'
                    '  "id": "${_idCtrl.text}",\n'
                    '  "pack": "${widget.packId}",\n'
                    '  "answer": "${answer.toUpperCase()}",\n'
                    '  "answer_normalized": "${_normalize(answer)}",\n'
                    '  "letters_pool": [${lettersPool.map((l) => '"$l"').join(', ')}],\n'
                    '  "difficulty": $_difficulty,\n'
                    '  "estimated_time_s": $_estimatedTimeS,\n'
                    '  "tags": [${_tags.map((t) => '"$t"').join(', ')}],\n'
                    '  "country": "$_country"\n'
                    '}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Widgets utilitaires
// ===========================================================================

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _NormalizedPreview extends StatelessWidget {
  const _NormalizedPreview({
    required this.answer,
    required this.normalize,
  });
  final String answer;
  final String Function(String) normalize;

  @override
  Widget build(BuildContext context) {
    if (answer.trim().isEmpty) return const SizedBox.shrink();
    final normalized = normalize(answer);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        'normalized = "$normalized" • ${answer.length} chars',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).disabledColor,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _TagsEditor extends ConsumerStatefulWidget {
  const _TagsEditor({required this.tags, required this.onChanged});
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  @override
  ConsumerState<_TagsEditor> createState() => _TagsEditorState();
}

class _TagsEditorState extends ConsumerState<_TagsEditor> {
  final _addCtrl = TextEditingController();

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty || widget.tags.contains(t)) {
      _addCtrl.clear();
      return;
    }
    final next = [...widget.tags, t];
    widget.onChanged(next);
    _addCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final whitelist =
        ref.watch(tagsWhitelistProvider).valueOrNull ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in widget.tags)
              Chip(
                label: Text(t),
                onDeleted: () {
                  final next = [...widget.tags]..remove(t);
                  widget.onChanged(next);
                },
                visualDensity: VisualDensity.compact,
                backgroundColor: whitelist.contains(t)
                    ? null
                    : Theme.of(context).colorScheme.errorContainer,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Autocomplete<String>(
          optionsBuilder: (text) {
            final q = text.text.toLowerCase();
            if (q.isEmpty) return const Iterable.empty();
            return whitelist
                .where((t) => t.contains(q) && !widget.tags.contains(t))
                .take(20);
          },
          onSelected: _addTag,
          fieldViewBuilder: (context, controller, focus, onSubmit) {
            return TextField(
              controller: controller,
              focusNode: focus,
              decoration: InputDecoration(
                hintText: 'Ajouter un tag (Enter ou clic suggestion)',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _addTag(controller.text),
                ),
              ),
              onSubmitted: (v) {
                _addTag(v);
                controller.clear();
              },
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          '${whitelist.length} tags whitelistés',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).disabledColor,
          ),
        ),
      ],
    );
  }
}

class _CircularGridPreview extends StatelessWidget {
  const _CircularGridPreview({required this.letters});
  final List<String> letters;

  static const double _size = 280;

  @override
  Widget build(BuildContext context) {
    if (letters.isEmpty) {
      return Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).disabledColor,
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Text(
            '(vide)',
            style: TextStyle(color: Theme.of(context).disabledColor),
          ),
        ),
      );
    }

    final radius = _size / 2 - 28;
    final theta = (2 * math.pi) / letters.length;

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              ),
            ),
          ),
          for (var i = 0; i < letters.length; i++)
            Transform.translate(
              offset: Offset(
                radius * math.cos(theta * i - math.pi / 2),
                radius * math.sin(theta * i - math.pi / 2),
              ),
              child: _LetterTile(letter: letters[i]),
            ),
        ],
      ),
    );
  }
}

class _LetterTile extends StatelessWidget {
  const _LetterTile({required this.letter});
  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFD2A24C),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }
}

class _PreviewField extends StatelessWidget {
  const _PreviewField({
    required this.label,
    required this.value,
    this.italic = false,
  });
  final String label;
  final String value;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).disabledColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
