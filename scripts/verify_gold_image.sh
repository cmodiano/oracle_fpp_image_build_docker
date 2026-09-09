#!/usr/bin/env bash
# Contrôle un gold image avant publication et produit son manifeste.
# usage: verify_gold_image.sh --zip Z --type rdbms|grid --ru R --mrp M --lspatches L
#                             --version-file V --base-sha256 S --container-tag T --out manifest.json
set -euo pipefail

usage() { echo "usage: $0 --zip Z --type rdbms|grid --ru R --mrp M --lspatches L --version-file V --base-sha256 S --container-tag T --out O"; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip)           ZIP="$2"; shift 2;;
    --type)          TYPE="$2"; shift 2;;
    --ru)            RU="$2"; shift 2;;
    --mrp)           MRP="$2"; shift 2;;
    --lspatches)     LSPATCHES="$2"; shift 2;;
    --version-file)  VERSION_FILE="$2"; shift 2;;
    --base-sha256)   BASE_SHA="$2"; shift 2;;
    --container-tag) CONTAINER_TAG="$2"; shift 2;;
    --out)           OUT="$2"; shift 2;;
    *) usage;;
  esac
done
: "${ZIP:?}" "${TYPE:?}" "${RU:?}" "${MRP:?}" "${LSPATCHES:?}" "${VERSION_FILE:?}" "${BASE_SHA:?}" "${CONTAINER_TAG:?}" "${OUT:?}"

fail() { echo "ERREUR : $*" >&2; exit 1; }

case "$TYPE" in
  rdbms) IMAGE_TYPE=ORACLEDBSOFTWARE ;;
  grid)  IMAGE_TYPE=ORACLEGISOFTWARE ;;
  *) fail "type inconnu : $TYPE" ;;
esac

LIST=$(mktemp); trap 'rm -f "$LIST"' EXIT
unzip -Z1 "$ZIP" > "$LIST"

# --- Présence des éléments indispensables à l'import FPP ------------------------------------
require() { grep -qxF "$1" "$LIST" || fail "$1 absent du zip"; }
require "OPatch/opatch"
require "inventory/ContentsXML/comps.xml"
require "inventory/ContentsXML/oraclehomeproperties.xml"
if [[ "$TYPE" == "grid" ]]; then require "gridSetup.sh"; else require "runInstaller"; fi

# --- Absence de résidus d'installation et de configuration locale ---------------------------
forbid() { grep -qE "$1" "$LIST" && fail "$2"; return 0; }
forbid '^log/'                       "répertoire log/ présent"
forbid '^cfgtoollogs/'               "répertoire cfgtoollogs/ présent"
forbid '^install/.*\.log$'           "logs d'installation présents"
forbid '\.bak$'                      "fichiers .bak présents"
# network/admin ne doit contenir que les samples livrés par Oracle
grep -E '^network/admin/.*\.ora$' "$LIST" | grep -qv '^network/admin/samples/' \
  && fail "fichiers .ora dans network/admin"
if [[ "$TYPE" == "grid" ]]; then
  forbid '^crs/install/crsconfig_params$' "crsconfig_params présent (home configuré)"
else
  # dbs ne doit contenir que le init.ora d'origine
  grep -E '^dbs/.*\.ora$' "$LIST" | grep -qv '^dbs/init\.ora$' \
    && fail "fichiers de paramètres d'instance dans dbs/"
fi

# --- Version cohérente avec le RU demandé ---------------------------------------------------
VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
[[ "$VERSION" == "$RU".* ]] || fail "version $VERSION incohérente avec le RU $RU"

# --- Taille --------------------------------------------------------------------------------
SIZE=$(wc -c < "$ZIP" | tr -d "[:space:]")
(( SIZE < 8 * 1024 * 1024 * 1024 )) || fail "zip de $SIZE octets (> 8 Go)"

IMAGE_SHA=$(sha256sum "$ZIP" | awk '{print $1}')

# --- Manifeste ------------------------------------------------------------------------------
# lspatches produit des lignes « <numéro>;<description> ».
jq -n \
  --arg type "$IMAGE_TYPE" \
  --arg ru "$RU" \
  --arg mrp "$MRP" \
  --arg version "$VERSION" \
  --arg base_sha "$BASE_SHA" \
  --arg image_sha "$IMAGE_SHA" \
  --arg tag "$CONTAINER_TAG" \
  --arg commit "${GITHUB_SHA:-}" \
  --arg run_id "${GITHUB_RUN_ID:-}" \
  --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson size "$SIZE" \
  --rawfile lspatches "$LSPATCHES" \
  '{
     type: $type, ru: $ru, mrp: $mrp, version: $version,
     patches: ($lspatches | split("\n") | map(select(length > 0) | split(";")
               | {id: .[0], description: (.[1] // "")})),
     base_zip_sha256: $base_sha, image_sha256: $image_sha, image_size: $size,
     build_container_tag: $tag, commit: $commit, run_id: $run_id, date: $date
   }' > "$OUT"

echo "Contrôles OK — $ZIP ($SIZE octets, sha256=$IMAGE_SHA)"
cat "$OUT"
