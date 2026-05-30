import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kilimandjaro_admin/src/app/router.dart';

/// Coque de l'app authentifiée : NavigationRail à gauche + content à droite.
///
/// Sections actuelles :
///   - Modération (existant — submissions UGC)
///   - Catalogue (Phase 2 — packs + devinettes)
///
/// La sélection du rail se base sur `currentLocation` pour rester en sync avec
/// l'URL (back/forward navigateur, deep-links).
class RootShell extends StatelessWidget {
  const RootShell({
    required this.currentLocation,
    required this.child,
    super.key,
  });

  final String currentLocation;
  final Widget child;

  int get _selectedIndex {
    if (currentLocation.startsWith(AdminRoutes.catalog) ||
        currentLocation.startsWith('/pack/')) {
      return 1;
    }
    return 0; // moderation par défaut
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) {
              if (i == 0) context.go(AdminRoutes.moderation);
              if (i == 1) context.go(AdminRoutes.catalog);
            },
            labelType: NavigationRailLabelType.all,
            leading: const _Logo(),
            trailing: Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (user != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Tooltip(
                        message: user.email ?? user.uid,
                        child: CircleAvatar(
                          radius: 16,
                          backgroundImage: user.photoURL != null
                              ? NetworkImage(user.photoURL!)
                              : null,
                          child: user.photoURL == null
                              ? const Icon(Icons.person, size: 18)
                              : null,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Déconnexion',
                    onPressed: () => FirebaseAuth.instance.signOut(),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.gavel_outlined),
                selectedIcon: Icon(Icons.gavel),
                label: Text('Modération'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.library_books_outlined),
                selectedIcon: Icon(Icons.library_books),
                label: Text('Catalogue'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFD2A24C),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'K',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}
