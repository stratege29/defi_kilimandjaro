# Google Play — Data Safety form (Kilimandjaro)

> Référence à reporter dans Play Console → App content → Data safety.
> Source de vérité : iOS [`PrivacyInfo.xcprivacy`](../ios/Runner/PrivacyInfo.xcprivacy)
> et le code source (Auth/Firestore/RTDB, Crashlytics, AdMob, IAP).
> Cf. plan.md §4 (Phase 4 — Monétisation).

**Dernière mise à jour** : 2026-05-22 (synchronisé avec Privacy Manifest iOS).

---

## 1. Data collection & sharing — réponses globales

| Question Play Console | Réponse |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (HTTPS / TLS sur tous les endpoints Firebase + AdMob) |
| Do you provide a way for users to request that their data be deleted? | **Yes** — depuis l'écran Profil → "Réinitialiser ma progression" (efface SharedPreferences + reset Firestore profile via Cloud Function `endMatch` cleanup). |

---

## 2. Data types — détail par catégorie

Pour chaque type ci-dessous, Play Console demande : **(a)** collected/shared, **(b)** purposes, **(c)** optional.

### 2.1 Personal info → User IDs
- **Collected** : Yes
- **Shared** : No
- **Optional** : No (anonyme par défaut, mais l'UID est requis pour le mode Défi)
- **Purposes** :
  - App functionality (matchmaking ELO + persistance progression Firestore)
- **Source code** :
  - `FirebaseAuth.signInAnonymously()` dans [`lib/main.dart`](../lib/main.dart)
  - UID stocké dans Firestore (`/profiles/{uid}`) — cf. [`profile_repository.dart`](../lib/data/repositories/profile_repository.dart)

### 2.2 Financial info → Purchase history
- **Collected** : Yes
- **Shared** : No
- **Optional** : Yes (uniquement si l'utilisateur achète un pack Cauris ou No-Ads)
- **Purposes** :
  - App functionality (validation IAP + entitlement No-Ads)
- **Source code** :
  - [`lib/data/iap/iap_service.dart`](../lib/data/iap/iap_service.dart)
  - Receipts traités localement par `in_app_purchase` + stockés via SharedPreferences (clé `player_progress.no_ads`).

### 2.3 App activity → App interactions
- **Collected** : Yes
- **Shared** : No (analytics interne Firebase uniquement)
- **Optional** : Yes — l'utilisateur peut révoquer le consentement EU via UMP.
- **Purposes** :
  - Analytics (Firebase Performance Monitoring — temps de rendu UI, latence Firestore)
  - App functionality (progression niveaux, streak quotidien)
- **Source code** :
  - Firebase Performance auto-instrumentation
  - `_progress.recordWin()` / `recordFailure()` dans [`player_progress_repository.dart`](../lib/data/repositories/player_progress_repository.dart)

### 2.4 App activity → In-app search history
- **Collected** : No

### 2.5 App activity → Other actions
- **Collected** : No (pas de tracking comportemental hors gameplay)

### 2.6 App info & performance → Crash logs
- **Collected** : Yes
- **Shared** : No
- **Optional** : No (collecte automatique Crashlytics en release)
- **Purposes** :
  - App functionality (debug crash → fix release)
- **Source code** :
  - `FirebaseCrashlytics.instance` dans [`lib/main.dart`](../lib/main.dart)
  - Désactivé en debug : `setCrashlyticsCollectionEnabled(!kDebugMode)`

### 2.7 App info & performance → Diagnostics
- **Collected** : Yes
- **Shared** : No
- **Optional** : No
- **Purposes** :
  - Analytics (Performance Monitoring)
- **Source code** : Firebase Performance auto-instrumentation.

### 2.8 App info & performance → Other app performance data
- **Collected** : Yes (mêmes données que Diagnostics)
- **Shared** : No
- **Optional** : No
- **Purposes** : Analytics + App functionality.

### 2.9 Device or other IDs
- **Collected** : Yes (AdMob ID publicitaire pour les pubs rewarded/interstitielles, sous réserve de consentement UMP)
- **Shared** : Yes (avec Google AdMob)
- **Optional** : Yes (révocable via UMP / Google account settings)
- **Purposes** :
  - Advertising or marketing (pubs rewarded "+50 Cauris" et interstitielles 1/N échecs)
  - Fraud prevention, security, and compliance (anti-fraud AdMob)
- **Source code** :
  - [`lib/data/ads/ads_service.dart`](../lib/data/ads/ads_service.dart) + [`consent_service.dart`](../lib/data/ads/consent_service.dart)
  - Killswitch via Remote Config (`ads_killswitch`) — cf. [`game_economy_config.dart`](../lib/domain/entities/game_economy_config.dart)

---

## 3. Catégories explicitement NON collectées

À cocher comme **Not collected** dans Play Console :

- Location (precise OR approximate)
- Personal info → Name, Email, Address, Phone number, Race/Ethnicity, Political/Religious, Sexual orientation, Other PI
- Financial info → User payment info, Credit score, Other financial info *(seul `Purchase history` est collecté — anonyme)*
- Health & fitness → tout
- Messages → tout
- Photos and videos → tout
- Audio files → tout *(la synthèse audio est procédurale, jamais enregistrée)*
- Files and docs → tout
- Calendar → tout
- Contacts → tout
- Web browsing → tout

---

## 4. Security practices

- **Data encrypted in transit** : Yes (HTTPS forcé par Firebase SDK + AdMob)
- **You can request that data be deleted** : Yes (écran Profil → reset progression)
- **Committed to Play Families Policy** : Yes (le jeu est cible familiale, PEGI 3 attendu)
- **Independent security review** : No (sera Yes après audit pré-launch v1.0 S9-S10)

---

## 5. Checklist de soumission

- [ ] Saisir chacun des types ci-dessus dans Play Console
- [ ] Joindre le lien vers la politique de confidentialité publique (à publier sur kilimandjaro.app/privacy)
- [ ] Cocher "App not directed at children under 13" si on cible 13+ (à reconfirmer avec PO)
- [ ] Re-valider le formulaire après tout ajout de SDK tiers (Sentry, Adjust, …)
- [ ] Sync ce document si on ajoute/retire un type de donnée (cf. Privacy Manifest iOS)
