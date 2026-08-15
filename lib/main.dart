import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/core/deep_links.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_theme.dart';
import 'package:defi_kilimandjaro/data/ads/ads_service.dart';
import 'package:defi_kilimandjaro/data/ads/att_service.dart';
import 'package:defi_kilimandjaro/data/ads/consent_service.dart';
import 'package:defi_kilimandjaro/data/firebase/analytics_service.dart';
import 'package:defi_kilimandjaro/data/firebase/app_check_setup.dart';
import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/iap/iap_service.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_pack_catalog_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/fcm_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/sync/progress_sync_service.dart';
import 'package:defi_kilimandjaro/data/wallet/wallet_sync.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/firebase_options.dart';
import 'package:defi_kilimandjaro/presentation/duel/incoming_challenge_listener.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// FCM background message handler — doit etre une fonction top-level.
// Appelee par le plugin quand l'app est terminee ou en arriere-plan.
// Ne doit pas appeler de code Flutter UI.
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // Firebase doit etre initialise dans l'isolat background.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Pas d'action UI ici — la navigation se fait dans onMessageOpenedApp.
}

/// Route l'app a partir du payload FCM quand l'utilisateur ouvre une notif.
///
/// Utilise [appRouterNavigatorKey] pour acceder au Navigator sans BuildContext.
/// - `duel_challenge`      → /duel/join/:matchId
/// - `pack_update`         → /my-packs (nouveau pack / contenu mis a jour)
/// - `tournament_reminder` → /tournaments/:tid (l'entree en arene est geree
///   automatiquement par TournamentDetailView si le tournoi est deja live)
void _handleFcmOpen(RemoteMessage message) {
  final type = message.data['type'] as String?;
  final context = appRouterNavigatorKey.currentContext;
  if (context == null) return;

  switch (type) {
    case 'duel_challenge':
      final matchId = message.data['matchId'] as String?;
      if (matchId == null || matchId.isEmpty) return;
      GoRouter.of(context).go(AppRoutes.duelJoinPath(matchId));
    case 'pack_update':
      GoRouter.of(context).go(AppRoutes.myPacks);
    case 'tournament_reminder':
      final tid = message.data['tournament_id'] as String?;
      if (tid == null || tid.isEmpty) return;
      GoRouter.of(context).go(AppRoutes.tournamentDetailPath(tid));
  }
}

Future<void> main() async {
  // All boot work runs in a guarded zone so any uncaught async error
  // ends up in Crashlytics (when available).
  await runZonedGuarded(_bootstrap, (error, stack) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('Uncaught zone error: $error');
    } else {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}

/// Instance partagée Remote Config — créée tôt pour pouvoir override le
/// provider Riverpod avec, après que `init()` ait fetch les valeurs.
/// Lecture des defaults garantie même si `init()` n'a pas tourné.
final RemoteConfigService _remoteConfig = RemoteConfigService();

/// Service analytics partagé — créé tôt pour pouvoir poser la user property
/// de variante A/B dès le boot (après résolution Remote Config) et override
/// le provider Riverpod. No-op si Firebase n'est pas initialisé.
final AnalyticsService _analytics =
    FirebaseAnalyticsService(FirebaseAnalytics.instance);

/// Signale que la session Firebase Auth est prête (anonyme ou existante).
///
/// Le sign-in a lieu APRÈS `runApp` (cf. [_deferredBoot]) : tout ce qui a
/// besoin d'un uid doit donc attendre ce future au lieu de lire
/// `FirebaseAuth.instance.currentUser` directement au boot, sinon le travail
/// part avec `uid == null` et se transforme silencieusement en no-op (cas
/// vécu : le token FCM n'était plus enregistré).
///
/// Toujours complété — y compris si le sign-in échoue ou timeout — pour ne
/// jamais laisser un consommateur suspendu.
final Completer<void> _authReadyCompleter = Completer<void>();
Future<void> get authReady => _authReadyCompleter.future;

/// Emulateurs locaux — opt-in via `--dart-define USE_FIREBASE_EMULATOR=true`.
const _useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
const _emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: 'localhost',
);

