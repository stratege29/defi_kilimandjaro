/// Chemins centralisés des assets images. Toute référence d'asset dans le
/// code passe par ici — jamais de string en dur.
abstract final class AppAssets {
  static const _brand = 'assets/images/brand';
  static const _tiles = 'assets/images/tiles';
  static const _buttons = 'assets/images/buttons';
  static const _icons = 'assets/images/icons';
  static const _backgrounds = 'assets/images/backgrounds';
  static const _mountains = 'assets/images/mountains';
  static const _devinettes = 'assets/images/devinettes';
  static const _ornaments = 'assets/images/ornaments';
  static const _fx = 'assets/images/fx';
  static const _badges = 'assets/images/badges';
  static const _shop = 'assets/images/shop';
  static const _duel = 'assets/images/duel';
  static const _packs = 'assets/images/packs';

  /// Dossier contenant les PNG du catalogue d'avatars (cf. `AvatarCatalog`).
  /// Référencé via `'${AppAssets.avatarsDir}/<id>.png'` dans chaque `Avatar`.
  static const String avatarsDir = 'assets/images/avatars';

  static const _kili = 'assets/kili';

  // --- Mascotte Kili (margouillat, remplace le griot) ---
  /// Corps complet, pose neutre. Héros de la page Grimper (`KiliMascot`).
  static const String kiliBody = '$_kili/kili.png';

  /// Découpe tête seule, pivote sur le cou (rig 2 calques `KiliMascot`).
  static const String kiliHead = '$_kili/kili_head.png';

  /// Pose « peek » : pattes agrippées à une rampe, tête qui dépasse,
  /// vue légèrement plongeante. Carte devinette en jeu.
  static const String kiliPeek = '$_kili/kili_peek.png';

  /// Variante de [kiliPeek] avec la rampe recolorée en or (au lieu du gris/
  /// beige d'origine) — pour poser Kili directement sur une surface dorée
  /// (CTA GRIMPER) sans rupture de teinte entre l'illustration et le fond.
  static const String kiliPeekGold = '$_kili/kili_peek_gold.png';

  /// Vue plongeante, pattes écartées façon escalade de paroi. Overlay de
  /// mise en garde d'ascension (pente qui se raidit / boss).
  static const String kiliClimb = '$_kili/kili_climb.png';

  /// Pouce levé, yeux pétillants (cœurs/étoiles). Carte d'accueil.
  static const String kiliCheer = '$_kili/kili_cheer.png';

  /// Roulé en boule, endormi. Lobby duel en attente d'adversaire.
  static const String kiliSleep = '$_kili/kili_sleep.png';

  /// Tête seule, cadrage serré, grand sourire. Avatar profil (fallback rond).
  static const String kiliFace = '$_kili/kili_face.png';

  /// Assis, patte sur la tête, larme — déception. Écran d'échec.
  static const String kiliSad = '$_kili/kili_sad.png';

  /// Debout, bras qui pointe vers l'avenir. Onboarding étape 2 (ascension).
  static const String kiliPoint = '$_kili/kili_point.png';

  // --- Brand ---
  static const String appIcon = '$_brand/app_icon.png';
  static const String logoK = '$_brand/logo_k.png';
  static const String splashBackground = '$_brand/splash_background.png';
  static const String splashPulse = '$_brand/splash_pulse.png';

  // --- Tuiles ---
  static const String tileNormal = '$_tiles/tile_normal.png';
  static const String tileSelected = '$_tiles/tile_selected.png';
  static const String tileValidated = '$_tiles/tile_validated.png';

  // --- Boutons ---
  static const String buttonPrimary = '$_buttons/button_primary.png';
  static const String buttonSecondary = '$_buttons/button_secondary.png';
  static const String buttonDanger = '$_buttons/button_danger.png';
  static const String buttonDisabled = '$_buttons/button_disabled.png';
  static const String buttonRound = '$_buttons/button_round.png';

  /// Cadre rond bois pour avatar de profil.
  static const String avatarFrame = '$_buttons/avatar_frame.png';

