import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/core/deep_links.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_theme.dart';
import 'package:defi_kilimandjaro/data/ads/ads_service.dart';
import 'package:defi_kilimandjaro/data/ads/consent_service.dart';
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

/// Navigue vers la route duel deep-link a partir du payload FCM.
///
/// Utilise [appRouterNavigatorKey] pour acceder au Navigator sans BuildContext.
void _navigateToMatchFromFcm(RemoteMessage message) {
  final matchId = message.data['matchId'] as String?;
  final type = message.data['type'] as String?;
  if (matchId == null || matchId.isEmpty) return;
  if (type != 'duel_challenge') return;

  // Utilise la route deep-link existante /duel/join/:matchId.
  final context = appRouterNavigatorKey.currentContext;
  if (context == null) return;
  GoRouter.of(context).go(AppRoutes.duelJoinPath(matchId));
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
  await AudioEngine.instance.init();
  // ignore: avoid_print
  print('[BOOT] 3 AudioEngine OK');

  // Firebase: initialize then ensure an anonymous session exists so
  // every player has a UID for duels even before signing in with
  // Google/Apple (Phase 6.1+).
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

    // App Check: must run right after Firebase.initializeApp and before any
    // authenticated call (Auth, Firestore, RTDB, Cloud Functions).
    await activateAppCheck();

    // Remote Config : économie + ad fréquences + killswitch. Fail-soft —
    // si le fetch échoue, les defaults baked-in restent actifs.
    await _remoteConfig.init();

    // Local emulator wiring — opt-in via --dart-define USE_FIREBASE_EMULATOR=true
    // (cf. README emulator section). Doit être appelé AVANT toute requête
    // Firestore/RTDB/Functions et AVANT signInAnonymously.
    // Chaque appel est isolé pour ne pas tuer le boot si l'emulator est
    // injoignable.
    const useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
    if (useEmulator) {
      const emulatorHost = String.fromEnvironment(
        'EMULATOR_HOST',
        defaultValue: 'localhost',
      );
      // ignore: avoid_print
      print('🔧 Wiring Firebase emulators to $emulatorHost');
      try {
        FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
      } catch (e) {
        // ignore: avoid_print
        print('🔧 Firestore emulator wire failed: $e');
      }
      try {
        FirebaseDatabase.instance.useDatabaseEmulator(emulatorHost, 9000);
      } catch (e) {
        // ignore: avoid_print
        print('🔧 Database emulator wire failed: $e');
      }
      try {
        FirebaseFunctions.instanceFor(
          region: 'europe-west1',
        ).useFunctionsEmulator(emulatorHost, 5001);
      } catch (e) {
        // ignore: avoid_print
        print('🔧 Functions emulator wire failed: $e');
      }
      try {
        await FirebaseAuth.instance
            .useAuthEmulator(emulatorHost, 9099)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        // ignore: avoid_print
        print('🔧 Auth emulator wire failed/timeout: $e');
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
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );

    // En mode emulator, on force un fresh sign-in pour invalider tout
    // token cached d'une session prod précédente (qui ferait rejeter les
    // requêtes Firestore avec permission-denied).
    if (useEmulator && FirebaseAuth.instance.currentUser != null) {
      try {
        await FirebaseAuth.instance.signOut();
        // ignore: avoid_print
        print('🔧 Emulator mode: signed out previous user (likely prod token)');
      } catch (e) {
        // ignore: avoid_print
        print('🔧 signOut failed: $e');
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

    // FCM : enregistrer le handler background AVANT toute autre init FCM.
    // Doit etre appele ici (avant runApp) pour que le plugin le connaisse
    // au demarrage de l'isolat background.
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

    // FCM : handler quand l'utilisateur tape sur une notif depuis background.
    FirebaseMessaging.onMessageOpenedApp.listen(_navigateToMatchFromFcm);

    // FCM : verifier si l'app a ete ouverte depuis une notif (app terminee).
    // Timeout 3s — getInitialMessage() peut hanger indéfiniment sur iOS si
    // APNs n'est pas encore prêt (cas typique : 1er lancement en TestFlight
    // sans embedded.mobileprovision). On accepte de rater le deep-link plutôt
    // que de bloquer le splash.
    try {
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 3));
      if (initialMessage != null) {
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            _navigateToMatchFromFcm(initialMessage);
          }),
        );
      }
    } on Object {
      // Timeout ou erreur FCM — l'app boot quand même.
    }
    // ignore: avoid_print
    print('[BOOT] 4 Firebase block OK');
  } catch (e) {
    // Fail-soft: solo gameplay continues without backend if Firebase fails.
    // ignore: avoid_print
    print('[BOOT] 4 Firebase bootstrap failed: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  // ignore: avoid_print
  print('[BOOT] 5 SharedPreferences OK');

  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemOverlay);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // ignore: avoid_print
  print('[BOOT] 6 SystemChrome OK — calling runApp');

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
      unawaited(
        ref.read(walletSyncCoordinatorProvider).reconcileOnLogin().whenComplete(
              () => ref
                  .read(progressSyncCoordinatorProvider)
                  .restoreAndBackup(),
            ),
      );

      // FCM token storage (permission + persistance Firestore).
      // Fire-and-forget : ne doit pas bloquer le boot.
      unawaited(ref.read(fcmRepositoryProvider).init());
      // ignore: avoid_print
      print('[BOOT] 9 FCM triggered');

      // FCM foreground : notif in-app quand un duel challenge arrive.
      _fcmForegroundSub = FirebaseMessaging.onMessage.listen(
        _onForegroundMessage,
      );
      // ignore: avoid_print
      print('[BOOT] 10 FCM listener attached');

      // UMP consent before AdMob (RGPD UE compliance).
      await ref.read(consentServiceProvider).requestConsent();
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

  /// Affiche une snackbar discrete quand un defi arrive en premier plan.
  void _onForegroundMessage(RemoteMessage message) {
    if (!mounted) return;
    final matchId = message.data['matchId'] as String?;
    final type = message.data['type'] as String?;
    if (matchId == null || type != 'duel_challenge') return;

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