Future<void> _bootstrap() async {
  // [BOOT] timeline via print() — visible dans Xcode console (debug + flutter run).
  // ignore: avoid_print
  print('[BOOT] 0 _bootstrap entered');
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: avoid_print
  print('[BOOT] 1 WidgetsFlutterBinding OK');

  // Remplace l'ecran blanc (par defaut Flutter en release quand un widget
  // throw) par un fallback visible. L'erreur est aussi loggee via
  // FlutterError.onError → Crashlytics. Permet aux utilisateurs de savoir
  // que quelque chose s'est mal passe et de relancer l'app, plutot que
  // de rester sur un ecran vide en croyant que l'app est figee.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return _AppErrorWidget(details: details);
  };
  await EasyLocalization.ensureInitialized();
  // ignore: avoid_print
  print('[BOOT] 2 EasyLocalization OK');

  // Firebase core : initialisation LOCALE uniquement (aucun appel réseau),
  // requise avant tout provider qui touche Firestore/Functions.
  //
  // Tout le reste du boot (audio, App Check, sign-in anonyme, Remote Config,
  // message FCM initial) est déplacé APRÈS runApp — cf. [_deferredBoot].
  // Chacune de ces étapes faisait un aller-retour réseau ici même : tant que
  // la chaîne n'avait pas rendu la main, runApp n'était pas appelé et Flutter
  // ne pouvait afficher AUCUNE frame — l'utilisateur restait sur le splash
  // natif figé (jusqu'à ~20 s de timeouts cumulés sur réseau dégradé).
  // Ne PAS ré-introduire d'await réseau dans cette fonction.
  try {
    // Native plugins (e.g. firebase_messaging on iOS) may auto-initialize the
    // default app from GoogleService-Info.plist before Dart gets here, which
    // makes initializeApp() throw [core/duplicate-app]. Catch that specific
    // case so the rest of the bootstrap (App Check, emulators, auth) still
    // runs. Any other error is re-thrown into the outer catch.
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
      // ignore: avoid_print
      print('🔧 Firebase default app already exists (native auto-init) — OK');
    }

    // Emulateurs locaux (cf. README) : câblage SYNCHRONE, sans réseau. Doit
    // précéder toute requête Firestore/RTDB/Functions, donc rester ici — les
    // providers peuvent émettre dès la première frame. Le câblage Auth, lui,
    // est awaité (5 s) : il part dans [_deferredBoot], juste avant le sign-in.
    if (_useEmulator) {
      // ignore: avoid_print
      print('🔧 Wiring Firebase emulators to $_emulatorHost');
      try {
        FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
      } catch (e) {
        // ignore: avoid_print
        print('🔧 Firestore emulator wire failed: $e');
      }
      try {
        FirebaseDatabase.instance.useDatabaseEmulator(_emulatorHost, 9000);
      } catch (e) {
        // ignore: avoid_print
        print('🔧 Database emulator wire failed: $e');
      }
      try {
        FirebaseFunctions.instanceFor(
          region: 'europe-west1',
        ).useFunctionsEmulator(_emulatorHost, 5001);
      } catch (e) {
        // ignore: avoid_print
        print('🔧 Functions emulator wire failed: $e');
      }
    }

    // Crashlytics: route Flutter framework errors to Firebase in release.
    // En debug on conserve le dump console (sinon cet override masque la
    // stack et toute erreur de build devient invisible au développement).
    FlutterError.onError = (errorDetails) {
      if (kDebugMode) FlutterError.presentError(errorDetails);
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    unawaited(
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode),
    );

    // FCM : enregistrer le handler background AVANT toute autre init FCM.
    // Doit etre appele ici (avant runApp) pour que le plugin le connaisse
    // au demarrage de l'isolat background.
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

    // FCM : handler quand l'utilisateur tape sur une notif depuis background.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmOpen);

    // ignore: avoid_print
    print('[BOOT] 3 Firebase core OK');
  } catch (e) {
    // Fail-soft: solo gameplay continues without backend if Firebase fails.
    // ignore: avoid_print
    print('[BOOT] 3 Firebase core failed: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  // ignore: avoid_print
  print('[BOOT] 4 SharedPreferences OK');

  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemOverlay);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // ignore: avoid_print
  print('[BOOT] 5 SystemChrome OK — calling runApp');

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('fr'), Locale('en')],
      path: 'assets/data/i18n',
      fallbackLocale: const Locale('fr'),
      // Force FR au premier lancement. Sans ça, easy_localization adopte la
      // locale système du device : un iPhone en EN affichait "Hint/Clear/
      // Validate" sur une UI où le reste (mountains, prompts, snackbars)
      // est en FR hardcodé. Cohérence > détection système.
      startLocale: const Locale('fr'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          remoteConfigServiceProvider.overrideWithValue(_remoteConfig),
          analyticsServiceProvider.overrideWithValue(_analytics),
          // Phase 3 : active le catalog remote (Firestore catalog/index)
          // en override du bundle-only par défaut. Le composite fait le
          // fallback bundle si remote indisponible. Pas de fetch au boot
          // (cf OTA v0.2) — il faut un refresh manuel pour récupérer le
          // remote la première fois.
          packCatalogRepositoryOverride,
        ],
        child: const _BootGate(child: KilimandjaroApp()),
      ),
    ),
  );

  // Le reste du boot part maintenant que l'arbre est monté : la première
  // frame Flutter n'attend plus le réseau.
  unawaited(_deferredBoot());
}

