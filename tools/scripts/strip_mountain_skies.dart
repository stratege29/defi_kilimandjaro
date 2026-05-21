// Strip sky/atmosphere elements from mountain SVGs so they overlay cleanly
// on top of the existing `AtmosphereLayer` + `ParallaxBgLayer`.
//
// What is removed:
//   - <defs> blocks (sky gradient definitions)
//   - <rect width="200" height="200" .../>  (sky background fill)
//   - <rect y="..." width="200" height="..." opacity=".."/>  (haze layers)
//   - <circle cy="X" .../>  where X < 80  (sun + stars in sky region)
//   - <polygon ... opacity="0.X"/>  where X ≤ 7  (distant ridges that would
//     conflict with ParallaxBgLayer)
//
// What is preserved:
//   - Main mountain silhouettes (faceted polygons, no opacity)
//   - Snow / glaciers / lava signatures (opacity ≥ 0.8 or no opacity)
//   - All <ellipse> (panaches Karthala/Fogo, cloud caps signature, palm crowns)
//   - All <line> (palm trunks, stratification)
//   - Foreground vegetation (acacias, baobabs, sand, beach)
//   - The original viewBox 0 0 200 200
//
// Originals are preserved in tools/mountain_samples/v2/  — this script only
// rewrites the copies inside assets/svg/mountains/.
//
// Run:  dart run tools/scripts/strip_mountain_skies.dart

import 'dart:io';

void main() {
  final dir = Directory('assets/svg/mountains');
  if (!dir.existsSync()) {
    stderr.writeln('✗ Directory not found: ${dir.path}');
    exit(1);
  }

  final svgs = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.svg'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (svgs.isEmpty) {
    stderr.writeln('✗ No .svg files in ${dir.path}');
    exit(1);
  }

  print('Stripping ${svgs.length} mountain SVGs...');
  var changed = 0;

  for (var i = 0; i < svgs.length; i++) {
    final file = svgs[i];
    final original = file.readAsStringSync();
    final stripped = _strip(original);

    final beforeSize = original.length;
    final afterSize = stripped.length;
    final reduction = beforeSize == 0
        ? 0
        : ((1 - afterSize / beforeSize) * 100).round();

    if (stripped != original) {
      file.writeAsStringSync(stripped);
      changed++;
    }

    final name = file.uri.pathSegments.last;
    print('  ${(i + 1).toString().padLeft(2)}/${svgs.length}  '
        '$name  (-${reduction.toString().padLeft(2)}%)');
  }

  print('');
  print('✓ Stripped $changed/${svgs.length} SVGs');
  print('  Now run: ./tools/scripts/compile_mountains.sh');
}

String _strip(String svg) {
  var s = svg;

  // 1. Remove <defs>...</defs> (gradient definitions).
  s = s.replaceAll(
    RegExp(r'<defs>[\s\S]*?</defs>\s*', multiLine: true),
    '',
  );

  // 2. Remove the full-viewport sky <rect>.
  s = s.replaceAll(
    RegExp(
      r'\s*<rect width="200" height="200" fill="(?:url\(#[^)]*\)|#[A-Fa-f0-9]+)"\s*/>',
    ),
    '',
  );

  // 3. Remove haze layer <rect>s (have opacity attr).
  s = s.replaceAll(
    RegExp(
      r'\s*<rect y="\d+" width="200" height="\d+" fill="[^"]+" opacity="[^"]+"\s*/>',
    ),
    '',
  );

  // 4. Remove <circle> with cy < 80 (sun + stars in sky area).
  s = s.replaceAllMapped(
    RegExp(r'\s*<circle cx="\d+(?:\.\d+)?" cy="(\d+(?:\.\d+)?)"[^/]*/>'),
    (m) {
      final cy = double.parse(m.group(1)!);
      return cy < 80 ? '' : m.group(0)!;
    },
  );

  // 5. Remove <polygon> with opacity ≤ 0.75 (distant ridges).
  s = s.replaceAllMapped(
    RegExp(r'\s*<polygon[^>]*opacity="(0\.\d+)"[^>]*/>'),
    (m) {
      final op = double.parse(m.group(1)!);
      return op <= 0.75 ? '' : m.group(0)!;
    },
  );

  // 6. Collapse multiple blank lines (from removals).
  s = s.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');

  return s;
}
