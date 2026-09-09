#!/usr/bin/env bash
# Publie un fichier dans Artifactory avec son checksum SHA-256 et ses propriétés (matrix params),
# puis relit les métadonnées côté serveur pour confirmer le dépôt.
# Un objet déjà présent n'est jamais écrasé silencieusement : une image peut avoir été importée
# dans FPP. Mettre FORCE=true pour l'écraser volontairement.
# usage: publish_artifactory.sh <fichier local> <chemin relatif dans le repo> "<k=v;k=v>"
set -euo pipefail
FILE="$1"; DEST="$2"; PROPS="${3:-}"
: "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_REPO:?}" "${ARTIFACTORY_TOKEN:?}"
FORCE="${FORCE:-false}"

AUTH=(-H "Authorization: Bearer $ARTIFACTORY_TOKEN")
SHA256=$(sha256sum "$FILE" | awk '{print $1}')
URL="$ARTIFACTORY_URL/$ARTIFACTORY_REPO/$DEST"

# 1. Immutabilité
CODE=$(curl -sS -o /dev/null -w '%{http_code}' -I "${AUTH[@]}" "$URL")
if [[ "$CODE" == "200" ]]; then
  if [[ "$FORCE" != "true" ]]; then
    echo "ERREUR : $DEST existe déjà dans $ARTIFACTORY_REPO (relancer avec force=true pour écraser)" >&2
    exit 1
  fi
  echo "AVERTISSEMENT : écrasement de $DEST (force=true)"
elif [[ "$CODE" != "404" ]]; then
  echo "ERREUR : réponse inattendue $CODE sur HEAD $URL" >&2
  exit 1
fi

# 2. Upload avec propriétés
UPLOAD_URL="$URL"
[[ -n "$PROPS" ]] && UPLOAD_URL="$UPLOAD_URL;$PROPS"
UPLOAD_URL="$UPLOAD_URL;sha256=$SHA256;status=built"
echo "Uploading $FILE -> $UPLOAD_URL"
curl -fsS "${AUTH[@]}" -H "X-Checksum-Sha256: $SHA256" -T "$FILE" "$UPLOAD_URL" > /dev/null

# 3. Relecture des métadonnées côté serveur
REMOTE_SHA=$(curl -fsS "${AUTH[@]}" "$ARTIFACTORY_URL/api/storage/$ARTIFACTORY_REPO/$DEST" \
  | jq -r '.checksums.sha256 // empty')
[[ "$REMOTE_SHA" == "$SHA256" ]] \
  || { echo "ERREUR : sha256 distant '$REMOTE_SHA' != local '$SHA256'" >&2; exit 1; }

REMOTE_PROP=$(curl -fsS "${AUTH[@]}" "$ARTIFACTORY_URL/api/storage/$ARTIFACTORY_REPO/$DEST?properties" \
  | jq -r '.properties.sha256[0] // empty')
[[ "$REMOTE_PROP" == "$SHA256" ]] \
  || { echo "ERREUR : propriété sha256 distante '$REMOTE_PROP' != '$SHA256'" >&2; exit 1; }

echo "url=$URL"
echo "sha256=$SHA256"