/// Boot réseau, hors du chemin critique de la première frame.
///
/// Ordre imposé : App Check DOIT précéder tout appel authentifié (Auth,
/// Firestore, RTDB, Functions), et le sign-in doit précéder tout ce qui a
/// besoin d'un uid — d'où le séquencement explicite ici plutôt qu'une rafale
/// de `unawaited`. Ce qui n'a aucune dépendance part en parallèle.
///
/// Entièrement fail-soft : le jeu solo tourne sans backend.
Future<void> _deferredBoot() async {
  // Audio : natif, sans réseau, mais `AVAudioSession.configure` + l'init
  // SoLoud coûtent plusieurs centaines de ms. Rien ne joue sur le splash.
  unawaited(AudioEngine.instance.init());

  try {
    // App Check : avant tout appel authentifié. Fait une attestation
    // DeviceCheck / Play Integrity + `getTokenResult()` — donc du réseau.
    await activateAppCheck();

    // Câblage Auth emulator (awaité, 5 s) — juste avant le sign-in.
    if (_useEmulator) {
      try {
        await FirebaseAuth.instance
            .useAuthEmulator(_emulatorHost, 9099)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        // ignore: avoid_print
        print('🔧 Auth emulator wire failed/timeout: $e');
      }

      // Fresh sign-in en mode emulator : invalide tout token cached d'une
      // session prod précédente (sinon Firestore rejette en permission-denied).
      if (FirebaseAuth.instance.currentUser != null) {
        try {
          await FirebaseAuth.instance.signOut();
          // ignore: avoid_print
          print('🔧 Emulator mode: signed out previous user (prod token)');
        } catch (e) {
          // ignore: avoid_print
          print('🔧 signOut failed: $e');
        }
      }
    }

    if (FirebaseAuth.instance.currentUser == null) {
      try {
        final cred = await FirebaseAuth.instance.signInAnonymously().timeout(
          const Duration(seconds: 8),
        );
        // ignore: avoid_print
        print('🔧 signInAnonymously OK uid=${cred.user?.uid}');
      } catch (e) {
        // ignore: avoid_print
        print('🔧 signInAnonymously failed/timeout: $e');
      }
    }
  } on Object catch (e) {
    // ignore: avoid_print
    print('[BOOT] deferred auth block failed: $e');
  } finally {
    // Toujours débloquer les consommateurs, même si l'auth a échoué : ils
    // gèrent déjà `uid == null` en no-op, un blocage serait pire.
    if (!_authReadyCompleter.isCompleted) _authReadyCompleter.complete();
    // ignore: avoid_print
    print('[BOOT] deferred: auth ready');
  }

  // Remote Config : économie + fréquences pub + killswitch. Les defaults
  // baked-in sont servis en attendant (cf. RemoteConfigService), et les
  // consommateurs lisent la config à l'entrée d'une session de jeu — donc
  // bien après ce point.
  await _remoteConfig.init();

  // Analytics : tague la variante A/B du scaling des sinks. Doit suivre la
  // résolution Remote Config pour taguer la bonne valeur.
  unawaited(_analytics.init());
  unawaited(
    _analytics.setSinkScalingVariant(
      enabled: _remoteConfig.current.sinkTierScalingEnabled,
    ),
  );

  // FCM : l'app a-t-elle été ouverte depuis une notif (app terminée) ?
  // Timeout 3 s — `getInitialMessage()` peut hanger indéfiniment sur iOS si
  // APNs n'est pas prêt (1er lancement TestFlight sans
  // embedded.mobileprovision). On accepte de rater le deep-link.
  try {
    final initialMessage = await FirebaseMessaging.instance
        .getInitialMessage()
        .timeout(const Duration(seconds: 3));
    if (initialMessage != null) {
      _handleFcmOpen(initialMessage);
    }
  } on Object {
    // Timeout ou erreur FCM — l'app tourne quand même.
  }
  // ignore: avoid_print
  print('[BOOT] deferred boot done');
}

