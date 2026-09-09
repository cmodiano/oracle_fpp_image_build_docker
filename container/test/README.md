# Validation locale de l'image de base

Permet de vérifier `container/Dockerfile` sans passer par GitHub Actions, sur un poste macOS avec
[`container`](https://github.com/apple/container) (fonctionne aussi avec `docker` : mêmes arguments).

## Build

```bash
container build --platform linux/amd64 --build-arg REPO_FILE=test/rocky8.repo \
  -t oracle-build-base:local-test container/
```

`test/rocky8.repo` fournit les paquets `-devel` absents des dépôts UBI publics via des miroirs
publics compatibles RHEL 8. Il emprunte le **même mécanisme `REPO_FILE`** que la production, ce qui
valide aussi ce chemin de code. `--platform linux/arm64` fonctionne également et va plus vite sur
Apple Silicon.

> `rocky8.repo` est réservé à la validation locale. En production, `REPO_FILE` pointe sur le
> Satellite ou le remote RPM Artifactory interne.

## Smoke tests

```bash
container run --rm oracle-build-base:local-test bash -c '
  id oracle; id grid; java -version
  cat /etc/oraInst.loc; ls -ld /u01/app/oraInventory
  rpm -q ksh libnsl libaio libaio-devel glibc-devel elfutils-libelf-devel libstdc++-devel libXrender-devel
  sudo -n -l'
```

Vérification du sudo restreint et du helper de nettoyage :

```bash
container run --rm oracle-build-base:local-test bash -c '
  H=/u01/app/oracle/product/19.0.0/dbhome_1
  mkdir -p "$H"; printf "#!/bin/sh\necho ok\n" > "$H/root.sh"; chmod 755 "$H/root.sh"
  sudo -n "$H/root.sh"                                          # doit passer
  sudo -n /usr/local/sbin/oracle-build-cleanup /etc             # doit être refusé
  sudo -n /usr/local/sbin/oracle-build-cleanup /u01/app/../etc  # doit être refusé
  sudo -n /usr/local/sbin/oracle-build-cleanup "$H"'            # doit supprimer
```

## Ce que ce test couvre

- Résolution et présence des paquets prérequis 19c.
- Users, groupes, UID/GID, limites, `/u01`, `/etc/oraInst.loc`.
- Règles sudo : `root.sh` sous un home à deux niveaux est bien autorisé (le motif à un seul niveau
  de la version initiale le refusait), helper de nettoyage borné à `/u01` et refusant `..`.
- Absence de tout binaire Oracle dans l'image.

## Ce qu'il ne couvre pas

- Les dépôts RPM internes réels.
- Tout ce qui touche Oracle : installation, patching, gold images. Ces étapes exigent les zips 19.3,
  un accès MOS et Artifactory, donc un runner `oracle-build`.
- Le push vers le registre Artifactory.
