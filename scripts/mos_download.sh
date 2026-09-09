#!/usr/bin/env bash
# Télécharge des patches depuis My Oracle Support (Linux x86-64).
# usage: mos_download.sh <dest_dir> <patch1> [patch2 ...]
# Requiert MOS_USER / MOS_PASS et getMOSPatch.jar sur le runner
# (https://github.com/MarisElsins/getMOSPatch) — ou remplacer par votre méthode maison.
set -euo pipefail
DEST="$1"; shift
: "${MOS_USER:?}" "${MOS_PASS:?}"
GETMOS="${GETMOS_JAR:-/u01/app/tools/getMOSPatch.jar}"
mkdir -p "$DEST"
for p in "$@"; do
  [[ -z "$p" ]] && continue
  echo "Downloading patch $p"
  java -jar "$GETMOS" MOSUser="$MOS_USER" MOSPass="$MOS_PASS" \
    patch="$p" platform=226P download=all destination="$DEST" silent=yes
done
ls -lh "$DEST"
