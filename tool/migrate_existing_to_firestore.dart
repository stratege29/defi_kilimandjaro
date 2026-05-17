// ignore_for_file: avoid_print
//
// Migration one-shot des packs existants (starter + ota_packs) vers
// Firestore. Crée :
//
//   - `content_packs/{packId}` : doc métadonnées (name, description,
//     prices, country, enabled=false par défaut). PAS de manifest (la
//     première publication via `publishPack` le posera).
//   - `content_packs/{packId}/questions/{questionId}` : doc par question
//     (id = questionId, format v3 strict).
//
// Idempotent : utilise `set(..., merge: true)`. Re-lancer écrase les champs
// modifiables sans toucher aux timestamps `created_at`.
//
// Auth : Application Default Credentials (ADC).
//   gcloud auth application-default login
//
// Usage :
//   dart pub get
//   dart run tool/migrate_existing_to_firestore.dart --project=kilimandjaro-dev
//   dart run tool/migrate_existing_to_firestore.dart --project=kilimandjaro-dev --dry-run
//
// Le script n'utilise PAS le SDK firebase_admin (pas dispo en Dart). Il
// passe par l'API REST Firestore + ADC token via gcloud.
//
// → On déclenche le côté Node pour réutiliser firebase-admin :
//
//   node tools/scripts/migrate_existing_to_firestore.mjs \
//     --project kilimandjaro-dev
//
// Ce fichier Dart est conservé comme placeholder + documentation (cf.
// l'équivalent .mjs ci-dessous, qui est l'implémentation réelle).

import 'dart:io';

void main(List<String> args) {
  stderr.writeln(
    'Ce script Dart est un placeholder pour cohérence d\'organisation.\n'
    'L\'implémentation est en Node car firebase-admin SDK n\'est pas\n'
    'disponible en Dart pour Cloud Storage / Firestore admin.\n\n'
    'Lance plutôt :\n'
    '  node tools/scripts/migrate_existing_to_firestore.mjs \\\n'
    '    --project kilimandjaro-dev [--dry-run]\n',
  );
  exit(64);
}
