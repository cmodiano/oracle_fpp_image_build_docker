#!/usr/bin/env bash
# Construit un ORACLE_HOME 19c patché et son gold image via AutoUpgrade seul : la gold image
# préassemblée vient de l'Oracle Update Advisor, aucun numéro de patch n'est nécessaire.
# À exécuter en tant que 'oracle' dans le conteneur de build.
# usage: build_rdbms_autoupgrade.sh --jar J --config C --patch-dir D --target-home H
#                                   --gold-dir G --gold-name F
set -euo pipefail

usage() { echo "usage: $0 --jar J --config C --patch-dir D --target-home H --gold-dir G --gold-name F"; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jar)         JAR="$2"; shift 2;;
    --config)      CFG="$2"; shift 2;;
    --patch-dir)   PATCH_DIR="$2"; shift 2;;
    --target-home) TARGET_HOME="$2"; shift 2;;
    --gold-dir)    GOLD_DIR="$2"; shift 2;;
    --gold-name)   GOLD_NAME="$2"; shift 2;;
    *) usage;;
  esac
done
: "${JAR:?}" "${CFG:?}" "${PATCH_DIR:?}" "${TARGET_HOME:?}" "${GOLD_DIR:?}" "${GOLD_NAME:?}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

export CV_ASSUME_DISTID="${CV_ASSUME_DISTID:-OL8}"

# 0. Le home doit être construit from scratch.
if [[ -e "$TARGET_HOME" ]] && [[ -n "$(ls -A "$TARGET_HOME" 2>/dev/null)" ]]; then
  echo "ERREUR : $TARGET_HOME n'est pas vide ; le home doit être construit from scratch" >&2
  exit 1
fi
mkdir -p "$PATCH_DIR" "$GOLD_DIR"

java -jar "$JAR" -version

# 1. Téléchargement (gold image OUA + patches complémentaires)
log "AutoUpgrade -mode download"
java -jar "$JAR" -config "$CFG" -patch -mode download
log "Contenu de $PATCH_DIR :"
find "$PATCH_DIR" -type f -exec ls -lh {} +
[[ -n "$(ls -A "$PATCH_DIR" 2>/dev/null)" ]] \
  || { echo "ERREUR : rien n'a été téléchargé dans $PATCH_DIR" >&2; exit 1; }

# 2. Création du home (EXTRACT, INSTALL, OH_PATCHING, ROOTSH)
log "AutoUpgrade -mode create_home"
java -jar "$JAR" -config "$CFG" -patch -mode create_home
[[ -x "$TARGET_HOME/bin/oraversion" ]] \
  || { echo "ERREUR : aucun home exploitable sous $TARGET_HOME" >&2; exit 1; }

# 3. Relevé de ce qui a été construit. Aucun RU n'est visé en entrée : la cohérence entre l'image
# RDBMS et l'image Grid est contrôlée par le job de synthèse du workflow.
"$TARGET_HOME/OPatch/opatch" lspatches | tee "$GOLD_DIR/lspatches.txt"
"$TARGET_HOME/bin/oraversion" -compositeVersion | tee "$GOLD_DIR/version.txt"
VERSION=$(tr -d '[:space:]' < "$GOLD_DIR/version.txt")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\. ]] \
  || { echo "ERREUR : version illisible : $VERSION" >&2; exit 1; }
log "version construite : $VERSION"

# 4. Gold image : produite par AutoUpgrade via create_gold_image, à un emplacement non documenté.
# On la cherche, et on échoue si elle est absente — aucune reconstruction implicite.
FOUND=$(find "$PATCH_DIR" "$(dirname "$TARGET_HOME")" "$GOLD_DIR" -maxdepth 3 -type f \
          \( -name "$GOLD_NAME" -o -name '*goldimage*.zip' \) 2>/dev/null | head -1)
if [[ -z "$FOUND" ]]; then
  echo "ERREUR : AutoUpgrade n'a produit aucune gold image (create_gold_image=$GOLD_NAME)" >&2
  echo "Contenu inspecté :" >&2
  find "$PATCH_DIR" "$(dirname "$TARGET_HOME")" "$GOLD_DIR" -maxdepth 3 -name '*.zip' >&2 || true
  exit 1
fi
log "Gold image produite par AutoUpgrade : $FOUND"
[[ "$FOUND" == "$GOLD_DIR/$GOLD_NAME" ]] || mv "$FOUND" "$GOLD_DIR/$GOLD_NAME"
ls -lh "$GOLD_DIR"
