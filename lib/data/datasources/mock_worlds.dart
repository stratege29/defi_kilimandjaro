import 'package:defi_kilimandjaro/domain/entities/world.dart';

/// Données mock pour le Hub avant le branchement Firebase (Phase 4).
///
/// 4 mondes thématiques cf. plan.md §0 et maquette p.4.
const List<World> mockWorlds = [
  World(
    id: 'village_des_or',
    name: 'Village des Or',
    emoji: '🏘️',
    unlocked: true,
    completedLevels: 3,
    totalLevels: 50,
  ),
  World(
    id: 'foret_sacree',
    name: 'Forêt Sacrée',
    emoji: '🌳',
    unlocked: true,
    completedLevels: 0,
    totalLevels: 50,
  ),
  World(
    id: 'lagune_des_saveurs',
    name: 'Lagune des Saveurs',
    emoji: '🌊',
    unlocked: false,
    completedLevels: 0,
    totalLevels: 50,
    unlockCost: 200,
  ),
  World(
    id: 'monts_des_legendes',
    name: 'Monts des Légendes',
    emoji: '⛰️',
    unlocked: false,
    completedLevels: 0,
    totalLevels: 50,
    unlockCost: 500,
  ),
];
