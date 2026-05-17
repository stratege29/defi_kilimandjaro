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
import 'package:defi_kilimandjaro/data/iap/iap_service.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/fcm_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/firebase_options.dart';
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

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await AudioEngine.instance.init();

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

    // App Check: fire-and-forget pour ne PAS bloquer le boot. Si le
    // serveur Firebase App Check rame ou si l'app n'est pas encore
    // enregistrée côté console, on ne veut pas un splash forever — les
    // requêtes Firebase passeront sans token (mode unenforced) jusqu'à
    // ce que l'activation se termine en arrière-plan.
    //
    // Une fois App Check enforced en backend (post-stabilisation prod),
    // remettre `await` ici + ajouter un timeout de 5s avec fallback.
    unawaited(activateAppCheck());

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
    FlutterError.onError = (errorDetails) {
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
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // Delay pour laisser le router s'initialiser.
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          _navigateToMatchFromFcm(initialMessage);
        }),
      );
    }
  } catch (e) {
    // Fail-soft: solo gameplay continues without backend if Firebase fails.
    // ignore: avoid_print
    print('🔧 Firebase bootstrap failed: $e');
  }

  final prefs = await SharedPreferences.getInstance();

  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemOverlay);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

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
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
      // IAP init is fire-and-forget.
      unawaited(ref.read(iapServiceProvider).init());

      // FCM token storage (permission + persistance Firestore).
      // Fire-and-forget : ne doit pas bloquer le boot.
      unawaited(ref.read(fcmRepositoryProvider).init());

      // FCM foreground : notif in-app quand un duel challenge arrive.
      _fcmForegroundSub = FirebaseMessaging.onMessage.listen(
        _onForegroundMessage,
      );

      // AdMob + UMP désactivés en v0.1 — le formulaire de consent Google
      // boucle infiniment sur certains iPhone (WebView UMP qui re-exec
      // du JavaScript toutes les 200ms sans jamais se résoudre, observé
      // en prod sur iOS 26). Ré-activera en v0.2 après investigation
      // ou migration vers UMP Lite / une autre solution de consent.
      //
      //   await ref.read(consentServiceProvider).requestConsent();
      //   unawaited(ref.read(adsServiceProvider).init());

      // Deep links : ecoute les URL scheme kilimandjaro://duel/*
      unawaited(ref.read(deepLinkServiceProvider).init());

      // OTA content sync : télécharge les packs distants depuis Firebase
      // Storage et peuple le cache Drift. Fire-and-forget — les échecs
      // sont loggés mais l'app continue sur le starter pack bundlé.
      unawaited(ref.read(manifestSyncServiceProvider).refresh());
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
  Widget build(BuildContext context) => widget.child;
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
