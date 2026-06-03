import 'dart:async';
import 'dart:convert';

import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/wallet/cauris_credit_sink.dart';
import 'package:defi_kilimandjaro/data/wallet/wallet_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Outbox transactionnel idempotent pour les crédits cauris.
///
/// Patron « transactional outbox » (standard documenté pour la monnaie
/// offline-capable) : chaque gain in-game est d'abord appliqué au solde local
/// (offline-first), puis **enfilé** ici avec une clé UUID stable. Un flusher
/// pousse les entrées au wallet serveur via `creditCauris(idempotencyKey:…)` ;
/// la clé garantit l'**exactly-once** même en cas de retry (réseau coupé,
/// app tuée). Cf `docs/wallet_server_schema.md` §3.
///
/// Garanties :
/// - **Durable** : la file vit dans SharedPreferences, survit aux reboots.
/// - **Idempotent** : la clé UUID = ID du doc d'audit serveur ; un replay est
///   un no-op côté CF.
/// - **Fail-soft** : une erreur réseau retient l'entrée pour un flush ultérieur
///   (boot suivant) ; un rejet permanent (cap anti-cheat) la supprime.
class CaurisCreditOutbox implements CaurisCreditSink {
  CaurisCreditOutbox({
    required SharedPreferences prefs,
    required WalletService wallet,
    Uuid? uuid,
  })  : _prefs = prefs,
        _wallet = wallet,
        _uuid = uuid ?? const Uuid();

  static const String _storageKey = 'cauris_credit_outbox';

  /// Plafond de tentatives par entrée avant abandon (anti-boucle infinie sur
  /// une entrée empoisonnée que le serveur rejetterait éternellement).
  static const int _maxAttempts = 50;

  final SharedPreferences _prefs;
  final WalletService _wallet;
  final Uuid _uuid;

  bool _flushing = false;

  @override
  void enqueue({
    required int amount,
    required CaurisCreditSource source,
    String? reference,
  }) {
    if (amount <= 0) return;
    final entries = _load()
      ..add(
        _OutboxEntry(
          key: _uuid.v4(),
          amount: amount,
          source: source,
          reference: reference,
        ),
      );
    // Persiste d'abord (durabilité), puis tente un flush opportuniste.
    unawaited(_persist(entries).then((_) => flush()));
  }

  /// Pousse toutes les entrées en attente. Idempotent et ré-entrant-safe :
  /// un flush déjà en cours court-circuite (le suivant reprendra le reste).
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      var entries = _load();
      if (entries.isEmpty) return;

      final survivors = <_OutboxEntry>[];
      for (final entry in entries) {
        final outcome = await _tryPush(entry);
        switch (outcome) {
          case _PushOutcome.done:
          case _PushOutcome.dropped:
            // Crédité (ou rejet permanent) → on retire de la file.
            break;
          case _PushOutcome.retry:
            final retried = entry.incremented();
            if (retried.attempts < _maxAttempts) survivors.add(retried);
          // Sinon : abandon silencieux après trop de tentatives.
        }
      }

      // Recharge avant d'écrire : un enqueue concurrent a pu ajouter des
      // entrées pendant le flush. On préserve celles qu'on n'a pas traitées.
      final current = _load();
      final processed = entries.map((e) => e.key).toSet();
      final appended =
          current.where((e) => !processed.contains(e.key)).toList();
      entries = [...survivors, ...appended];
      await _persist(entries);
    } finally {
      _flushing = false;
    }
  }

  /// Tente un push unitaire. Mappe les erreurs wallet sur une issue.
  Future<_PushOutcome> _tryPush(_OutboxEntry entry) async {
    try {
      await _wallet.creditCauris(
        amount: entry.amount,
        source: entry.source,
        reference: entry.reference,
        idempotencyKey: entry.key,
      );
      return _PushOutcome.done;
    } on WalletException catch (e) {
      if (e.isNotBootstrapped) {
        // Le wallet n'existe pas encore : on bootstrap au prochain reconcile
        // (login/boot). On retient l'entrée pour la repousser après.
        return _PushOutcome.retry;
      }
      if (e.code == 'invalid-argument') {
        // Cap anti-cheat dépassé : rejet permanent, inutile de retenter.
        return _PushOutcome.dropped;
      }
      // Réseau / App Check / indisponible : transitoire.
      return _PushOutcome.retry;
    } on Object {
      return _PushOutcome.retry;
    }
  }

  List<_OutboxEntry> _load() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <_OutboxEntry>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(_OutboxEntry.fromJson)
          .whereType<_OutboxEntry>()
          .toList();
    } on FormatException {
      return <_OutboxEntry>[];
    }
  }

  Future<void> _persist(List<_OutboxEntry> entries) async {
    if (entries.isEmpty) {
      await _prefs.remove(_storageKey);
      return;
    }
    await _prefs.setString(
      _storageKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}

enum _PushOutcome { done, dropped, retry }

class _OutboxEntry {
  _OutboxEntry({
    required this.key,
    required this.amount,
    required this.source,
    this.reference,
    this.attempts = 0,
  });

  static _OutboxEntry? fromJson(Map<String, dynamic> j) {
    final sourceName = j['source'] as String?;
    final source = CaurisCreditSource.values
        .where((s) => s.name == sourceName)
        .cast<CaurisCreditSource?>()
        .firstWhere((s) => s != null, orElse: () => null);
    final key = j['key'] as String?;
    final amount = (j['amount'] as num?)?.toInt();
    if (key == null || amount == null || source == null) return null;
    return _OutboxEntry(
      key: key,
      amount: amount,
      source: source,
      reference: j['reference'] as String?,
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    );
  }

  final String key;
  final int amount;
  final CaurisCreditSource source;
  final String? reference;
  final int attempts;

  _OutboxEntry incremented() => _OutboxEntry(
        key: key,
        amount: amount,
        source: source,
        reference: reference,
        attempts: attempts + 1,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'amount': amount,
        'source': source.name,
        if (reference != null) 'reference': reference,
        'attempts': attempts,
      };
}

/// Fournit l'outbox durable, branché sur SharedPreferences + WalletService.
final caurisCreditOutboxProvider = Provider<CaurisCreditOutbox>((ref) {
  return CaurisCreditOutbox(
    prefs: ref.watch(sharedPreferencesProvider),
    wallet: ref.watch(walletServiceProvider),
  );
});
