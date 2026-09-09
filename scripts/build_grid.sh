#!/usr/bin/env bash
# Construit un Grid home 19c patché (software-only) et produit un gold image importable dans FPP.
# À exécuter en tant que 'grid' avec sudo NOPASSWD pour root.sh.
set -euo pipefail

usage() { echo "usage: $0 --base-zip Z --grid-home H --patch-dir D --ru-patch N [--oneoffs a,b] --rsp R --gold-dir G --gold-name F"; exit 1; }
ONEOFFS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-zip)  BASE_ZIP="$2"; shift 2;;
    --grid-home) GRID_HOME="$2"; shift 2;;
    --patch-dir) PATCH_DIR="$2"; shift 2;;
    --ru-patch)  RU_PATCH="$2"; shift 2;;
    --oneoffs)   ONEOFFS="$2"; shift 2;;
    --rsp)       RSP="$2"; shift 2;;
    --gold-dir)  GOLD_DIR="$2"; shift 2;;
    --gold-name) GOLD_NAME="$2"; shift 2;;
    *) usage;;
  esac
done
: "${BASE_ZIP:?}" "${GRID_HOME:?}" "${PATCH_DIR:?}" "${RU_PATCH:?}" "${RSP:?}" "${GOLD_DIR:?}" "${GOLD_NAME:?}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

# 1. Déballer l'image Grid 19.3 de base
log "Unzip base image -> $GRID_HOME"
mkdir -p "$GRID_HOME" "$GOLD_DIR" "$PATCH_DIR/unzipped"
unzip -oq "$BASE_ZIP" -d "$GRID_HOME"

# 2. Remplacer OPatch (obligatoire avant -applyRU)
if compgen -G "$PATCH_DIR/p6880880*.zip" > /dev/null; then
  log "Update OPatch"
  rm -rf "$GRID_HOME/OPatch"
  unzip -oq "$PATCH_DIR"/p6880880*.zip -d "$GRID_HOME"
fi

# 3. Déballer RU et one-offs
log "Unzip RU $RU_PATCH"
unzip -oq "$PATCH_DIR/p${RU_PATCH}"*.zip -d "$PATCH_DIR/unzipped"
RU_DIR="$PATCH_DIR/unzipped/$RU_PATCH"
ONEOFF_DIRS=""
if [[ -n "$ONEOFFS" ]]; then
  IFS=',' read -ra OO <<< "$ONEOFFS"
  for p in "${OO[@]}"; do
    unzip -oq "$PATCH_DIR/p${p}"*.zip -d "$PATCH_DIR/unzipped"
    ONEOFF_DIRS="${ONEOFF_DIRS:+$ONEOFF_DIRS,}$PATCH_DIR/unzipped/$p"
  done
fi

# 4. Installation software-only avec RU (+ one-offs) appliqués à la volée
log "gridSetup -applyRU (software only)"
APPLY=(-applyRU "$RU_DIR")
[[ -n "$ONEOFF_DIRS" ]] && APPLY+=(-applyOneOffs "$ONEOFF_DIRS")
rc=0
"$GRID_HOME/gridSetup.sh" -silent -waitForCompletion -ignorePrereqFailure \
  -responseFile "$(readlink -f "$RSP")" "${APPLY[@]}" || rc=$?
# gridSetup renvoie 6 pour "succeeded with warnings"
[[ "$rc" == 0 || "$rc" == 6 ]] || { echo "gridSetup failed rc=$rc"; exit 1; }

# 5. root.sh (finalise le software-only)
log "root.sh"
sudo "$GRID_HOME/root.sh"

# 6. Inventaire des patches pour le manifeste
"$GRID_HOME/OPatch/opatch" lspatches | tee "$GOLD_DIR/lspatches.txt"

# 7. Gold image
log "createGoldImage -> $GOLD_DIR/$GOLD_NAME"
"$GRID_HOME/gridSetup.sh" -silent -createGoldImage -destinationLocation "$GOLD_DIR" -name "$GOLD_NAME"
ls -lh "$GOLD_DIR"