/// Initialise les services lourds (IAP, FCM, deep links) apres que
/// ProviderScope soit disponible, sans bloquer le splash visuel.
class _BootGate extends ConsumerStatefulWidget {
  const _BootGate({required this.child});
  final Widget child;

  @override
  ConsumerState<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends ConsumerState<_BootGate> {
  StreamSubscription<RemoteMessage>? _fcmForegroundSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ignore: avoid_print
      print('[BOOT] 7 post-frame entered');

      // IAP init is fire-and-forget.
      unawaited(ref.read(iapServiceProvider).init());
      // ignore: avoid_print
      print('[BOOT] 8 IAP triggered');

      // Trace l'install date au 1er lancement (utilisé par la fenêtre
      // Starter Pack H+48). Idempotent si déjà set côté progress.
      unawaited(
        ref
            .read(playerProgressProvider.notifier)
            .ensureInstallDate(DateTime.now()),
      );

      // Sync cloud de la progression solo (récupération multi-appareil).
      // 1. Installe la sauvegarde debouncée (push 3 s après chaque gain).
      // 2. Réconcilie le wallet serveur (cauris + packs) puis restaure +
      //    repousse la progression solo. Fail-soft : n'affecte jamais le
      //    jeu offline. La restauration décisive a lieu après une
      //    (re)connexion de compte (cf. AccountController).
      ref.read(progressAutoBackupProvider);

      // Ces trois-là écrivent sous `{uid}` : ils DOIVENT attendre la session
      // Firebase, qui est maintenant établie après runApp. Sans ce gate ils
      // partiraient avec `uid == null` et deviendraient des no-ops muets.
      unawaited(
        authReady.then((_) {
          if (!mounted) return;
          unawaited(
            ref
                .read(walletSyncCoordinatorProvider)
                .reconcileOnLogin()
                .whenComplete(
                  () => ref
                      .read(progressSyncCoordinatorProvider)
                      .restoreAndBackup(),
                ),
          );
          // FCM token storage (permission + persistance Firestore).
          unawaited(ref.read(fcmRepositoryProvider).init());
          // ignore: avoid_print
          print('[BOOT] 9 wallet/progress/FCM triggered (auth ready)');
        }),
      );

      // FCM foreground : notif in-app quand un duel challenge arrive.
      _fcmForegroundSub = FirebaseMessaging.onMessage.listen(
        _onForegroundMessage,
      );
      // ignore: avoid_print
      print('[BOOT] 10 FCM listener attached');

      // UMP consent before AdMob (RGPD UE compliance).
      await ref.read(consentServiceProvider).requestConsent();
      if (!mounted) return;
      // App Tracking Transparency (iOS) — DOIT précéder l'init AdMob :
      // Apple (Guideline 2.1) exige le prompt avant toute collecte de
      // données traçables. Awaité pour que le SDK pub démarre seulement
      // après la réponse utilisateur. No-op Android / si déjà répondu.
      await ref.read(attServiceProvider).ensureRequested();
      if (!mounted) return;
      unawaited(ref.read(adsServiceProvider).init());

      // Deep links : ecoute les URL scheme kilimandjaro://duel/*
      unawaited(ref.read(deepLinkServiceProvider).init());
      // ignore: avoid_print
      print('[BOOT] 11 deep links triggered');

      // OTA content sync DÉSACTIVÉ TEMPORAIREMENT — suspect d'OOM iOS 26.
      // Réactiver après confirmation que ce n'est pas le coupable.
      //   unawaited(ref.read(manifestSyncServiceProvider).refresh());
      // ignore: avoid_print
      print('[BOOT] 12 OTA sync skipped (debug)');
    });
  }

  /// Affiche une snackbar discrete quand une notif arrive en premier plan.
  void _onForegroundMessage(RemoteMessage message) {
    if (!mounted) return;
    final type = message.data['type'] as String?;

    if (type == 'duel_challenge') {
      final matchId = message.data['matchId'] as String?;
      if (matchId == null || matchId.isEmpty) return;
      final title = message.notification?.title ?? 'Tu as un defi !';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(title),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Rejoindre',
            onPressed: () {
              GoRouter.of(context).go(AppRoutes.duelJoinPath(matchId));
            },
          ),
        ),
      );
    } else if (type == 'pack_update') {
      final title =
          message.notification?.title ?? 'Nouveau contenu disponible';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(title),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Voir',
            onPressed: () {
              GoRouter.of(context).go(AppRoutes.myPacks);
            },
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _fcmForegroundSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      IncomingChallengeListener(child: widget.child);
}

