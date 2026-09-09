#!/usr/bin/env bash
# Construit un ORACLE_HOME 19c patché (software-only) depuis le zip 19.3 de base et produit
# un gold image importable dans FPP.
# À exécuter en tant que 'oracle' dans le conteneur de build (sudo NOPASSWD pour root.sh).
set -euo pipefail

usage() { echo "usage: $0 --base-zip Z --oracle-home H --oracle-base B --patch-dir D --ru-patch N [--oneoffs a,b] --rsp R --gold-dir G --gold-name F"; exit 1; }
ONEOFFS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-zip)    BASE_ZIP="$2"; shift 2;;
    --oracle-home) ORACLE_HOME="$2"; shift 2;;
    --oracle-base) ORACLE_BASE="$2"; shift 2;;
    --patch-dir)   PATCH_DIR="$2"; shift 2;;
    --ru-patch)    RU_PATCH="$2"; shift 2;;
    --oneoffs)     ONEOFFS="$2"; shift 2;;
    --rsp)         RSP="$2"; shift 2;;
    --gold-dir)    GOLD_DIR="$2"; shift 2;;
    --gold-name)   GOLD_NAME="$2"; shift 2;;
    *) usage;;
  esac
done
: "${BASE_ZIP:?}" "${ORACLE_HOME:?}" "${ORACLE_BASE:?}" "${PATCH_DIR:?}" "${RU_PATCH:?}" "${RSP:?}" "${GOLD_DIR:?}" "${GOLD_NAME:?}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

# Le CVU ne reconnaît pas UBI : on lui présente une distribution supportée.
export CV_ASSUME_DISTID="${CV_ASSUME_DISTID:-OL8}"
export ORACLE_HOME ORACLE_BASE

# 0. Le home doit être construit from scratch : refus si quoi que ce soit y traîne déjà.
if [[ -e "$ORACLE_HOME" ]] && [[ -n "$(ls -A "$ORACLE_HOME" 2>/dev/null)" ]]; then
  echo "ERREUR : $ORACLE_HOME n'est pas vide ; le home doit être construit from scratch" >&2
  exit 1
fi

# 1. Déballer l'image DB 19.3 de base
log "Unzip base image -> $ORACLE_HOME"
mkdir -p "$ORACLE_HOME" "$GOLD_DIR" "$PATCH_DIR/unzipped"
unzip -oq "$BASE_ZIP" -d "$ORACLE_HOME"

# 2. Remplacer OPatch (obligatoire avant -applyRU)
if compgen -G "$PATCH_DIR/p6880880*.zip" > /dev/null; then
  log "Update OPatch"
  rm -rf "$ORACLE_HOME/OPatch"
  unzip -oq "$PATCH_DIR"/p6880880*.zip -d "$ORACLE_HOME"
else
  echo "ERREUR : aucun zip OPatch (p6880880*.zip) dans $PATCH_DIR" >&2
  exit 1
fi

# 3. Déballer RU et one-offs (OJVM, MRP, DPBP… fournis par l'étape de téléchargement)
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

# 4. Response file : substitution des chemins puis installation software-only.
RSP_RUN="$PATCH_DIR/db_swonly.run.rsp"
sed -e "s|@@ORACLE_HOME@@|$ORACLE_HOME|" -e "s|@@ORACLE_BASE@@|$ORACLE_BASE|" \
    "$(readlink -f "$RSP")" > "$RSP_RUN"

log "runInstaller -applyRU (software only)"
APPLY=(-applyRU "$RU_DIR")
[[ -n "$ONEOFF_DIRS" ]] && APPLY+=(-applyOneOffs "$ONEOFF_DIRS")
rc=0
"$ORACLE_HOME/runInstaller" -silent -waitForCompletion -ignorePrereqFailure \
  -responseFile "$RSP_RUN" "${APPLY[@]}" || rc=$?
# runInstaller renvoie 6 pour "succeeded with warnings"
[[ "$rc" == 0 || "$rc" == 6 ]] || { echo "runInstaller failed rc=$rc"; exit 1; }

# 5. Scripts root (le rsp demande executeRootScript=false)
if [[ -x /u01/app/oraInventory/orainstRoot.sh ]]; then
  log "orainstRoot.sh"
  sudo /u01/app/oraInventory/orainstRoot.sh
fi
log "root.sh"
sudo "$ORACLE_HOME/root.sh"

# 6. Inventaire des patches : le RU doit y figurer, sinon l'installation n'a pas appliqué le RU.
"$ORACLE_HOME/OPatch/opatch" lspatches | tee "$GOLD_DIR/lspatches.txt"
grep -q "^${RU_PATCH};" "$GOLD_DIR/lspatches.txt" \
  || { echo "ERREUR : le RU $RU_PATCH n'apparaît pas dans lspatches" >&2; exit 1; }
"$ORACLE_HOME/bin/oraversion" -compositeVersion | tee "$GOLD_DIR/version.txt"

# 7. Gold image
log "createGoldImage -> $GOLD_DIR/$GOLD_NAME"
"$ORACLE_HOME/runInstaller" -silent -createGoldImage -destinationLocation "$GOLD_DIR" -name "$GOLD_NAME"
ls -lh "$GOLD_DIR"
