# oracle-build-base (UBI 8)

Image de build sans binaires Oracle : prérequis 19c, users/groupes, limites, `/u01`, `oraInst.loc`, sudo restreint.

## Build
```bash
podman build -t artifactory.example.com/dbops/oracle-build-base:ubi8-19c container/
# UID/GID différents des défauts Oracle ?  --build-arg ORACLE_UID=1001 --build-arg OINSTALL_GID=1001 ...
# Hôte non abonné RHEL ?                    --build-arg REPO_FILE=desjardins.repo  (fichier à placer dans container/)
```

## Utilisation dans le workflow
```yaml
jobs:
  build-rdbms:
    runs-on: [self-hosted, linux, oracle-build]
    container:
      image: artifactory.example.com/dbops/oracle-build-base:ubi8-19c
      options: --user 54321:54321          # oracle ; 54322:54321 pour grid
      volumes:
        - /u01/gha:/u01/gha                 # disque de travail de l'hôte (≥ 60 Go)
```
Sur UBI, quelques `-devel` (libaio-devel, elfutils-libelf-devel, libXrender-devel, libstdc++-devel)
viennent des dépôts RHEL complets : un hôte RHEL abonné (Podman passe l'entitlement) ou un `.repo`
interne suffit. Rien dans l'image ne dépend d'Oracle Linux.

## Ce qui n'est volontairement pas dedans
- Aucun zip ni home Oracle : ils sont déballés à chaque run depuis Artifactory (19.3 de base).
- Aucun sysctl (sans effet en conteneur ; les prérequis noyau sont validés par FPP sur les cibles).
- Aucun identifiant : keystore AutoUpgrade et secrets sont injectés à l'exécution.
