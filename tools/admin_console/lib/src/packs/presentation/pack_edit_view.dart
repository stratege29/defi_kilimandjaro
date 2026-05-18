import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kilimandjaro_admin/src/packs/data/packs_repository.dart';
import 'package:kilimandjaro_admin/src/packs/domain/pack.dart';
import 'package:kilimandjaro_admin/src/packs/presentation/pack_image_card.dart';

/// Édite les métadonnées d'un pack + déclenche la publication OTA.
/// Écran d'édition d'un pack.
class PackEditView extends ConsumerStatefulWidget {
  /// Construit l'éditeur du pack `packId`.
  const PackEditView({required this.packId, super.key});

  /// Id du pack édité.
  final String packId;

  @override
  ConsumerState<PackEditView> createState() => _PackEditViewState();
}

class _PackEditViewState extends ConsumerState<PackEditView> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _country = TextEditingController();
  final _priceEur = TextEditingController();
  final _priceCauris = TextEditingController();
  bool _enabled = false;
  bool _freeChoiceEligible = false;
  bool _initialized = false;
  bool _saving = false;
  bool _publishing = false;
  String? _publishStatus;

  void _initFromPack(Pack p) {
    if (_initialized) return;
    _name.text = p.name;
    _description.text = p.description;
    _country.text = p.country;
    _priceEur.text = p.priceEur.toString();
    _priceCauris.text = p.priceCauris.toString();
    _enabled = p.enabled;
    _freeChoiceEligible = p.freeChoiceEligible;
    _initialized = true;
  }

  Future<void> _save(Pack current) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(packsRepositoryProvider).upsertPack(
            current.copyWith(
              name: _name.text.trim(),
              description: _description.text.trim(),
              country: _country.text.trim(),
              enabled: _enabled,
              freeChoiceEligible: _freeChoiceEligible,
              priceEur: double.tryParse(_priceEur.text.trim()) ?? 0,
              priceCauris: int.tryParse(_priceCauris.text.trim()) ?? 0,
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Métadonnées sauvegardées.')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publish() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publier le pack ?'),
        content: const Text(
          'Le pack sera reconstruit depuis Firestore, gzippé, uploadé '
          'vers Cloud Storage, et la nouvelle version sera distribuée à '
          "tous les utilisateurs au prochain démarrage de l'app.\n\n"
          'Cette opération bumpe la version du pack systématiquement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Publier'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _publishing = true;
      _publishStatus = null;
    });
    try {
      final res =
          await ref.read(packsRepositoryProvider).publishPack(widget.packId);
      if (mounted) {
        setState(() {
          _publishStatus =
              'OK · v${res.version} · ${res.count} questions · '
              '${res.sizeBytes}B · hash ${res.hash.substring(0, 12)}…';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pack publié en v${res.version}.')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(
          () => _publishStatus = 'ERREUR ${e.code} : ${e.message ?? ""}',
        );
      }
    } on Object catch (e) {
      if (mounted) setState(() => _publishStatus = 'ERREUR : $e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _country.dispose();
    _priceEur.dispose();
    _priceCauris.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final packAsync = ref.watch(packProvider(widget.packId));
    return packAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur : $e')),
      data: (pack) {
        _initFromPack(pack);
        return _buildBody(context, pack);
      },
    );
  }

  Widget _buildBody(BuildContext context, Pack pack) {
    final df = DateFormat.yMMMd().add_Hm();
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Header
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.go('/packs'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    pack.id,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _publishing
                        ? null
                        : () => context.go('/packs/${pack.id}/questions'),
                    icon: const Icon(Icons.list),
                    label: Text('Questions (${pack.count})'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _publishing ? null : _publish,
                    icon: _publishing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: const Text('Publier le pack'),
                  ),
                ],
              ),
              if (_publishStatus != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_publishStatus!),
                ),
              ],
              const SizedBox(height: 24),

              // ---- Manifest (read-only)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manifest OTA (read-only — mis à jour par publishPack)',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      _kv('current_version', 'v${pack.currentVersion}'),
                      _kv('count', '${pack.count}'),
                      _kv(
                        'hash_sha256',
                        pack.hashSha256.isEmpty
                            ? '(jamais publié)'
                            : pack.hashSha256,
                      ),
                      _kv('size_bytes', '${pack.sizeBytes}'),
                      _kv(
                        'storage_path',
                        pack.storagePath.isEmpty ? '—' : pack.storagePath,
                      ),
                      _kv(
                        'last_published_at',
                        pack.lastPublishedAt == null
                            ? '—'
                            : df.format(pack.lastPublishedAt!),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ---- Image du pack
              PackImageCard(pack: pack),
              const SizedBox(height: 24),

              // ---- Metadata form
              Text('Métadonnées', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom affiché'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _country,
                decoration: const InputDecoration(
                  labelText: 'country (code 2 lettres)',
                ),
                validator: (v) {
                  if (v == null || v.trim().length != 2) {
                    return 'Code pays à 2 lettres (ex: ci).';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceEur,
                      decoration: const InputDecoration(
                        labelText: 'Prix EUR',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _priceCauris,
                      decoration: const InputDecoration(
                        labelText: 'Prix Cauris',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('enabled'),
                subtitle: const Text(
                  "Active la distribution dans l'app. Décocher pour cacher "
                  'un pack sans le supprimer.',
                ),
              ),
              SwitchListTile(
                value: _freeChoiceEligible,
                onChanged: (v) =>
                    setState(() => _freeChoiceEligible = v),
                title: const Text('free_choice_eligible'),
                subtitle: const Text(
                  'Le joueur peut le choisir comme pack gratuit à '
                  "l'onboarding.",
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed:
                        _saving || _publishing ? null : () => _save(pack),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Sauvegarder les métadonnées'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: Text(
                k,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.white70,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                v,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      );
}
