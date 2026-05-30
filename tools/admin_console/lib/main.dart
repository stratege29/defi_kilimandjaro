import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kilimandjaro_admin/firebase_options.dart';
import 'package:kilimandjaro_admin/src/app/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Récupère le résultat d'un `signInWithRedirect` (cf SignInScreen).
  // Sur Web uniquement — sur les autres plateformes l'API n'existe pas.
  // No-op si on n'arrive pas d'un redirect OAuth (cas le plus fréquent).
  if (kIsWeb) {
    try {
      await FirebaseAuth.instance.getRedirectResult();
    } catch (_) {
      // Silencieux : si le redirect a échoué côté Google, on laisse
      // l'UI sign-in afficher l'erreur au prochain tap.
    }
  }

  runApp(
    const ProviderScope(child: AdminApp()),
  );
}

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(adminRouterProvider);
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
      routerConfig: router,
    );
  }
}
