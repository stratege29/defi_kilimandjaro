/// Mappe l'altitude d'un sommet (en mètres) sur un niveau de difficulté
/// de devinette (1–5), selon l'option B validée par le PO.
///
/// Palier   | Altitude (m)  | Difficulté
/// -------- | ------------- | ----------
/// Plaine   | 0 – 499       | 1
/// Collines | 500 – 1 499   | 2
/// Massif   | 1 500 – 2 999 | 3
/// Haute    | 3 000 – 4 499 | 4
/// Sommet   | 4 500+        | 5
///
/// Utilisé dans [GameView._pushNextDevinette] et [MountainDetailView._onLevelTap]
/// pour alimenter [DevinetteSelectionService.nextDevinette].
int difficultyForAltitude(int altitudeMeters) {
  if (altitudeMeters < 500) return 1;
  if (altitudeMeters < 1500) return 2;
  if (altitudeMeters < 3000) return 3;
  if (altitudeMeters < 4500) return 4;
  return 5;
}
