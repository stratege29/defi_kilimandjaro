import 'package:defi_kilimandjaro/audio/audio_engine.dart';
import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_theme.dart';
import 'package:defi_kilimandjaro/data/ads/ads_service.dart';
import 'package:defi_kilimandjaro/data/iap/iap_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await AudioEngine.instance.init();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // IAP and Ads init are fire-and-forget; failures go silent.
      ref.read(iapServiceProvider).init();
      ref.read(adsServiceProvider).init();
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
