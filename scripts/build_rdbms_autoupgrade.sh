#!/usr/bin/env bash
# Construit un ORACLE_HOME 19c patché et son gold image via AutoUpgrade seul : la gold image
# préassemblée vient de l'Oracle Update Advisor, aucun numéro de patch n'est nécessaire.
# À exécuter en tant que 'oracle' dans le conteneur de build.
# usage: build_rdbms_autoupgrade.sh --jar J --config C --patch-dir D --target-home H
#                                   --ru R --gold-dir G --gold-name F
set -euo pipefail

usage() { echo "usage: $0 --jar J --config C --patch-dir D --target-home H --ru R --gold-dir G --gold-name F"; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jar)         JAR="$2"; shift 2;;
    --config)      CFG="$2"; shift 2;;
    --patch-dir)   PATCH_DIR="$2"; shift 2;;
    --target-home) TARGET_HOME="$2"; shift 2;;
    --ru)          RU="$2"; shift 2;;
    --gold-dir)    GOLD_DIR="$2"; shift 2;;
    --gold-name)   GOLD_NAME="$2"; shift 2;;
    *) usage;;
  esac
done
: "${JAR:?}" "${CFG:?}" "${PATCH_DIR:?}" "${TARGET_HOME:?}" "${RU:?}" "${GOLD_DIR:?}" "${GOLD_NAME:?}"
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

# 3. Contrôle de version : aucun numéro de patch n'est imposé, mais le RU obtenu doit être celui visé.
"$TARGET_HOME/OPatch/opatch" lspatches | tee "$GOLD_DIR/lspatches.txt"
"$TARGET_HOME/bin/oraversion" -compositeVersion | tee "$GOLD_DIR/version.txt"
VERSION=$(tr -d '[:space:]' < "$GOLD_DIR/version.txt")
[[ "$VERSION" == "$RU".* ]] \
  || { echo "ERREUR : version obtenue $VERSION, RU visé $RU" >&2; exit 1; }

# 4. Gold image : AutoUpgrade la produit via create_gold_image, à un emplacement non documenté.
# Repli sur runInstaller si elle est introuvable.
FOUND=$(find "$PATCH_DIR" "$(dirname "$TARGET_HOME")" "$GOLD_DIR" -maxdepth 3 -type f \
          -name "$GOLD_NAME" 2>/dev/null | head -1)
if [[ -z "$FOUND" ]]; then
  FOUND=$(find "$PATCH_DIR" "$(dirname "$TARGET_HOME")" -maxdepth 3 -type f \
            -name '*goldimage*.zip' 2>/dev/null | head -1)
fi
if [[ -n "$FOUND" ]]; then
  log "Gold image produite par AutoUpgrade : $FOUND"
  [[ "$FOUND" == "$GOLD_DIR/$GOLD_NAME" ]] || mv "$FOUND" "$GOLD_DIR/$GOLD_NAME"
else
  log "Aucune gold image produite par AutoUpgrade — repli sur runInstaller -createGoldImage"
  "$TARGET_HOME/runInstaller" -silent -createGoldImage \
    -destinationLocation "$GOLD_DIR" -name "$GOLD_NAME"
fi
ls -lh "$GOLD_DIR"
