import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/firebase_options.dart';
import 'package:kilimandjaro_admin/src/router.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sur le web, on force l'authDomain à correspondre au host courant pour
  // éviter le cross-domain OAuth bloqué par Safari ITP. Le chemin
  // `/__/auth/handler` est servi automatiquement par Firebase Hosting
  // pour tout site du même projet.
  final base = DefaultFirebaseOptions.currentPlatform;
  final options = kIsWeb
      ? FirebaseOptions(
          apiKey: base.apiKey,
          appId: base.appId,
          messagingSenderId: base.messagingSenderId,
          projectId: base.projectId,
          authDomain: web.window.location.host,
          databaseURL: base.databaseURL,
          storageBucket: base.storageBucket,
          measurementId: base.measurementId,
        )
      : base;
  await Firebase.initializeApp(options: options);
  runApp(
    const ProviderScope(child: AdminApp()),
  );
}

/// Root widget de la console (MaterialApp.router + thème).
class AdminApp extends StatelessWidget {
  /// Constructeur const standard.
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Kilimandjaro Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD2A24C),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: buildRouter(),
    );
  }
}
