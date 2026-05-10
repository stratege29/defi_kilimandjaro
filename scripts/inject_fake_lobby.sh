#!/usr/bin/env bash
# Injecte un faux adversaire dans /lobby pour tester le matchmaking sans 2e device.
#
# Usage : ./scripts/inject_fake_lobby.sh [mmr]
#   mmr (optionnel) — altitude du faux joueur, défaut 1000
#
# Pré-requis : `firebase login` actif, projet kilimandjaro-dev sélectionné.
set -euo pipefail

MMR="${1:-1000}"
TS=$(($(date +%s%N) / 1000000))   # timestamp en ms
UID_FAKE="fake_$(date +%s)"

JSON=$(printf '{"mmr":%d,"ts":%d,"request_id":"test"}' "$MMR" "$TS")

echo "→ Inject /lobby/${UID_FAKE} : ${JSON}"

# Écrit le payload dans un fichier temporaire puis le passe à firebase CLI
# (le here-string sur stdin n'est pas géré correctement par database:set).
TMPFILE=$(mktemp -t fakelobby.XXXXXX.json)
trap 'rm -f "$TMPFILE"' EXIT
printf '%s' "$JSON" > "$TMPFILE"

firebase database:set "/lobby/${UID_FAKE}" "$TMPFILE" \
  --project kilimandjaro-dev \
  --force

echo "✔ Fake lobby entry posted. Wait <5s for your iPhone client to match."
echo "  To clean up: firebase database:remove /lobby/${UID_FAKE} --project kilimandjaro-dev --force"
