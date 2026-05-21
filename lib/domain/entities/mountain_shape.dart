/// Archétype visuel d'un sommet africain.
///
/// Catégorie géomorphologique parsée depuis `mountains.json`. La silhouette
/// finale est rendue depuis `assets/svg/mountains/{id}.svg.vec` (dessin
/// spécifique à chaque sommet), mais cette enum reste disponible pour le
/// filtrage, le tri ou un éventuel fallback.
enum MountainShape {
  /// Volcan classique — cône symétrique avec sommet ponctuel.
  /// Ex: Mont Cameroun, Mont Kenya, Karthala, Pico do Fogo.
  cone,

  /// Sommet plat / massif tabulaire — plateau au faîte.
  /// Ex: Kilimandjaro (calotte neigeuse plate), Table Mountain (Tafelberg).
  plateau,

  /// Crête dentelée — ligne de faîte irrégulière et accidentée.
  /// Ex: Drakensberg, Atlas (Toubkal), Mulanje.
  crest,

  /// Dôme arrondi — massif en bosse douce.
  /// Ex: Maromokotro (Madagascar), Bintumani (Sierra Leone).
  dome,

  /// Aiguille/dent — pic effilé presque vertical.
  /// Ex: Hombori Tondo (Mali), Pico Basile.
  dent,

  /// Mesa / plateau bas trapézoïdal — table courte et large.
  /// Ex: Red Rocks (Gambie, 53 m), Otse Mountain (Botswana).
  mesa,
}
