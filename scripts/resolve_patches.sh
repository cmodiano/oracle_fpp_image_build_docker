#!/usr/bin/env bash
# Résout les numéros de patch d'un MRP depuis la table versionnée config/patches/<mrp_label>.json
# et les émet au format key=value (destiné à $GITHUB_OUTPUT).
# usage: resolve_patches.sh --dir config/patches [--mrp <mrp_label>|latest]
set -euo pipefail

DIR="config/patches"
MRP="latest"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="$2"; shift 2;;
    --mrp) MRP="$2"; shift 2;;
    *) echo "usage: $0 --dir D [--mrp M|latest]" >&2; exit 1;;
  esac
done

fail() { echo "ERREUR : $*" >&2; exit 1; }

if [[ "$MRP" == "latest" ]]; then
  # Les fichiers sont nommés d'après le libellé MRP : le tri par version donne le plus récent.
  FILE=$(cd "$DIR" && printf '%s\n' [0-9]*.json | sort -V | tail -1)
  FILE="$DIR/$FILE"
  [[ -f "$FILE" ]] || fail "aucune table de patches dans $DIR"
else
  FILE="$DIR/$MRP.json"
fi
[[ -f "$FILE" ]] || fail "table de patches introuvable : $FILE"
echo "Table retenue : $FILE" >&2

get() { jq -r --arg k "$1" '.[$k] // empty' "$FILE"; }

MRP_LABEL=$(get mrp_label)
RU_VERSION=$(get ru_version)
DB_RU_PATCH=$(get db_ru_patch)
GI_RU_PATCH=$(get gi_ru_patch)
OPATCH_PATCH=$(get opatch_patch); OPATCH_PATCH="${OPATCH_PATCH:-6880880}"
GI_ONEOFFS=$(get gi_oneoffs)
DB_ONEOFFS=$(get db_oneoffs);     DB_ONEOFFS="${DB_ONEOFFS:-auto}"

[[ -n "$MRP_LABEL"   ]] || fail "clé mrp_label absente ou vide dans $FILE"
[[ -n "$RU_VERSION"  ]] || fail "clé ru_version absente ou vide dans $FILE"
[[ -n "$DB_RU_PATCH" ]] || fail "clé db_ru_patch absente ou vide dans $FILE"
[[ -n "$GI_RU_PATCH" ]] || fail "clé gi_ru_patch absente ou vide dans $FILE"

# Ces valeurs alimentent des chemins Artifactory et des lignes de commande : jeu de caractères borné.
[[ "$MRP_LABEL" == "$(basename "$FILE" .json)" ]] \
  || fail "mrp_label '$MRP_LABEL' ≠ nom du fichier $(basename "$FILE" .json)"
[[ "$MRP_LABEL"   =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "mrp_label invalide : $MRP_LABEL"
[[ "$RU_VERSION"  =~ ^[0-9]+\.[0-9]+$ ]]    || fail "ru_version invalide : $RU_VERSION"
[[ "$DB_RU_PATCH" =~ ^[0-9]+$ ]]            || fail "db_ru_patch invalide : $DB_RU_PATCH"
[[ "$GI_RU_PATCH" =~ ^[0-9]+$ ]]            || fail "gi_ru_patch invalide : $GI_RU_PATCH"
[[ "$OPATCH_PATCH" =~ ^[0-9]+$ ]]           || fail "opatch_patch invalide : $OPATCH_PATCH"
[[ "$GI_ONEOFFS"  =~ ^([0-9]+(,[0-9]+)*)?$ ]] || fail "gi_oneoffs invalide : $GI_ONEOFFS"
[[ "$DB_ONEOFFS" == "auto" || "$DB_ONEOFFS" == "none" || "$DB_ONEOFFS" =~ ^[0-9]+(,[0-9]+)*$ ]] \
  || fail "db_oneoffs invalide : $DB_ONEOFFS"
[[ "$MRP_LABEL" == "$RU_VERSION".* ]] \
  || fail "mrp_label '$MRP_LABEL' incohérent avec ru_version '$RU_VERSION'"

cat <<EOF
mrp_label=$MRP_LABEL
ru_version=$RU_VERSION
db_ru_patch=$DB_RU_PATCH
gi_ru_patch=$GI_RU_PATCH
opatch_patch=$OPATCH_PATCH
gi_oneoffs=$GI_ONEOFFS
db_oneoffs=$DB_ONEOFFS
EOF
