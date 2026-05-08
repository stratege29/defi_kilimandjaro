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
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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

    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } on Exception catch (_) {
    // Fail-soft: solo gameplay continues without backend if Firebase fails.
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
