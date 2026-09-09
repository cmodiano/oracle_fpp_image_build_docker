#!/usr/bin/env bash
# Télécharge le jeu de patches recommandé via AutoUpgrade (mode download uniquement).
# AutoUpgrade peut sortir en succès sans rien télécharger : la présence du RU et d'OPatch
# est donc revérifiée explicitement.
# usage: autoupgrade_download.sh --jar J --config C --patch-dir D --ru-patch N
set -euo pipefail

usage() { echo "usage: $0 --jar J --config C --patch-dir D --ru-patch N"; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jar)       JAR="$2"; shift 2;;
    --config)    CFG="$2"; shift 2;;
    --patch-dir) PATCH_DIR="$2"; shift 2;;
    --ru-patch)  RU_PATCH="$2"; shift 2;;
    *) usage;;
  esac
done
: "${JAR:?}" "${CFG:?}" "${PATCH_DIR:?}" "${RU_PATCH:?}"

java -jar "$JAR" -version
java -jar "$JAR" -config "$CFG" -patch -mode download

echo "Contenu de $PATCH_DIR :"
ls -lh "$PATCH_DIR"

compgen -G "$PATCH_DIR/p${RU_PATCH}*.zip" > /dev/null \
  || { echo "ERREUR : RU $RU_PATCH absent de $PATCH_DIR après le téléchargement" >&2; exit 1; }
compgen -G "$PATCH_DIR/p6880880*.zip" > /dev/null \
  || { echo "ERREUR : OPatch (6880880) absent de $PATCH_DIR après le téléchargement" >&2; exit 1; }
