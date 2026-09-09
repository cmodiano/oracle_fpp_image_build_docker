#!/usr/bin/env bash
# usage: publish_artifactory.sh <fichier local> <chemin relatif dans le repo> "<k=v;k=v>"
# Publie avec checksum SHA-256 et propriétés (matrix params) pour piloter l'import FPP par métadonnées.
set -euo pipefail
FILE="$1"; DEST="$2"; PROPS="${3:-}"
: "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_REPO:?}" "${ARTIFACTORY_TOKEN:?}"
SHA256=$(sha256sum "$FILE" | awk '{print $1}')
URL="$ARTIFACTORY_URL/$ARTIFACTORY_REPO/$DEST"
[[ -n "$PROPS" ]] && URL="$URL;$PROPS;sha256=$SHA256"
echo "Uploading $FILE -> $URL"
curl -fsS -H "Authorization: Bearer $ARTIFACTORY_TOKEN" \
     -H "X-Checksum-Sha256: $SHA256" \
     -T "$FILE" "$URL" > /dev/null
echo "sha256=$SHA256"
