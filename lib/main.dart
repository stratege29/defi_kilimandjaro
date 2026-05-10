import 'dart:async';

import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_theme.dart';
import 'package:defi_kilimandjaro/data/ads/ads_service.dart';
import 'package:defi_kilimandjaro/data/ads/consent_service.dart';
import 'package:defi_kilimandjaro/data/iap/iap_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/firebase_options.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  // All boot work runs in a guarded zone so any uncaught async error
  // ends up in Crashlytics (when available).
  await runZonedGuarded(_bootstrap, (error, stack) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('Uncaught zone error: $error');
    } else {
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: true,
      );
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
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

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
        FirebaseFunctions.instanceFor(region: 'europe-west1')
            .useFunctionsEmulator(emulatorHost, 5001);
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
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

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
        final cred = await FirebaseAuth.instance
            .signInAnonymously()
            .timeout(const Duration(seconds: 8));
        // ignore: avoid_print
        print('🔧 signInAnonymously OK uid=${cred.user?.uid}');
      } catch (e) {
        // ignore: avoid_print
        print('🔧 signInAnonymously failed/timeout: $e');
      }
    }
  } catch (e) {
    // Fail-soft: solo gameplay continues without backend if Firebase fails.
    // ignore: avoid_print
    print('🔧 Firebase bootstrap failed: $e');
  }

  final prefs = await SharedPreferences.getInstance();

  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemOverlay);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('fr'), Locale('en')],
      path: 'assets/data/i18n',
      fallbackLocale: const Locale('fr'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const _BootGate(child: KilimandjaroApp()),
      ),
    ),
  );
}

/// Initialise les services lourds (IAP) après que ProviderScope soit
/// disponible, sans bloquer le splash visuel.
class _BootGate extends ConsumerStatefulWidget {
  const _BootGate({required this.child});
  final Widget child;

  @override
  ConsumerState<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends ConsumerState<_BootGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // IAP init is fire-and-forget.
      unawaited(ref.read(iapServiceProvider).init());

      // UMP consent before AdMob (RGPD UE compliance).
      await ref.read(consentServiceProvider).requestConsent();
      if (!mounted) return;
      unawaited(ref.read(adsServiceProvider).init());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class KilimandjaroApp extends StatelessWidget {
  const KilimandjaroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Kilimandjaro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }
}
