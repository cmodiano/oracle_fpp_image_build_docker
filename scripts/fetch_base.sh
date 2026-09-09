#!/usr/bin/env bash
# Rapatrie un artefact depuis Artifactory (zip 19.3 de base, autoupgrade.jar…) et vérifie son sha256.
# Le checksum est lu sur l'API de stockage si --sha256 n'est pas fourni.
# usage: fetch_base.sh --repo R --path P --dest D [--sha256 S]
set -euo pipefail

usage() { echo "usage: $0 --repo R --path P --dest D [--sha256 S]"; exit 1; }
SHA_EXPECTED=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   REPO="$2"; shift 2;;
    --path)   APATH="$2"; shift 2;;
    --dest)   DEST="$2"; shift 2;;
    --sha256) SHA_EXPECTED="$2"; shift 2;;
    *) usage;;
  esac
done
: "${REPO:?}" "${APATH:?}" "${DEST:?}" "${ARTIFACTORY_URL:?}" "${ARTIFACTORY_TOKEN:?}"

AUTH=(-H "Authorization: Bearer $ARTIFACTORY_TOKEN")

if [[ -z "$SHA_EXPECTED" ]]; then
  SHA_EXPECTED=$(curl -fsS "${AUTH[@]}" "$ARTIFACTORY_URL/api/storage/$REPO/$APATH" \
    | jq -r '.checksums.sha256 // empty')
  [[ -n "$SHA_EXPECTED" ]] \
    || { echo "ERREUR : sha256 introuvable pour $REPO/$APATH" >&2; exit 1; }
fi

mkdir -p "$(dirname "$DEST")"
echo "Téléchargement $REPO/$APATH -> $DEST"
curl -fsS "${AUTH[@]}" -o "$DEST" "$ARTIFACTORY_URL/$REPO/$APATH"

SHA_LOCAL=$(sha256sum "$DEST" | awk '{print $1}')
if [[ "$SHA_LOCAL" != "$SHA_EXPECTED" ]]; then
  echo "ERREUR : sha256 attendu $SHA_EXPECTED, obtenu $SHA_LOCAL" >&2
  rm -f "$DEST"
  exit 1
fi
echo "sha256 vérifié : $SHA_LOCAL"
