# oracle-build-base (UBI 8)

Image de build sans binaires Oracle : prérequis 19c, users/groupes, limites, `/u01`, `oraInst.loc`,
sudo restreint. Reconstruite uniquement quand `container/**` change (workflow `build-base-image.yml`).

## Build
```bash
docker build -t "$CONTAINER_REGISTRY/dbops/oracle-build-base:ubi8-19c" container/
```

### UID/GID
Défauts Oracle : `oracle=54321`, `grid=54322`, `oinstall=54321`, `dba=54322`. Ils doivent correspondre
à ceux des VM du parc, sinon les fichiers du gold image portent les mauvais propriétaires :
```bash
docker build --build-arg ORACLE_UID=1001 --build-arg OINSTALL_GID=1001 ... container/
```

### Paquets absents d'UBI 8
`libaio-devel`, `elfutils-libelf-devel`, `libXrender-devel` et `libstdc++-devel` ne sont pas dans les
dépôts UBI publics. Contrairement à Podman, **Docker ne transmet pas l'entitlement RHEL de l'hôte**
au build : l'abonnement de la machine ne suffit pas.

Méthode retenue : déposer un `.repo` interne (Satellite ou remote RPM Artifactory) dans `container/`
et builder avec `--build-arg REPO_FILE=<nom>.repo`.

```bash
docker build --build-arg REPO_FILE=desjardins.repo -t "$CONTAINER_REGISTRY/dbops/oracle-build-base:ubi8-19c" container/
```

Alternative si l'on tient à l'abonnement de l'hôte : BuildKit avec
`--secret id=rhsm,src=/etc/pki/entitlement` et un `RUN --mount=type=secret` dans le Dockerfile —
plus de pièces mobiles, non retenu ici.

## Utilisation dans le workflow
```yaml
jobs:
  build-rdbms:
    runs-on: [self-hosted, linux, oracle-build]
    container:
      image: <registre>/dbops/oracle-build-base:ubi8-19c
      options: --user 54321:54321          # oracle ; 54322:54321 pour grid
```

Aucun volume : le conteneur travaille dans son propre système de fichiers (`/u01/gha`) et emporte
tout en disparaissant. Rien n'est provisionné sur le runner, aucun état ne survit au job.

## Variables et secrets GitHub utilisés par `build-base-image.yml`
- Variables : `CONTAINER_REGISTRY` (hôte du registre Artifactory), `ARTIFACTORY_USER`.
- Secret : `ARTIFACTORY_TOKEN`.

## Ce qui n'est volontairement pas dedans
- Aucun zip ni home Oracle : tout est rapatrié à chaque run.
- Aucun sysctl (sans effet en conteneur ; les prérequis noyau sont validés par FPP sur les cibles).
- Aucun identifiant : keystore AutoUpgrade et secrets sont injectés à l'exécution.
