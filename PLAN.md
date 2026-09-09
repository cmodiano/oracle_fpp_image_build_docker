# Plan d'implantation — Gold images Oracle 19c (RDBMS + Grid) via GitHub Actions → Artifactory → FPP

Document destiné à un agent d'implémentation. Chaque phase est indépendante, livrable et testable seule.
Respecter les décisions de la section 0 sans les rediscuter ; poser une question uniquement sur les points marqués **À CONFIRMER**.

---

## 0. Contexte et décisions figées

**Objectif.** À chaque MRP mensuel, produire deux zips de gold image (`ORACLEDBSOFTWARE` et `ORACLEGISOFTWARE`), importables tels quels par `rhpctl import image`, publiés dans Artifactory. L'import FPP est hors périmètre (fait par DBOPS).

**Décisions.**
1. Build dans un conteneur **UBI 8** sans aucun binaire Oracle pré-installé (`container/Dockerfile`, déjà écrit). Le conteneur est immuable, versionné, reconstruit uniquement quand le Dockerfile change.
2. À chaque run, le home est construit **from scratch** à partir du zip 19.3 de base (Grid : `LINUX.X64_193000_grid_home.zip`, DB : `LINUX.X64_193000_db_home.zip`) stocké dans Artifactory. Rien n'est réutilisé d'un run à l'autre.
3. Patching **par l'installeur** des deux côtés : `runInstaller -applyRU/-applyOneOffs` (DB) et `gridSetup.sh -applyRU/-applyOneOffs` (Grid), en mode software-only. Pas de `opatch apply` manuel.
4. **AutoUpgrade sert uniquement à télécharger** le jeu de patches recommandé depuis MOS (`-patch -mode download`). Il ne crée pas de home. Le GI RU est téléchargé à part (`scripts/mos_download.sh`).
5. Chemins d'installation dans le conteneur = chemins des VM (**À CONFIRMER** : `/u01/app/oracle/product/19.0.0/dbhome_1` et `/u01/app/19.0.0/grid` ?). Le chemin n'est pas contractuel (FPP relocalise au `add workingcopy`), mais on l'aligne pour éliminer une variable.
6. Une seule image par type pour tout le parc RHEL 7/8/9 ; le relink par FPP absorbe la différence d'OS. Build sur RHEL/UBI 8.
7. Runners GitHub **self-hosted** (label `oracle-build`), accès Artifactory et MOS, Podman/Docker disponibles, `/u01/gha` local ≥ 60 Go.
8. Nommage : `db_<MRP>.zip`, `gi_<MRP>.zip` avec `<MRP>` = libellé complet (ex. `19.28.0.0.250915`). Chemin Artifactory : `<repo>/{rdbms,grid}/19/<RU>/`.
9. Aucun secret dans le repo. Identifiants MOS via secrets GitHub (Grid) et keystore AutoUpgrade (DB) monté depuis l'hôte. Token Artifactory via secret GitHub.
10. Langue des commentaires et de la documentation : français. Scripts : bash strict (`set -euo pipefail`), YAML validé.

**Arborescence cible du repo.**
```
.github/workflows/oracle-gold-images.yml   # orchestration (à réécrire en mode container)
.github/workflows/build-base-image.yml     # build + push du conteneur de base
container/Dockerfile                        # UBI8 + prérequis (existant)
container/README.md
config/autoupgrade-patch.cfg               # config AutoUpgrade versionnée (download only)
config/db_swonly.rsp                       # response file DB software-only
config/grid_swonly.rsp                     # response file Grid software-only (existant)
scripts/fetch_base.sh                      # rapatrie un zip 19.3 depuis Artifactory + vérifie sha256
scripts/mos_download.sh                    # patches MOS (existant)
scripts/build_rdbms.sh                     # phase 3 + 6
scripts/build_grid.sh                      # phase 2 + 5 (existant, à ajuster)
scripts/publish_artifactory.sh             # phase 7 (existant)
scripts/verify_gold_image.sh               # contrôles avant publication
README.md / PLAN.md
```

