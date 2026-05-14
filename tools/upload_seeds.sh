#!/usr/bin/env bash
#
# Upload seed packs to Firebase Storage and seed Firestore docs from
# build/seed_packs/manifests.json.
#
# Usage:
#   tools/upload_seeds.sh <bucket> [--dry-run]
#
# Example:
#   tools/upload_seeds.sh kilimandjaro-prod.appspot.com
#   tools/upload_seeds.sh kilimandjaro-dev.appspot.com --dry-run
#
# Prereqs:
#   - gcloud auth login + gcloud config set project <project>
#   - gsutil installed
#   - node >= 20 + tools/scripts/seed_firestore.mjs deps installed
#
# Side effects:
#   - copies build/seed_packs/**/*.gz -> gs://<bucket>/packs/v2/
#   - upserts Firestore docs under collection `packs` from each manifest
#     (URL field is rewritten with the actual public bucket URL).

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <bucket> [--dry-run]" >&2
  exit 64
fi

BUCKET="$1"
DRY_RUN=false
if [[ "${2:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEED_DIR="$REPO_ROOT/build/seed_packs"
MANIFEST="$SEED_DIR/manifests.json"

if [[ ! -d "$SEED_DIR" ]]; then
  echo "error: $SEED_DIR not found — build seeds first." >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "error: $MANIFEST not found." >&2
  exit 1
fi

echo "==> bucket: gs://$BUCKET"
echo "==> seed dir: $SEED_DIR"
echo "==> dry run: $DRY_RUN"

# 1. Upload .gz packs
GZ_COUNT=$(find "$SEED_DIR" -name "*.gz" | wc -l | tr -d ' ')
echo "==> found $GZ_COUNT .gz pack(s)"

if [[ "$DRY_RUN" == "false" ]]; then
  gsutil -m cp -r "$SEED_DIR"/**/*.gz "gs://$BUCKET/packs/v2/"
else
  echo "[dry-run] gsutil -m cp -r $SEED_DIR/**/*.gz gs://$BUCKET/packs/v2/"
fi

# 2. Seed Firestore from manifests.json
echo "==> seeding Firestore from manifest"
if [[ "$DRY_RUN" == "false" ]]; then
  node "$REPO_ROOT/tools/scripts/seed_firestore.mjs" \
    --bucket "$BUCKET" --manifest "$MANIFEST"
else
  echo "[dry-run] node tools/scripts/seed_firestore.mjs --bucket $BUCKET --manifest $MANIFEST"
fi

echo "==> done."
