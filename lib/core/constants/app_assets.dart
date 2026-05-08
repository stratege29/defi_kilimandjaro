/// Chemins centralisés des assets images. Toute référence d'asset dans le
/// code passe par ici — jamais de string en dur.
abstract final class AppAssets {
  static const _mascot = 'assets/images/mascot';
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

  // --- Mascotte griot (turban bleu, halo jaune) ---
  /// Pose neutre / approbation (clin d'œil + pouce levé). Carte devinette, HUD.
  static const String griotIdle = '$_mascot/griot_idle.png';

  /// Pose victoire (poings levés en triomphe). Écran 04 Victoire.
  static const String griotVictory = '$_mascot/griot_victory.png';

  /// Pose réflexion / indice (index levé + main sur cœur). Bouton Indice, tooltip.
  static const String griotHint = '$_mascot/griot_hint.png';

  /// Pose narration / guidance (pointe du doigt). Onboarding, tutoriels.
  static const String griotPoint = '$_mascot/griot_point.png';

  /// Pose célébration ouverte (bras grands ouverts). Écran d'accueil, fanfare.
  static const String griotWelcome = '$_mascot/griot_welcome.png';

  /// Pose consolation (à générer — voir asset bible B4).
  static const String griotSad = '$_mascot/griot_sad.png';

  /// Pose hero sommet Kilimandjaro (à générer — voir asset bible B6).
  static const String griotSummit = '$_mascot/griot_summit.png';

  /// Bulle de dialogue (queue vers le haut). Pour les tooltips au-dessus du griot.
  static const String speechBubbleUp = '$_mascot/speech_bubble_up.png';

  /// Bulle de dialogue (queue vers le bas). Pour les tooltips en dessous du griot.
  static const String speechBubbleDown = '$_mascot/speech_bubble_down.png';

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
  static const String iconCoin = '$_icons/coin.png';
  static const String iconCoinStack = '$_icons/coin_stack.png';
  static const String iconHint = '$_icons/hint_kola.png';
  static const String iconErase = '$_icons/erase_broom.png';
  static const String iconValidate = '$_icons/validate_check.png';
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
  static const String shopCoinsS = '$_shop/coins_s.png';
  static const String shopCoinsM = '$_shop/coins_m.png';
  static const String shopCoinsL = '$_shop/coins_l.png';
  static const String shopCoinsXL = '$_shop/coins_xl.png';
  static const String shopCoinsMega = '$_shop/coins_mega.png';
  static const String shopNoAds = '$_shop/no_ads.png';

  // --- Duel ---
  static const String duelVsBanner = '$_duel/vs_banner.png';
  static const String duelLobby = '$_duel/lobby_drum.png';
  static const String duelTrophy = '$_duel/trophy_elo.png';
}