---

## 1. Image de base (conteneur UBI 8)

**Livrable.** Image `oracle-build-base:ubi8-19c` publiée dans le registre Artifactory.

**Tâches.**
1. Relire `container/Dockerfile`. Ajuster UID/GID aux valeurs des VM (**À CONFIRMER** : sinon garder les défauts Oracle 54321/54322).
2. Résoudre les paquets absents d'UBI (`libaio-devel`, `elfutils-libelf-devel`, `libXrender-devel`, `libstdc++-devel`) : soit build sur hôte RHEL abonné, soit `--build-arg REPO_FILE=<fichier .repo interne>`. Documenter la méthode retenue dans `container/README.md`.
3. Créer `.github/workflows/build-base-image.yml` : déclenché sur modification de `container/**` et `workflow_dispatch` ; build avec Podman sur runner `oracle-build`, tag `ubi8-19c-<sha court>` + `ubi8-19c`, push vers le registre Artifactory (secret `ARTIFACTORY_TOKEN`).
4. Ajouter un smoke test dans ce workflow : `podman run --rm <image> id oracle`, `id grid`, `java -version`, `sudo -n -l`, `ls -ld /u01/app/oraInventory`.

**Critères d'acceptation.**
- `podman run --rm <image> rpm -q ksh libnsl libaio-devel glibc-devel` → tous présents.
- Users `oracle` et `grid` avec les groupes attendus ; `/etc/oraInst.loc` présent ; sudo restreint fonctionne sans mot de passe.
- Aucun fichier Oracle (`find / -name "runInstaller" -o -name "gridSetup.sh"` vide).

---

## 2. Installation Grid (software-only, patché)

**Livrable.** `scripts/build_grid.sh` produisant un Grid home patché sous `$GRID_HOME`, exécuté en tant que `grid` dans le conteneur.

**Entrées.** `--base-zip`, `--grid-home`, `--patch-dir` (contient `p<GI_RU>_*.zip`, `p6880880_*.zip`, one-offs), `--ru-patch`, `--oneoffs`, `--rsp config/grid_swonly.rsp`.

