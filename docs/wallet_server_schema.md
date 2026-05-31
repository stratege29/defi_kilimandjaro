# Wallet côté serveur — Phase 4

> **Statut** : design Phase 4 (juin 2026). À implémenter dans `functions/src/wallet/`.
> **Précédent** : [`docs/backoffice_schema.md`](backoffice_schema.md) (Phase 1-2).

---

## 1. Objectif

Faire transitionner le wallet utilisateur (`cauris` + `ownedPacks`) du **client SharedPreferences vers Firestore**, avec :

1. **Anti-cheat strict** : toute modification du wallet passe par une Cloud Function avec validation serveur (prix lu depuis `catalog/index`, jamais du client).
2. **Audit trail immuable** : chaque opération (unlock, credit, debit) est loggée dans une sous-collection.
3. **Offline-first préservé** : le client garde SharedPreferences comme cache local. Synchronisation pull/push en arrière-plan.
4. **Restore cross-device** : un user qui réinstalle l'app récupère ses packs et son solde en se reconnectant.

## 2. Schéma Firestore

```
users/{uid}/inventory/
  wallet                            ← doc unique
    {
      cauris: 350,                   ← solde courant
      owned_packs: ["culture_ci"],   ← liste packId débloqués
      version: 12,                   ← incrémenté à chaque mutation (optimistic concurrency)
      created_at: <ts>,
      updated_at: <ts>,
      last_sync_at: <ts>,            ← dernier push client
      bootstrap_source: "client_v1"  ← d'où vient le bootstrap initial
    }

  audit/{logId}                      ← subcollection, append-only
    {
      type: "unlock_pack" | "credit_cauris" | "debit_cauris" | "iap_grant"
            | "bootstrap" | "tamper_detected",
      timestamp: <ts>,
      actor_uid: <uid>,               ← égal au parent
      source: "win"|"daily"|"rewarded"|"streak"|"iap"|"unlock"|"manual",
      amount: <int>,                  ← signé (positif credit, négatif debit)
      pack_id: <string|null>,         ← si unlock_pack
      product_id: <string|null>,      ← si iap_grant
      cauris_before: <int>,
      cauris_after: <int>,
      wallet_version_before: <int>,
      wallet_version_after: <int>,
      details: { ... }                ← payload libre selon type
    }
```

## 3. Cycle de vie

```
[Premier lancement post-Phase 4]
        │
        ▼
  Client a SharedPrefs avec cauris=N et ownedPacks=[X,Y]
        │
        ▼  WalletRepository.ensureBootstrapped()
        ▼
  CF bootstrapWallet(input: {cauris, ownedPacks})
        │
        ├─ Si wallet doc déjà existe → no-op (idempotent), retourne le serveur
        │   pour resync client
        ▼
  Création wallet doc avec :
    - cauris = min(input.cauris, eco_initial_cauris + grace_margin)  ← anti-cheat
    - owned_packs = input.ownedPacks ∩ catalog/index.packs[].id (filtre)
    - version = 1, bootstrap_source = "client_v1"
    - audit log type=bootstrap

[Achat d'un pack avec ses cauris]
        │
        ▼  UI : tap "Débloquer (X cauris)" sur MyPacksView
        ▼  WalletRepository.unlockPack(packId)
        ▼
  CF unlockPack(input: {packId})
        │
        ├─ Lit catalog/index, trouve unlock_cost_cauris (FAIL si pack inconnu)
        ├─ Lit wallet doc (FAIL si pas bootstrapped)
        ├─ Vérifie cauris >= cost (FAIL failed-precondition)
        ├─ Vérifie not in owned_packs (FAIL already-exists)
        ▼
  Transaction Firestore :
    - wallet.cauris -= cost
    - wallet.owned_packs += packId
    - wallet.version += 1
    - écrit audit log type=unlock_pack
        │
        ▼
  Retourne {newBalance, newVersion, packId}
        │
        ▼  Client : grantPack local + addCauris(-cost)

[Crédit cauris in-game (win, daily, rewarded)]
        │
        ▼  PlayerProgressRepository.recordWin/recordDaily/...
        ▼
  → Crédit local immédiat (UX snappy, offline-first)
  → unawaited(WalletRepository.creditCauris(amount, source))
        ▼
  CF creditCauris(input: {amount, source})
        │
        ├─ Validate amount <= MAX_PER_SOURCE[source] (anti-cheat)
        ├─ MAX_PER_SOURCE = {
        │     win: 100,        ← > eco_win_reward_base * tier max
        │     daily: 600,      ← base + bonus max
        │     rewarded: 200,   ← marge sur eco_rewarded_video_bonus
        │     streak: 500,
        │   }
        ▼
  Transaction :
    - wallet.cauris += amount (saturation à MAX_BALANCE)
    - wallet.version += 1
    - audit log type=credit_cauris
        │
        ▼
  Retourne {newBalance}

[Détection tampering]
        │
        ▼  Client push wallet.cauris > serveur.cauris + max_credit_pending
        ▼
  CF rejette failed-precondition + audit log type=tamper_detected
        │
        ▼  Client doit pull-down forcé (resync) + UI flash discret
```