class KilimandjaroApp extends ConsumerWidget {
  const KilimandjaroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep DevinetteLocale aligned with easy_localization's active locale so
    // riddle/explanation/proverb getters resolve to the right language. Runs
    // on every locale change (build is triggered by EasyLocalization).
    DevinetteLocale.activeLang = context.locale.languageCode;

    return MaterialApp.router(
      title: 'Kilimandjaro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(appRouterProvider),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }
}

/// Widget de fallback affiche a la place d'un widget qui throw au build.
///
/// Sans ce widget custom, Flutter en release affiche un ecran VIDE quand
/// un widget throw (et un RedScreen en debug). L'utilisateur croit que
/// l'app est figee. Ici on affiche un message + bouton "Reessayer" qui
/// pop la route courante (souvent suffisant pour debloquer).
///
/// L'erreur reelle est dans Crashlytics via FlutterError.onError.
class _AppErrorWidget extends StatelessWidget {
  const _AppErrorWidget({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    // En release, on affiche un short token (type d'exception + 1ere
    // frame du stack) pour identifier rapidement la cause sans exposer
    // de data sensible. En debug, on dump toute l'exception.
    final exceptionType = details.exception.runtimeType.toString();
    final library = details.library ?? '';
    final firstFrame = _firstAppStackFrame(details.stack);
    final shortInfo = '$exceptionType @ ${library.isEmpty ? "?" : library}'
        '\n$firstFrame';
    return Material(
      color: const Color(0xFF0F2A14), // vertForet fallback (sans theme)
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Color(0xFFE0B341), // orSoleil fallback
                size: 56,
              ),
              const SizedBox(height: 16),
              const Text(
                'Une erreur est survenue',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFE0B341),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Reouvre l'app pour reessayer.\nL'erreur a ete signalee.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFE6D7B8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              // Diagnostic minimal (debug + release) : type d'exception +
              // premiere frame dans le code app. Necessaire pour identifier
              // la cause sans avoir a connecter Xcode console.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  kDebugMode ? '${details.exception}\n$firstFrame' : shortInfo,
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB8A98C),
                    fontSize: 11,
                    fontFamily: 'Courier',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Extrait la 1ere frame du stack qui pointe vers le code app
  /// (package:defi_kilimandjaro/...), pour identifier rapidement la source
  /// de l'exception. Ignore les frames Flutter/Dart internes.
  static String _firstAppStackFrame(StackTrace? stack) {
    if (stack == null) return '(no stack)';
    final lines = stack.toString().split('\n');
    for (final line in lines) {
      if (line.contains('package:defi_kilimandjaro/')) {
        // ex: "#3 _AvatarBadge.build (package:defi_kilimandjaro/.../profile_view.dart:332:42)"
        final trimmed = line.trim();
        // Garde max 100 chars pour rester lisible.
        return trimmed.length > 100
            ? '${trimmed.substring(0, 100)}...'
            : trimmed;
      }
    }
    return lines.isNotEmpty ? lines.first.trim() : '(no app frame)';
  }
}
