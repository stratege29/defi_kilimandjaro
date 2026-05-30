import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kilimandjaro_admin/src/catalog/catalog_providers.dart';
import 'package:kilimandjaro_admin/src/models/catalog_entry.dart';
import 'package:kilimandjaro_admin/src/models/pack_meta.dart';
import 'package:kilimandjaro_admin/src/pack_editor/pack_editor_providers.dart';

/// Métadonnées d'un pack — read-only pour cette phase.
///
/// Édition à venir en Phase 2.5 (mêmes champs en TextField avec save via
/// CF upsertPackMeta / upsertPackI18n à créer).
class MetadataTab extends ConsumerWidget {
  const MetadataTab({required this.packId, super.key});

  final String packId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(catalogEntryProvider(packId));
    final meta = ref.watch(packMetaProvider(packId));
    final i18n = ref.watch(packI18nProvider(packId));

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (entry != null) _CatalogCard(entry: entry),
        const SizedBox(height: 16),
        _MetaCard(metaAsync: meta),
        const SizedBox(height: 16),
        _I18nCard(i18nAsync: i18n),
      ],
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.entry});

  final CatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.book_outlined,
              title: 'Catalogue (catalog/index.packs[])',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 32,
              runSpacing: 12,
              children: [
                _KeyValue(label: 'ID', value: entry.id),
                _KeyValue(label: 'Ordre', value: '${entry.ordering}'),
                _KeyValue(
                  label: 'Visible',
                  value: entry.visible ? 'Oui' : 'Masqué',
                ),
                _KeyValue(label: 'Bundle', value: entry.bundled ? 'Oui' : 'Non'),
                _KeyValue(
                  label: 'Choix gratuit',
                  value: entry.freeChoiceEligible ? 'Éligible' : 'Non',
                ),
                _KeyValue(
                  label: 'Prix',
                  value: entry.unlockCostCauris == 0
                      ? 'Gratuit'
                      : '${entry.unlockCostCauris} ♦',
                ),
                _KeyValue(
                  label: 'Version active',
                  value: 'v${entry.currentVersion}',
                ),
                _KeyValue(
                  label: 'Count',
                  value: '${entry.count}',
                ),
                _KeyValue(
                  label: 'Min app',
                  value: entry.minAppVersion,
                ),
                _KeyValue(
                  label: 'Theme',
                  value: entry.themeColorHex,
                  valueWidget: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: entry.themeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(entry.themeColorHex),
                    ],
                  ),
                ),
              ],
            ),
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Tags marketing',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: entry.tags
                    .map((t) => Chip(
                          label: Text(t),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.metaAsync});

  final AsyncValue<PackMeta?> metaAsync;

  static final _dateFormat = DateFormat('dd MMM yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.settings_outlined,
              title: 'Meta (packs/<id>/meta/doc)',
            ),
            const SizedBox(height: 16),
            metaAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, st) => Text('Erreur: $e'),
              data: (meta) {
                if (meta == null) {
                  return const Text(
                    'Aucun meta — lancer seed_backoffice.mjs pour seeder.',
                  );
                }
                return Wrap(
                  spacing: 32,
                  runSpacing: 12,
                  children: [
                    _KeyValue(
                      label: 'Dernière version publiée',
                      value: 'v${meta.latestPublishedVersion}',
                    ),
                    _KeyValue(
                      label: 'Prochaine version draft',
                      value: 'v${meta.nextDraftVersion}',
                    ),
                    _KeyValue(
                      label: 'Modifs en attente',
                      value: '${meta.pendingChanges}',
                    ),
                    if (meta.updatedAt != null)
                      _KeyValue(
                        label: 'Modifié',
                        value: _dateFormat.format(meta.updatedAt!),
                      ),
                    if (meta.updatedBy != null)
                      _KeyValue(label: 'Par', value: meta.updatedBy!),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _I18nCard extends StatelessWidget {
  const _I18nCard({required this.i18nAsync});

  final AsyncValue<List<PackI18n>> i18nAsync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.translate_outlined,
              title: 'Traductions (packs/<id>/i18n/<lang>)',
            ),
            const SizedBox(height: 16),
            i18nAsync.when(
              loading: () => const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (e, st) => Text('Erreur: $e'),
              data: (list) {
                if (list.isEmpty) {
                  return const Text('Aucune traduction.');
                }
                return Column(
                  children: list
                      .map((i) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Chip(
                                  label: Text(i.lang.toUpperCase()),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        i.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (i.shortTagline.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          i.shortTagline,
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Theme.of(context)
                                                .disabledColor,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(i.description),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({
    required this.label,
    required this.value,
    this.valueWidget,
  });

  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).disabledColor,
            ),
          ),
          const SizedBox(height: 2),
          valueWidget ??
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
        ],
      ),
    );
  }
}