## 4. Stratégie offline-first

Le client garde **SharedPreferences comme source of truth UI**. Le serveur est :
- **Validateur** (CFs unlock/credit valident et persistent)
- **Audit log** (traçabilité légale)
- **Restore source** (re-installation app)

Le client ne **bloque jamais** un gain in-game sur un round-trip serveur. Pattern :

```dart
// Dans PlayerProgressRepository.recordWin :
await _persistLocally(state.copyWith(cauris: state.cauris + reward));
unawaited(_walletRepo.creditCauris(reward, source: 'win'));  // fire-and-forget
```

Si le push serveur échoue (network down), le change reste local. À la prochaine sync :
- `WalletRepository.sync()` compare local vs server
- Si local.version < server.version → pull (serveur gagne sur conflit version)
- Si local.cauris > server.cauris → push delta via batched CF calls

## 5. Anti-cheat (par couches)

| Couche | Mécanisme |
|---|---|
| **Bootstrap** | Cap `cauris` initial à `eco_initial_cauris + 1000` pour éviter spam |
| **Credit** | `amount <= MAX_PER_SOURCE[source]` (table de coefficients par type d'action) |
| **Debit/Unlock** | Prix lu depuis `catalog/index` serveur (client envoie juste packId) |
| **Concurrency** | Champ `version` incrémenté à chaque mutation (optimistic lock dans transaction) |
| **Audit immuable** | `audit/{logId}` append-only, jamais effacé, indexé par timestamp+type |
| **Tamper detection** | Si client push cauris > serveur.cauris + (MAX_PER_SOURCE × max_pending_window) → log + reset client |
| **Rate limiting** | Réutilise `users_quota` existant (5 unlock/jour max par exemple) |

## 6. Firestore rules

```
match /users/{uid}/inventory/wallet {
  allow read: if isSignedIn() && request.auth.uid == uid;
  allow write: if false;  // CFs uniquement
}

match /users/{uid}/inventory/audit/{logId} {
  allow read: if isSignedIn() && request.auth.uid == uid;  // user voit son propre audit
  allow write: if false;  // CFs uniquement (append-only)
}
```

(L'audit est lisible par l'user pour transparence — peut être restreint admin-only en Phase 5 si besoin RGPD.)

## 7. Cloud Functions à créer

| CF | Type | Guard | Effet |
|---|---|---|---|
| `bootstrapWallet` | onCall | requireAuth | Crée wallet doc depuis input client (cap anti-cheat). Idempotent. |
| `unlockPack` | onCall | requireAuth | Transaction débit cauris + add pack. Audit log. |
| `creditCauris` | onCall | requireAuth | Crédit avec cap MAX_PER_SOURCE. Audit log. |
| `syncWallet` | onCall | requireAuth | Retourne le wallet courant pour pull-down client. |

Pas de `debitCauris` directe (les dépenses passent toutes par `unlockPack` ou par les paid features Phase 5 — hint, reveal, freeze token qui restent local pour l'instant).

## 8. Migration utilisateurs existants

À la sortie de Phase 4, les utilisateurs ont déjà des wallets SharedPreferences. Le flow de migration :

1. Au prochain boot post-deploy :
   - Si user logged-in (Firebase Auth) → `WalletRepository.ensureBootstrapped()`
   - Lit local cauris + ownedPacks → appelle `bootstrapWallet` CF
   - CF crée wallet doc + audit log type=bootstrap
   - Client sync (pull pour vérif)
2. Si user pas authentifié (rare — quasi tout user a auth anonyme Firebase) → différer jusqu'au prochain login
3. Si network down → retry au prochain boot (idempotent)

**Note** : pas de bouton "Migrer maintenant" UI. Le bootstrap se fait silencieusement.

## 9. Coûts Firestore

À l'échelle 10 000 utilisateurs actifs × 5 events économiques/jour :
- 50 000 writes/jour × 30 = 1.5 M writes/mois
- Coût Firestore : ~3 €/mois (0.18 €/100k writes)
- Reads : 1 read/boot pour pull wallet → 300 k/mois → négligeable

À l'échelle 100 000 users : ~30 €/mois. Très acceptable.

## 10. Open questions

- **Rate limiting** : utiliser `users_quota` existant ou créer un compteur dédié `wallet_quota` ? Pour MVP, on skip (les CFs sont déjà gated par auth).
- **Notification user en cas de tamper detected** : silencieux ou snackbar "Solde synchronisé" ? À tester UX.
- **Migration des packs `ownedPacks` legacy** : si un user a `culture_ci` en local mais le `catalog/index` ne l'a plus, on garde ou on droppe ? **Recommandation** : garder (rétrocompat).

---

**Auteur** : Claude + Arnaud, juin 2026
**Statut** : à valider avant implémentation Phase 4.2+
