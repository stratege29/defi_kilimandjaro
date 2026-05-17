import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/firebase_options.dart';
import 'package:kilimandjaro_admin/src/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
