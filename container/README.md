# oracle-build-base (UBI 8)

Image de build sans binaires Oracle : prérequis 19c, users/groupes, limites, `/u01`, `oraInst.loc`,
sudo restreint. Reconstruite uniquement quand `container/**` change (workflow `build-base-image.yml`).

## Build
```bash
podman build -t "$CONTAINER_REGISTRY/dbops/oracle-build-base:ubi8-19c" container/
```

### UID/GID
Défauts Oracle : `oracle=54321`, `grid=54322`, `oinstall=54321`, `dba=54322`. Ils doivent correspondre
à ceux des VM du parc, sinon les fichiers du gold image portent les mauvais propriétaires :
```bash
podman build --build-arg ORACLE_UID=1001 --build-arg OINSTALL_GID=1001 ... container/
```

### Paquets absents d'UBI 8
`libaio-devel`, `elfutils-libelf-devel`, `libXrender-devel` et `libstdc++-devel` ne sont pas dans les
dépôts UBI publics. Deux méthodes, au choix selon le runner :

1. **Hôte RHEL abonné** (méthode par défaut) : Podman passe automatiquement l'entitlement de l'hôte
   au build, `dnf` résout les paquets depuis les dépôts RHEL. Rien à faire.
2. **Hôte non abonné** : déposer un `.repo` interne (Satellite ou remote RPM Artifactory) dans
   `container/` et builder avec `--build-arg REPO_FILE=<nom>.repo`.

## Nettoyage privilégié
`sudo` compare les arguments avec `fnmatch(FNM_PATHNAME)` : un `*` ne franchit pas un `/`, donc aucune
règle `rm -rf /u01/*` ne peut couvrir un home profond. L'image fournit
`/usr/local/sbin/oracle-build-cleanup`, autorisé sans mot de passe, qui refuse toute cible hors de
`/u01/<x>/<y>` et toute cible contenant `..` :
```bash
sudo /usr/local/sbin/oracle-build-cleanup /u01/app/oracle/product/19.0.0/dbhome_1
```

## Utilisation dans le workflow
```yaml
jobs:
  build-rdbms:
    runs-on: [self-hosted, linux, oracle-build]
    container:
      image: <registre>/dbops/oracle-build-base:ubi8-19c
      options: --user 54321:54321          # oracle ; 54322:54321 pour grid
      volumes:
        - /u01/gha:/u01/gha                 # disque de travail de l'hôte (≥ 60 Go)
```

## Variables et secrets GitHub utilisés par `build-base-image.yml`
- Variables : `CONTAINER_REGISTRY` (hôte du registre Artifactory), `ARTIFACTORY_USER`.
- Secret : `ARTIFACTORY_TOKEN`.

## Ce qui n'est volontairement pas dedans
- Aucun zip ni home Oracle : ils sont déballés à chaque run depuis Artifactory (19.3 de base).
- Aucun sysctl (sans effet en conteneur ; les prérequis noyau sont validés par FPP sur les cibles).
- Aucun identifiant : keystore AutoUpgrade et secrets sont injectés à l'exécution.