**Étapes (dans l'ordre).**
1. `unzip` du zip 19.3 dans `$GRID_HOME` (répertoire vide, créé par le script).
2. Remplacer `$GRID_HOME/OPatch` par le contenu de `p6880880_*.zip`.
3. Déballer RU et one-offs dans `$PATCH_DIR/unzipped/<patch>`.
4. `gridSetup.sh -silent -waitForCompletion -ignorePrereqFailure -responseFile <rsp> -applyRU <dir RU> [-applyOneOffs a,b]`. Codes retour acceptés : 0 et 6.
5. `sudo $GRID_HOME/root.sh` (et `orainstRoot.sh` si demandé par l'installeur).
6. `$GRID_HOME/OPatch/opatch lspatches` → `lspatches.txt` ; échec si le numéro du RU n'y figure pas.

**Notes techniques.**
- `oracle.install.crs.rootconfig.executeRootScript=false` dans le rsp ; le `root.sh` est lancé par le script.
- `-ignorePrereqFailure` est nécessaire en conteneur (sysctl, swap, mémoire). Logger les avertissements dans le job pour revue.
- Prévoir `CV_ASSUME_DISTID=OL8` en variable d'environnement si le CVU ne reconnaît pas UBI (**à tester**).

**Critères d'acceptation.**
- `opatch lspatches` liste le GI RU et OPatch ≥ version attendue.
- `$GRID_HOME/bin/crsctl query crs softwareversion -local` (ou `oraversion -compositeVersion`) renvoie la version RU cible.
- Le script est idempotent sur un répertoire vide et échoue explicitement si `$GRID_HOME` n'est pas vide.

---

## 3. Installation RDBMS (software-only, patché)

**Livrable.** `scripts/build_rdbms.sh`, même structure et même contrat que `build_grid.sh`, exécuté en tant que `oracle`.

**Étapes.**
1. `unzip` du zip 19.3 DB dans `$ORACLE_HOME`.
2. Remplacer `$ORACLE_HOME/OPatch`.
3. Déballer le DB RU, OJVM/MRP/DPBP et one-offs présents dans `$PATCH_DIR` (fournis par la phase 4).
4. `runInstaller -silent -waitForCompletion -ignorePrereqFailure -responseFile config/db_swonly.rsp -applyRU <dir RU> -applyOneOffs <liste>`. Codes retour acceptés : 0 et 6.
5. `sudo $ORACLE_HOME/root.sh`.
6. `opatch lspatches` → `lspatches.txt` ; échec si le RU attendu est absent.

**Response file `config/db_swonly.rsp` à créer** (schéma `rspfmt_dbinstall_response_schema_v19.0.0`) : `oracle.install.option=INSTALL_DB_SWONLY`, `UNIX_GROUP_NAME=oinstall`, `INVENTORY_LOCATION=/u01/app/oraInventory`, `ORACLE_HOME`, `ORACLE_BASE`, `oracle.install.db.InstallEdition=EE`, groupes `OSDBA=dba`, `OSOPER=oper`, `OSBACKUPDBA=backupdba`, `OSDGDBA=dgdba`, `OSKMDBA=kmdba`, `OSRACDBA=racdba`, `executeRootScript=false`. `ORACLE_HOME`/`ORACLE_BASE` substitués par le script (placeholders `@@...@@`).

**Critères d'acceptation.**
- `opatch lspatches` contient le RU, l'OJVM (si RECOMMENDED l'inclut) et le MRP cible.
- `$ORACLE_HOME/bin/oraversion -compositeVersion` = version cible.
- Aucun fichier de configuration d'instance créé (`$ORACLE_HOME/dbs` vide hormis `init.ora` d'origine, `network/admin` vide hormis `samples`).

---

## 4. AutoUpgrade : installation et configuration versionnée

**Livrable.** AutoUpgrade opérationnel dans le conteneur en mode téléchargement, config sous `config/autoupgrade-patch.cfg`, keystore hors repo.

