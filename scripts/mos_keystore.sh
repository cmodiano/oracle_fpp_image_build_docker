#!/usr/bin/env bash
# Crée le keystore MOS d'AutoUpgrade dans l'espace de travail éphémère du job.
# Les runners sont jetables et interchangeables : rien n'est provisionné à l'avance, le keystore
# naît et meurt avec le job.
#
# -load_password est une commande interactive : la séquence de réponses lui est fournie sur stdin.
# Mot de passe du keystore (deux fois), puis « add -user <compte> », mot de passe MOS (deux fois),
# « exit », puis le mode auto-login. Le mot de passe du keystore est aléatoire et jeté : l'auto-login
# le rend inutile pour la suite du job.
#
# usage: mos_keystore.sh --jar J --config C --keystore K
# env: MOS_USER, MOS_PASS
set -euo pipefail

usage() { echo "usage: $0 --jar J --config C --keystore K"; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jar)      JAR="$2"; shift 2;;
    --config)   CFG="$2"; shift 2;;
    --keystore) KEYSTORE="$2"; shift 2;;
    *) usage;;
  esac
done
: "${JAR:?}" "${CFG:?}" "${KEYSTORE:?}" "${MOS_USER:?}" "${MOS_PASS:?}"

mkdir -p "$KEYSTORE"
chmod 700 "$KEYSTORE"

# Contrainte AutoUpgrade : 8 caractères minimum, au moins une majuscule et un chiffre.
KS_PASS="Ks$(openssl rand -hex 12)1A"

# La sortie est mise de côté : elle peut contenir des échos de saisie. En cas d'échec, seules les
# lignes d'erreur sont réémises, sans les mots de passe.
LOG=$(mktemp); trap 'rm -f "$LOG"' EXIT
set +e
printf '%s\n' \
  "$KS_PASS" "$KS_PASS" \
  "add -user $MOS_USER" \
  "$MOS_PASS" "$MOS_PASS" \
  "exit" \
  "YES" \
  | java -jar "$JAR" -load_password -patch -config "$CFG" > "$LOG" 2>&1
rc=$?
set -e

if [[ "$rc" -ne 0 ]] || [[ ! -f "$KEYSTORE/cwallet.sso" ]]; then
  echo "ERREUR : création du keystore MOS échouée (rc=$rc)" >&2
  echo "Si AutoUpgrade lit les mots de passe sur le terminal et non sur stdin, cette approche ne" >&2
  echo "peut pas fonctionner : voir README, section keystore." >&2
  grep -viE "$KS_PASS|$MOS_PASS" "$LOG" >&2 || true
  exit 1
fi
echo "Keystore MOS créé dans $KEYSTORE (auto-login)"
