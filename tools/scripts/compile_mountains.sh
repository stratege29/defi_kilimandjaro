#!/usr/bin/env bash
# Compile les 52 SVG de montagnes en .vec binaire (vector_graphics_compiler).
#
# Pourquoi : SVG → binaire .vec = 5-10× plus rapide au runtime que parser XML,
# zéro cost-of-build du widget, GPU cache automatique. Indispensable quand on
# affiche plusieurs vignettes en grille (écran Sommets : 52 tuiles 80x80).
#
# Exécution : depuis la racine du projet :
#   ./tools/scripts/compile_mountains.sh
#
# Régénère après chaque modification d'un .svg source.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
SRC_DIR="$PROJECT_ROOT/assets/svg/mountains"

cd "$PROJECT_ROOT"

if [ ! -d "$SRC_DIR" ]; then
  echo "✗ Source dir not found: $SRC_DIR"
  exit 1
fi

shopt -s nullglob
svg_files=("$SRC_DIR"/*.svg)

if [ ${#svg_files[@]} -eq 0 ]; then
  echo "✗ No SVG files in $SRC_DIR"
  exit 1
fi

echo "Compiling ${#svg_files[@]} mountain SVG → .vec ..."

count=0
for svg in "${svg_files[@]}"; do
  vec="${svg}.vec"
  dart run vector_graphics_compiler -i "$svg" -o "$vec" --no-tessellate
  count=$((count + 1))
  filename=$(basename "$svg")
  printf "  [%2d/%d] %s\n" "$count" "${#svg_files[@]}" "$filename"
done

echo ""
echo "✓ Compiled $count SVG → .vec in $SRC_DIR"
echo ""
total_svg=$(du -sh "$SRC_DIR"/*.svg 2>/dev/null | awk '{sum+=$1} END {print sum"K"}')
total_vec=$(ls -la "$SRC_DIR"/*.vec 2>/dev/null | awk '{sum+=$5} END {printf "%.1fK\n", sum/1024}')
echo "  Sources .svg : ~$total_svg"
echo "  Compiled .vec: ~$total_vec"