**Tâches.**
1. **Distribution du jar.** Publier `autoupgrade.jar` (dernière version, MOS 2485457.1) dans Artifactory sous `<repo-tools>/autoupgrade/<version>/autoupgrade.jar`. Le workflow le télécharge à chaque run (pas dans l'image de base, pour pouvoir le monter en version). Vérifier `java -jar autoupgrade.jar -version`.
2. **Keystore MOS.** Créer une fois, à la main, sur chaque runner, sous `/u01/gha/autoupgrade/keystore` (propriétaire `oracle`, 700) :
   `java -jar autoupgrade.jar -config <cfg> -patch -load_password` → `add MOS` → `save -convert_to_auto_login` → `exit`.
   Le répertoire est monté dans le conteneur. Documenter la procédure dans `README.md` ; ne jamais le committer.
3. **Config versionnée** `config/autoupgrade-patch.cfg` : conserver `global.global_log_dir`, `global.keystore`, `patch1.folder`, `patch1.download=yes`, `patch1.patch=RECOMMENDED` (alternative commentée `RU:<ver>,MRP,OPATCH,OJVM`). **Supprimer** `source_home`/`target_home` : plus de `create_home`. Placeholders `@@...@@` substitués par le workflow.
4. **Étape de téléchargement** : `java -jar autoupgrade.jar -config patch.cfg -patch -mode download`. Le script doit ensuite lister `$PATCH_DIR` et échouer si aucun `p*.zip` contenant le RU attendu n'est présent (AutoUpgrade peut « réussir » sans rien télécharger si la config est mal interprétée).
5. **Fallback.** Si la syntaxe de `patch1.patch` ne donne pas le MRP attendu avec la version d'`autoupgrade.jar` disponible, basculer le RDBMS sur `scripts/mos_download.sh` avec les numéros de patch en input du workflow (comme le Grid). Documenter le choix retenu.

**Critères d'acceptation.**
- Un run `-mode download` dans le conteneur produit dans `$PATCH_DIR` : OPatch, DB RU, MRP et OJVM cibles, tous avec checksum vérifié par AutoUpgrade.
- Aucun identifiant MOS n'apparaît dans les logs du job (grep `MOS_PASS`, `password` sur la sortie).

---

## 5. Création de l'image Grid

**Livrable.** `gi_<MRP>.zip` + `lspatches.txt` + `manifest.json` sous `$WORK_ROOT/grid/gold/`.

**Étapes.**
1. `$GRID_HOME/gridSetup.sh -silent -createGoldImage -destinationLocation $GOLD_DIR -name gi_<MRP>.zip`.
2. `scripts/verify_gold_image.sh` : ouvrir le zip (`unzip -l`) et vérifier
   - présence de `gridSetup.sh`, `OPatch/opatch`, `inventory/ContentsXML/comps.xml` ;
   - absence de `log/`, `cfgtoollogs/`, `install/*.log`, `crs/install/crsconfig_params`, `network/admin/*.ora` (hors `samples`), fichiers `*.bak` ;
   - version dans `inventory/ContentsXML/oraclehomeproperties.xml` cohérente.
3. Générer `manifest.json` : `{type, ru, mrp, patches:[…de lspatches], base_zip_sha256, image_sha256, build_container_tag, commit, run_id, date}`.

**Critères d'acceptation.** Zip < 8 Go, contrôles de `verify_gold_image.sh` verts, manifeste complet. Test final manuel (hors agent) : `rhpctl import image -image gi_test -zip … -imagetype ORACLEGISOFTWARE` réussit sur un FPP de labo.

---

## 6. Création de l'image RDBMS

Identique à la phase 5 avec `$ORACLE_HOME/runInstaller -silent -createGoldImage -destinationLocation $GOLD_DIR -name db_<MRP>.zip`, contrôles adaptés (`runInstaller`, `OPatch/opatch`, `inventory/ContentsXML/comps.xml` ; absence de `dbs/*.ora` hors `init.ora`, `network/admin/*.ora` hors `samples`, logs). Type `ORACLEDBSOFTWARE` dans le manifeste.

---

## 7. Publication sur Artifactory

**Livrable.** `scripts/publish_artifactory.sh` (existant) durci, dépôt et conventions documentés.

**Tâches.**
1. Dépôt Generic local `oracle-gold-images-local` (**À CONFIRMER** le nom), avec un layout `{rdbms,grid}/19/<RU>/<fichier>`.
2. Upload de trois fichiers par image : `<nom>.zip`, `<nom>.lspatches.txt`, `<nom>.manifest.json`. Header `X-Checksum-Sha256` et propriétés matrix : `type`, `ru`, `mrp`, `commit`, `run`, `sha256`, `status=built`.
3. **Immutabilité** : avant upload, `HEAD` sur l'URL cible ; si l'objet existe, échec du job sauf input `force=true` (jamais d'écrasement silencieux d'une image potentiellement déjà importée dans FPP).
4. Après upload, relire les propriétés via l'API (`GET /api/storage/<path>?properties`) et vérifier le sha256 ; échec sinon.
5. Publier dans le résumé du job (`$GITHUB_STEP_SUMMARY`) les URLs, sha256 et la commande `rhpctl import image` prête à copier pour DBOPS.

**Critères d'acceptation.** `curl -I` sur l'URL renvoie `X-Checksum-Sha256` égal au calcul local ; les propriétés sont interrogeables via `GET /api/search/prop?type=ORACLEGISOFTWARE&mrp=<MRP>`.

---

## 8. Orchestration GitHub Actions (réécriture de `oracle-gold-images.yml`)

1. Inputs `workflow_dispatch` : `ru_version`, `mrp_label`, `gi_ru_patch`, `opatch_patch` (défaut `6880880`), `gi_oneoffs`, `db_oneoffs`, `build_rdbms`, `build_grid`, `force`.
2. Deux jobs parallèles `build-rdbms` et `build-grid`, chacun avec :
   ```yaml
   runs-on: [self-hosted, linux, oracle-build]
   container:
     image: <registre>/dbops/oracle-build-base:ubi8-19c
     options: --user 54321:54321      # 54322:54321 pour build-grid
     volumes:
       - /u01/gha:/u01/gha
       - /u01/gha/autoupgrade:/u01/gha/autoupgrade:ro   # keystore (build-rdbms seulement)
   ```
3. Séquence par job : checkout → `fetch_base.sh` (zip 19.3 + sha256) → téléchargement patches (phase 4 ou `mos_download.sh`) → `build_*.sh` → `verify_gold_image.sh` → `publish_artifactory.sh` → nettoyage `if: always()` (`detachHome` puis `sudo rm -rf` du home et de `$WORK_ROOT/<job>`).
4. `concurrency.group = oracle-gold-<mrp_label>`, `timeout-minutes: 180`, `df -h` en début et fin de job.
5. Job `summary` (`needs` des deux, `if: always()`) : tableau résultat + commandes d'import.
6. Ne pas ajouter de `schedule` tant que la dérivation automatique des numéros de patch n'existe pas.

---

## 9. Validation de bout en bout (definition of done)

1. `build-base-image.yml` vert, image dans le registre.
2. `oracle-gold-images.yml` lancé avec un MRP réel : les deux jobs verts en < 3 h, runner nettoyé (`df -h` identique avant/après, inventaire central sans home orphelin : `cat /u01/app/oraInventory/ContentsXML/inventory.xml`).
3. Les deux zips présents dans Artifactory avec propriétés et sha256 vérifiés.
4. Deuxième run identique → échec contrôlé sur l'immutabilité (sans `force`).
5. Hors agent, par DBOPS : import des deux images dans un FPP de labo, `rhpctl add workingcopy` sur une VM RHEL 7, 8 et 9, `opatch lspatches` identique au `lspatches.txt` publié.

---

## 10. Prérequis à fournir par l'humain avant de démarrer

- Zips 19.3 DB et Grid déposés dans Artifactory (`BASE_IMAGES_REPO`) avec leurs sha256.
- `autoupgrade.jar` déposé dans Artifactory ; `getMOSPatch.jar` (ou méthode maison) sur les runners.
- Secrets GitHub : `MOS_USER`, `MOS_PASS`, `ARTIFACTORY_TOKEN`. Variables : `ARTIFACTORY_URL`, `ARTIFACTORY_REPO`, `BASE_IMAGES_REPO`, `TOOLS_REPO`, `CONTAINER_REGISTRY`.
- Runner self-hosted label `oracle-build`, Podman, `/u01/gha` (≥ 60 Go, propriétaire `oracle:oinstall`), keystore AutoUpgrade créé.
- Réponses aux **À CONFIRMER** : chemins des homes, UID/GID, nom du dépôt Artifactory.

## 11. Règles pour l'agent

- Ne jamais committer d'identifiant, de keystore, de zip Oracle ni de patch.
- Ne pas inventer de numéros de patch ou de syntaxe AutoUpgrade non vérifiée : quand un paramètre est incertain, le tester dans le conteneur (`-mode download` est sans effet de bord) et consigner le résultat dans `README.md`.
- Un commit par phase, message préfixé `phase-N:`. Chaque phase se termine par ses critères d'acceptation exécutés et leur sortie collée dans la PR.
- Toute déviation par rapport à la section 0 doit être proposée, pas appliquée.
