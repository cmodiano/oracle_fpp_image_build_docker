# Oracle 19c gold images — build GitHub Actions → Artifactory → FPP

Produit à chaque MRP deux zips de gold image (`db_<MRP>.zip`, `gi_<MRP>.zip`) importables tels quels
par `rhpctl import image`. L'import FPP est fait par DBOPS, hors de ce dépôt.

## Flux
1. `build-base-image.yml` construit l'image de build UBI 8 (aucun binaire Oracle) et la pousse dans
   le registre Artifactory. Rejoué uniquement quand `container/**` change.
2. `oracle-gold-images.yml` (`workflow_dispatch`) lance deux jobs parallèles, chacun **dans ce
   conteneur**, sur runner self-hosted `oracle-build`.
3. **RDBMS** : zip 19.3 de base rapatrié d'Artifactory → AutoUpgrade `-mode download` (téléchargement
   seul, keystore MOS local au runner) → `runInstaller -applyRU/-applyOneOffs` software-only →
   `root.sh` → `runInstaller -createGoldImage`.
4. **Grid** : zip 19.3 de base → patches GI depuis MOS (`getMOSPatch`) → `gridSetup.sh -applyRU`
   software-only → `root.sh` → `gridSetup.sh -createGoldImage`.
5. `verify_gold_image.sh` contrôle le contenu du zip et produit `manifest.json`.
6. `publish_artifactory.sh` publie zip + `lspatches.txt` + `manifest.json` avec sha256 et propriétés,
   sans jamais écraser un objet existant (sauf input `force`).

Le home est reconstruit **from scratch** à chaque run : rien n'est réutilisé d'un run à l'autre.

### Import côté FPP (DBOPS)
```bash
curl -fsS -H "Authorization: Bearer $TOKEN" -o /fpp/staging/gi_19.28.0.0.250915.zip \
  "$ART/$ARTIFACTORY_REPO/grid/19/19.28/gi_19.28.0.0.250915.zip"
sha256sum /fpp/staging/gi_19.28.0.0.250915.zip   # comparer à la propriété sha256 / au manifeste
rhpctl import image -image gi_19_28_0_0_250915 -zip /fpp/staging/gi_19.28.0.0.250915.zip \
  -imagetype ORACLEGISOFTWARE -series gi19
rhpctl import image -image db_19_28_0_0_250915 -zip /fpp/staging/db_19.28.0.0.250915.zip \
  -imagetype ORACLEDBSOFTWARE -series db19
```

## Arborescence
```
.github/workflows/build-base-image.yml   # build + smoke test + push du conteneur de base
.github/workflows/oracle-gold-images.yml # orchestration des deux gold images
container/                               # Dockerfile UBI 8 + doc (voir container/README.md)
config/autoupgrade-patch.cfg             # AutoUpgrade, téléchargement seul
config/db_swonly.rsp                     # response file DB software-only
config/grid_swonly.rsp                   # response file Grid software-only
scripts/fetch_base.sh                    # récupère un artefact Artifactory + vérifie le sha256
scripts/autoupgrade_download.sh          # AutoUpgrade -mode download + contrôle du contenu
scripts/mos_download.sh                  # patches GI depuis MOS
scripts/build_rdbms.sh                   # home DB patché + gold image
scripts/build_grid.sh                    # home Grid patché + gold image
scripts/verify_gold_image.sh             # contrôles avant publication + manifest.json
scripts/publish_artifactory.sh           # publication immuable + relecture des métadonnées
```

## Chemins et identités
| Élément | Valeur |
| --- | --- |
| `ORACLE_HOME` | `/u01/app/oracle/product/19.0.0/dbhome_1` |
| `ORACLE_BASE` | `/u01/app/oracle` |
| `GRID_HOME` | `/u01/app/19.0.0/grid` |
| Inventaire | `/u01/app/oraInventory` |
| UID/GID | `oracle=54321`, `grid=54322`, `oinstall=54321`, `dba=54322` |

Le chemin n'est pas contractuel (FPP relocalise au `add workingcopy`) mais reste aligné sur les VM.

## Prérequis runner (label `oracle-build`)
- Podman, ≥ 60 Go libres sous `/u01/gha` (propriétaire `oracle:oinstall`), accès Artifactory et MOS.
- Keystore AutoUpgrade créé **une seule fois**, à la main, sous `/u01/gha/autoupgrade/keystore`
  (propriétaire `oracle`, mode 700) — il n'est jamais committé :
  ```bash
  java -jar autoupgrade.jar -config patch.cfg -patch -load_password
  # add MOS
  # save -convert_to_auto_login
  # exit
  ```
- Un seul build à la fois par runner (`concurrency` côté GitHub).

## Prérequis Artifactory
- `BASE_IMAGES_REPO` : `oracle/19.3/LINUX.X64_193000_db_home.zip` et `…_grid_home.zip`.
- `TOOLS_REPO` : `autoupgrade/<version>/autoupgrade.jar`, `getmospatch/getMOSPatch.jar`.
- `ARTIFACTORY_REPO` : dépôt Generic local des gold images, layout `{rdbms,grid}/19/<RU>/<fichier>`.
- Registre de conteneurs pour `dbops/oracle-build-base`.

## Secrets et variables GitHub
- Secrets : `MOS_USER`, `MOS_PASS` (Grid uniquement), `ARTIFACTORY_TOKEN`.
- Variables : `ARTIFACTORY_URL`, `ARTIFACTORY_USER`, `ARTIFACTORY_REPO`, `BASE_IMAGES_REPO`,
  `TOOLS_REPO`, `CONTAINER_REGISTRY`, `AUTOUPGRADE_VERSION`.

## Points à valider en pilote
- Syntaxe exacte de `patch1.patch` selon la version d'`autoupgrade.jar` déployée : si `RECOMMENDED`
  ne ramène pas le MRP attendu, basculer sur `RU:<ver>,MRP,OPATCH,OJVM` (ligne commentée dans
  `config/autoupgrade-patch.cfg`) ou sur `mos_download.sh` comme pour le Grid.
- `CV_ASSUME_DISTID=OL8` : à confirmer que le CVU accepte UBI 8 avec cette valeur.
- Acceptation par `rhpctl import image` des zips produits en conteneur (vérification version et
  plateforme faite à l'import par FPP).
- Nettoyage de l'inventaire central entre deux runs : l'inventaire vit dans le conteneur (jetable),
  seul `/u01/gha` est monté depuis l'hôte.