  // --- Icônes UI ---
  // NB : les fichiers PNG conservent leur nom `coin*.png` côté assets/
  // pour ne pas dupliquer la planche illustrative — seuls les identifiants
  // Dart suivent le rebranding Cauris.
  static const String iconCauris = '$_icons/coin.png';
  static const String iconCaurisStack = '$_icons/coin_stack.png';
  static const String iconHint = '$_icons/hint_kola.png';
  static const String iconErase = '$_icons/erase_broom.png';
  // iconValidate retiré — auto-validation au mot complet rend le bouton
  // « Valider » superflu (cf. refonte gameplay : 3 boutons → Pub/Indice/Effacer).
  // L'asset validate_check.png est conservé dans /assets/icons/ au cas où
  // un futur mode (ex. duel manuel) en aurait besoin.
  static const String iconLock = '$_icons/lock.png';
  static const String iconStreak = '$_icons/streak_flame.png';
  static const String iconStreakBroken = '$_icons/streak_broken.png';
  static const String iconAudioOn = '$_icons/audio_on.png';
  static const String iconAudioOff = '$_icons/audio_off.png';
  static const String iconNavPlay = '$_icons/nav_play.png';
  static const String iconNavMap = '$_icons/nav_map.png';
  static const String iconNavProfile = '$_icons/nav_profile.png';

  // --- Backgrounds ---
  static const String bgHub = '$_backgrounds/hub.png';
  static const String bgMountainAscent = '$_backgrounds/mountain_ascent.png';
  static const String bgAfricaMap = '$_backgrounds/africa_map.png';
  static const String parchmentCard = '$_backgrounds/parchment_card.png';

  // --- Montagnes ---
  static String mountainBiome(int tier) => '$_mountains/biome_$tier.png';
  static String mountainHero(String id) => '$_mountains/hero_$id.png';
  static const String kilimandjaroHero = '$_mountains/hero_tz_kilimanjaro.png';

  // --- Devinettes (sujets, clé = answer_normalized) ---
  static String devinetteSubject(String key) => '$_devinettes/$key.png';

  // --- Ornements & FX ---
  static const String adinkraSheet = '$_ornaments/adinkra_sheet.png';
  static const String borderHorizontal = '$_ornaments/border_horizontal.png';
  static const String cornerOrnament = '$_ornaments/corner.png';
  static const String bogolanBand = '$_ornaments/bogolan_band.png';
  static const String kenteBand = '$_ornaments/kente_band.png';
  static const String sunburst = '$_ornaments/sunburst.png';

  static const String fxParticleGold = '$_fx/particle_gold.png';
  static const String fxConfettiKente = '$_fx/confetti_kente.png';
  static const String fxGlow = '$_fx/glow_disc.png';
  static const String fxMist = '$_fx/mist_puff.png';

  // --- Badges titres honorifiques ---
  static const String badgeOreille = '$_badges/oreille_du_village.png';
  static const String badgeGardien = '$_badges/gardien_de_la_parole.png';
  static const String badgeGriot = '$_badges/griot_du_feu.png';
  static const String badgeAncetre = '$_badges/ancetre_vivant.png';

  // --- Shop ---
  /// Planche composite (calebasses + coffres + trône + No-Ads) — utilisée
  /// comme illustration hero du Shop tant que les visuels individuels
  /// L1-L6 ne sont pas générés.
  static const String shopPackSheet = '$_shop/shop_pack_sheet.png';
  static const String shopCaurisS = '$_shop/coins_s.png';
  static const String shopCaurisM = '$_shop/coins_m.png';
  static const String shopCaurisL = '$_shop/coins_l.png';
  static const String shopCaurisXL = '$_shop/coins_xl.png';
  static const String shopCaurisMega = '$_shop/coins_mega.png';
  static const String shopNoAds = '$_shop/no_ads.png';

  // --- Packs (icônes thématiques du catalogue) ---
  /// Illustration carrée d'un pack (ex. `culture_ci.png`). Tous les packs
  /// n'ont pas forcément d'asset — prévoir un fallback (`errorBuilder`).
  static String packIcon(String id) => '$_packs/$id.png';

  // --- Duel ---
  static const String duelVsBanner = '$_duel/vs_banner.png';
  static const String duelLobby = '$_duel/lobby_drum.png';
  static const String duelTrophy = '$_duel/trophy_elo.png';
}
