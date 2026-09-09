# Oracle 19c gold images — build GitHub Actions → Artifactory → FPP

## Flux
1. `workflow_dispatch` avec RU/MRP cibles → deux jobs parallèles sur runners self-hosted.
2. **RDBMS** : AutoUpgrade télécharge les patches (keystore MOS local au runner) et crée un home patché
   depuis un home 19.3 de base, puis `runInstaller -createGoldImage`.
3. **Grid** : téléchargement du GI RU + OPatch (+ one-offs) depuis MOS, install software-only
   `gridSetup.sh -applyRU`, `root.sh`, puis `gridSetup.sh -createGoldImage`.
4. Zips + `lspatches.txt` publiés dans Artifactory avec propriétés `type`, `ru`, `mrp`, `sha256`, `commit`.
5. Import FPP hors GitHub (script / DBOPS), exemple :
   ```bash
   curl -fsS -H "Authorization: Bearer $TOKEN" -o /fpp/staging/gi_19.28.0.0.250915.zip \
     "$ART/oracle-gold-images-local/grid/19/19.28/gi_19.28.0.0.250915.zip"
   sha256sum -c   # comparer à la propriété sha256
   rhpctl import image -image gi_19_28_0_0_250915 -zip /fpp/staging/gi_19.28.0.0.250915.zip \
     -imagetype ORACLEGISOFTWARE -series gi19
   rhpctl import image -image db_19_28_0_0_250915 -zip /fpp/staging/db_19.28.0.0.250915.zip \
     -imagetype ORACLEDBSOFTWARE -series db19
   ```

## Prérequis runner (label `oracle-build`)
- OL8/RHEL8, paquets `oracle-database-preinstall-19c`, users `oracle`/`grid`, groupes ASM, sudo NOPASSWD pour `root.sh` et `rm -rf` sous `/u01`.
- ≥ 60 Go libres sous `/u01` (home DB + home GI + patches + zips).
- Java 11+ ; `autoupgrade.jar` (version patching, ≥ 24.x) sous `/u01/app/oracle/autoupgrade`.
- Keystore AutoUpgrade créé une fois : `java -jar autoupgrade.jar -config patch.cfg -patch -load_password`
  → `add MOS`, puis `save -convert_to_auto_login`, `exit`.
- Home 19.3 de base installé (software-only) : `/u01/app/oracle/product/19.0.0/dbhome_base`.
- Zip Grid 19.3 de base disponible (ou rapatrié depuis Artifactory `BASE_IMAGES_REPO` dans une étape préalable).
- `getMOSPatch.jar` (ou équivalent) pour le job Grid.

## Secrets / variables GitHub
- Secrets : `MOS_USER`, `MOS_PASS` (Grid seulement), `ARTIFACTORY_TOKEN`.
- Variables : `ARTIFACTORY_URL`, `ARTIFACTORY_REPO`, `BASE_IMAGES_REPO`.

## Points à valider en pilote
- Syntaxe exacte de `patch1.patch` et du mode `create_home` selon la version d'`autoupgrade.jar` déployée
  (la doc évolue vite ; tester `-mode download` seul d'abord).
- `gridSetup.sh -createGoldImage` après `root.sh` : vérifier que le zip est bien accepté par `rhpctl import image`
  (FPP vérifie version et plateforme à l'import).
- Nettoyage de l'inventaire central (`oraInventory`) entre deux runs : le `detachHome` du job doit suffire,
  sinon dédier un `INVENTORY_LOCATION` par run.
- Un runner = un build à la fois (`concurrency` côté GitHub + un seul runner par host).
