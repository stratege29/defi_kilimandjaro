import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PackTheme.parseHexColor', () {
    test('parse #RRGGBB (alpha forcé à FF)', () {
      expect(PackTheme.parseHexColor('#FF0000'), const Color(0xFFFF0000));
    });

    test('parse sans dièse', () {
      expect(PackTheme.parseHexColor('00FF00'), const Color(0xFF00FF00));
    });

    test('parse #AARRGGBB', () {
      expect(PackTheme.parseHexColor('#8000FF00'), const Color(0x8000FF00));
    });

    test('retourne null sur entrée invalide / nulle / vide', () {
      expect(PackTheme.parseHexColor(null), isNull);
      expect(PackTheme.parseHexColor(''), isNull);
      expect(PackTheme.parseHexColor('xyz'), isNull);
      expect(PackTheme.parseHexColor('#12'), isNull);
    });
  });

  group('PackThemes.resolve', () {
    test('défaut reproduit la palette « Vert Nuit » historique', () {
      final t = PackThemes.resolve();
      expect(t, PackThemes.defaultTheme);
      // Garde anti-régression : les couleurs-clés == tokens actuels.
      expect(t.background, AppColors.vertForet);
      expect(t.tile, AppColors.bois);
      expect(t.tileSelected, AppColors.orJour);
      expect(t.path, AppColors.orSoleil);
      expect(t.validation, AppColors.success);
      expect(t.sommetsTint, isNull);
    });

    test('résout le skin dédié par convention d\'id de pack', () {
      expect(PackThemes.resolve(packId: 'culture_ci'), PackThemes.cultureCi);
      expect(
        PackThemes.resolve(packId: 'crack_nouchi'),
        PackThemes.crackNouchi,
      );
      expect(PackThemes.resolve(packId: 'football_ci'), PackThemes.footballCi);
    });

    test('themeId explicite prime sur la convention de packId', () {
      final t = PackThemes.resolve(
        packId: 'culture_ci',
        themeId: 'abidjan_neon',
      );
      expect(t.id, PackThemes.crackNouchi.id);
    });

    test('id inconnu → thème par défaut', () {
      expect(PackThemes.resolve(packId: 'inexistant'), PackThemes.defaultTheme);
      expect(
        PackThemes.resolve(themeId: 'inexistant'),
        PackThemes.defaultTheme,
      );
    });

    test('les overrides couleur remote sont appliqués sur le preset', () {
      final t = PackThemes.resolve(
        packId: 'culture_ci',
        overrides: const <String, String>{
          'accent': '#123456',
          'sommets_tint': '#654321',
        },
      );
      expect(t.accent, const Color(0xFF123456));
      expect(t.sommetsTint, const Color(0xFF654321));
      // Rôle non surchargé : conservé depuis le preset.
      expect(t.tile, PackThemes.cultureCi.tile);
      // L'id du preset est préservé.
      expect(t.id, PackThemes.cultureCi.id);
    });

    test('override invalide laisse la valeur du preset', () {
      final t = PackThemes.resolve(
        overrides: const <String, String>{'accent': 'pas-un-hex'},
      );
      expect(t.accent, PackThemes.defaultTheme.accent);
    });

    test('motif et forme de tuiles surchargent le preset', () {
      final t = PackThemes.resolve(
        packId: 'culture_ci', // preset adinkra / sculpted
        motifName: 'kente',
        tileShapeName: 'diamond',
      );
      expect(t.motif, PackMotif.kente);
      expect(t.tileShape, TileShape.diamond);
      // Les couleurs du preset restent intactes.
      expect(t.background, PackThemes.cultureCi.background);
    });

    test('motif/forme nuls ou inconnus laissent ceux du preset', () {
      final t = PackThemes.resolve(
        packId: 'crack_nouchi', // kita / rounded
        motifName: 'inconnu',
        tileShapeName: null,
      );
      expect(t.motif, PackThemes.crackNouchi.motif);
      expect(t.tileShape, PackThemes.crackNouchi.tileShape);
    });
  });

  group('PackTheme name parsers', () {
    test('motifFromName', () {
      expect(PackTheme.motifFromName('vagues'), PackMotif.vagues);
      expect(PackTheme.motifFromName('none'), PackMotif.none);
      expect(PackTheme.motifFromName(null), isNull);
      expect(PackTheme.motifFromName('xxx'), isNull);
    });

    test('tileShapeFromName', () {
      expect(PackTheme.tileShapeFromName('hex'), TileShape.hex);
      expect(PackTheme.tileShapeFromName(null), isNull);
      expect(PackTheme.tileShapeFromName('xxx'), isNull);
    });
  });
}
