#!/usr/bin/env bash
# Construit un Grid home 19c patché (software-only) depuis le zip 19.3 de base et produit
# un gold image importable dans FPP.
# À exécuter en tant que 'grid' dans le conteneur de build (sudo NOPASSWD pour root.sh).
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

# Le CVU ne reconnaît pas UBI : on lui présente une distribution supportée.
export CV_ASSUME_DISTID="${CV_ASSUME_DISTID:-OL8}"

# 0. Le home doit être construit from scratch : refus si quoi que ce soit y traîne déjà.
if [[ -e "$GRID_HOME" ]] && [[ -n "$(ls -A "$GRID_HOME" 2>/dev/null)" ]]; then
  echo "ERREUR : $GRID_HOME n'est pas vide ; le home doit être construit from scratch" >&2
  exit 1
fi

# 1. Déballer l'image Grid 19.3 de base
log "Unzip base image -> $GRID_HOME"
mkdir -p "$GRID_HOME" "$GOLD_DIR" "$PATCH_DIR/unzipped"
unzip -oq "$BASE_ZIP" -d "$GRID_HOME"

# 2. Remplacer OPatch (obligatoire avant -applyRU)
if compgen -G "$PATCH_DIR/p6880880*.zip" > /dev/null; then
  log "Update OPatch"
  rm -rf "$GRID_HOME/OPatch"
  unzip -oq "$PATCH_DIR"/p6880880*.zip -d "$GRID_HOME"
else
  echo "ERREUR : aucun zip OPatch (p6880880*.zip) dans $PATCH_DIR" >&2
  exit 1
fi

# 3. Déballer RU et one-offs
log "Unzip RU $RU_PATCH"
unzip -oq "$PATCH_DIR/p${RU_PATCH}"*.zip -d "$PATCH_DIR/unzipped"
RU_DIR="$PATCH_DIR/unzipped/$RU_PATCH"
[[ -d "$RU_DIR" ]] || { echo "ERREUR : $RU_DIR absent après déballage du RU" >&2; exit 1; }
ONEOFF_DIRS=""
if [[ -n "$ONEOFFS" ]]; then
  IFS=',' read -ra OO <<< "$ONEOFFS"
  for p in "${OO[@]}"; do
    [[ -z "$p" ]] && continue
    unzip -oq "$PATCH_DIR/p${p}"*.zip -d "$PATCH_DIR/unzipped"
    ONEOFF_DIRS="${ONEOFF_DIRS:+$ONEOFF_DIRS,}$PATCH_DIR/unzipped/$p"
  done
fi

# 4. Installation software-only avec RU (+ one-offs) appliqués à la volée.
# -ignorePrereqFailure est nécessaire en conteneur (sysctl, swap, mémoire) : les avertissements
# sont relus ci-dessous pour revue.
log "gridSetup -applyRU (software only)"
APPLY=(-applyRU "$RU_DIR")
[[ -n "$ONEOFF_DIRS" ]] && APPLY+=(-applyOneOffs "$ONEOFF_DIRS")
rc=0
"$GRID_HOME/gridSetup.sh" -silent -waitForCompletion -ignorePrereqFailure \
  -responseFile "$(readlink -f "$RSP")" "${APPLY[@]}" || rc=$?
# gridSetup renvoie 6 pour "succeeded with warnings"
[[ "$rc" == 0 || "$rc" == 6 ]] || { echo "gridSetup failed rc=$rc"; exit 1; }

# 5. Scripts root (le rsp demande executeRootScript=false)
if [[ -x /u01/app/oraInventory/orainstRoot.sh ]]; then
  log "orainstRoot.sh"
  sudo /u01/app/oraInventory/orainstRoot.sh
fi
log "root.sh"
sudo "$GRID_HOME/root.sh"

# 6. Inventaire des patches : le RU doit y figurer, sinon l'installation n'a pas appliqué le RU.
"$GRID_HOME/OPatch/opatch" lspatches | tee "$GOLD_DIR/lspatches.txt"
grep -q "^${RU_PATCH};" "$GOLD_DIR/lspatches.txt" \
  || { echo "ERREUR : le RU $RU_PATCH n'apparaît pas dans lspatches" >&2; exit 1; }
"$GRID_HOME/bin/oraversion" -compositeVersion | tee "$GOLD_DIR/version.txt"

# 7. Gold image
log "createGoldImage -> $GOLD_DIR/$GOLD_NAME"
"$GRID_HOME/gridSetup.sh" -silent -createGoldImage -destinationLocation "$GOLD_DIR" -name "$GOLD_NAME"
ls -lh "$GOLD_DIR"
