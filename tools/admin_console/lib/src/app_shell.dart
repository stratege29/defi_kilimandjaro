import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kilimandjaro_admin/src/auth/auth_providers.dart';

/// Shell global : NavigationRail à gauche (Packs, Modération UGC),
/// header AppBar avec compte connecté + logout.
/// Shell global affiché autour des écrans authentifiés.
class AppShell extends ConsumerWidget {
  /// `child` est le sub-route rendu dans la zone principale.
  /// `location` est l'URL active utilisée pour highlighter le NavigationRail.
  const AppShell({required this.child, required this.location, super.key});

  /// Sub-route rendu dans la zone principale (à droite du rail).
  final Widget child;

  /// URL go_router active.
  final String location;

  static const _destinations = <_Dest>[
    _Dest(label: 'Packs', icon: Icons.layers, route: '/packs'),
    _Dest(
      label: 'Modération UGC',
      icon: Icons.shield_moon,
      route: '/moderation',
    ),
  ];

  int _selectedIndex(String location) {
    for (var i = 0; i < _destinations.length; i++) {
      if (location.startsWith(_destinations[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claims = ref.watch(adminClaimsProvider).valueOrNull;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kilimandjaro Admin'),
        actions: [
          if (claims != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.verified_user, size: 16),
                  label: Text(
                    '${claims.email ?? "?"} · ${claims.role ?? "(no role)"}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex(location),
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => context.go(_destinations[i].route),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Dest {
  const _Dest({required this.label, required this.icon, required this.route});
  final String label;
  final IconData icon;
  final String route;
}
