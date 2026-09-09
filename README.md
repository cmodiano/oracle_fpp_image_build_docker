# Oracle 19c gold images — GitHub Actions → Artifactory → FPP

Produit, à chaque MRP mensuel, deux zips de gold image importables tels quels par
`rhpctl import image` :

| Image | Fichier | `-imagetype` |
| --- | --- | --- |
| RDBMS | `db_<MRP>.zip` | `ORACLEDBSOFTWARE` |
| Grid Infrastructure | `gi_<MRP>.zip` | `ORACLEGISOFTWARE` |

L'import dans FPP est fait par DBOPS, hors de ce dépôt.

---

## 1. Principes

1. **Build en conteneur.** Tout s'exécute dans `oracle-build-base` (UBI 8, aucun binaire Oracle).
   Le conteneur est immuable et n'est reconstruit que quand `container/**` change.
2. **Home construit from scratch à chaque run.** On part du zip 19.3 de base stocké dans
   Artifactory. Rien n'est réutilisé d'un run à l'autre : pas de home « de référence » qui dérive.
3. **Patching par l'installeur, jamais par `opatch apply`.** `runInstaller -applyRU/-applyOneOffs`
   côté DB, `gridSetup.sh -applyRU/-applyOneOffs` côté Grid, en mode software-only.
4. **Une seule image par type** pour tout le parc RHEL 7/8/9 : le relink fait par FPP au
   `add workingcopy` absorbe la différence d'OS. Build sur UBI 8.
5. **Rien de sensible dans le dépôt** : ni zip Oracle, ni patch, ni identifiant, ni keystore.

---

## 2. Vue d'ensemble

```mermaid
flowchart TB
  subgraph base["build-base-image.yml (seulement si container/** change)"]
    C1[container/Dockerfile] --> C2[podman build + smoke test] --> C3[(Registre Artifactory<br/>oracle-build-base:ubi8-19c)]
  end

  D[workflow_dispatch<br/>mrp_label ou 'latest'] --> RS[Job resolve<br/>config/patches/&lt;mrp&gt;.json]
  RS --> R & G

  subgraph R["Job build-rdbms — conteneur, user oracle"]
    R1[fetch_base.sh<br/>zip 19.3 DB] --> R2[autoupgrade_download.sh<br/>-patch -mode download] --> R3[build_rdbms.sh<br/>runInstaller -applyRU] --> R4[runInstaller -createGoldImage]
  end

  subgraph G["Job build-grid — conteneur, user grid"]
    G1[fetch_base.sh<br/>zip 19.3 Grid] --> G2[mos_download.sh<br/>getMOSPatch] --> G3[build_grid.sh<br/>gridSetup.sh -applyRU] --> G4[gridSetup.sh -createGoldImage]
  end

  R4 --> V[verify_gold_image.sh<br/>contrôles + manifest.json]
  G4 --> V
  V --> P[publish_artifactory.sh<br/>sha256 + propriétés + immutabilité]
  P --> A[(Artifactory<br/>{rdbms,grid}/19/RU/)]
  A -.->|hors GitHub, par DBOPS| F[rhpctl import image]
```

---

## 3. Pourquoi deux processus différents

**AutoUpgrade ne gère que les homes RDBMS.** Son mode `-patch` connaît les Release Updates, MRP,
OJVM et DPBP de la base de données ; il ne sait rien des homes Grid Infrastructure. Il n'existe donc
aucun outil unique couvrant les deux côtés, et le pipeline assume cette asymétrie plutôt que de la
masquer.

| | RDBMS | Grid Infrastructure |
| --- | --- | --- |
| Découverte des patches | AutoUpgrade `patch1.patch=RECOMMENDED` | numéros fournis en input du workflow |
| Téléchargement MOS | AutoUpgrade `-patch -mode download` | `getMOSPatch` (`scripts/mos_download.sh`) |
| Authentification MOS | keystore AutoUpgrade, local au runner | secrets GitHub `MOS_USER` / `MOS_PASS` |
| Installation | `runInstaller -silent -applyRU …` | `gridSetup.sh -silent -applyRU …` |
| Utilisateur | `oracle` (54321) | `grid` (54322) |
| Gold image | `runInstaller -createGoldImage` | `gridSetup.sh -createGoldImage` |

AutoUpgrade est cantonné au **téléchargement**. Il ne crée aucun home : `source_home` et
`target_home` sont volontairement absents de `config/autoupgrade-patch.cfg`. Les deux homes sont
donc construits exactement de la même façon — par l'installeur — ce qui garde un seul mode de
défaillance à diagnostiquer.

---

## 4. Processus RDBMS, étape par étape

| # | Étape | Script |
| --- | --- | --- |
| 1 | Nettoyage de `$JOB_ROOT` et de `$ORACLE_HOME` | `oracle-build-cleanup` (helper root de l'image) |
| 2 | Rapatriement du zip 19.3 DB + contrôle sha256 | `scripts/fetch_base.sh` |
| 3 | Rapatriement de `autoupgrade.jar` | `scripts/fetch_base.sh` |
| 4 | Génération de `patch.cfg` (substitution des `@@…@@`) | `sed` dans le workflow |
| 5 | Téléchargement des patches, puis contrôle que le RU et OPatch sont bien là | `scripts/autoupgrade_download.sh` |
| 6 | Unzip 19.3 → `$ORACLE_HOME`, remplacement d'OPatch, unzip RU + one-offs | `scripts/build_rdbms.sh` |
| 7 | `runInstaller -silent -applyRU … -applyOneOffs …` (rc 0 ou 6 acceptés) | idem |
| 8 | `orainstRoot.sh` si présent, puis `root.sh` via sudo | idem |
| 9 | `opatch lspatches` → échec si le RU n'y figure pas ; `oraversion -compositeVersion` | idem |
| 10 | `runInstaller -silent -createGoldImage` | idem |

**One-offs.** `db_oneoffs=auto` (défaut) applique tout ce qu'AutoUpgrade a téléchargé sauf le RU et
OPatch — c'est-à-dire l'OJVM, le MRP et le DPBP du jeu `RECOMMENDED`. Une liste explicite de numéros
force le contenu ; `none` n'applique que le RU.

**Keystore MOS.** Créé une seule fois à la main sur le runner, monté en lecture seule dans le
conteneur. Aucun identifiant MOS ne transite par le workflow côté RDBMS.

---

## 5. Processus Grid, étape par étape

| # | Étape | Script |
| --- | --- | --- |
| 1 | Nettoyage de `$JOB_ROOT` et de `$GRID_HOME` | `oracle-build-cleanup` |
| 2 | Rapatriement du zip 19.3 Grid + contrôle sha256 | `scripts/fetch_base.sh` |
| 3 | Rapatriement de `getMOSPatch.jar` | `scripts/fetch_base.sh` |
| 4 | Téléchargement du GI RU, d'OPatch et des one-offs demandés | `scripts/mos_download.sh` |
| 5 | Unzip 19.3 → `$GRID_HOME`, remplacement d'OPatch, unzip RU + one-offs | `scripts/build_grid.sh` |
| 6 | `gridSetup.sh -silent -applyRU … -applyOneOffs …` (rc 0 ou 6 acceptés) | idem |
| 7 | `orainstRoot.sh` si présent, puis `root.sh` via sudo | idem |
| 8 | `opatch lspatches` → échec si le RU n'y figure pas | idem |
| 9 | `gridSetup.sh -silent -createGoldImage` | idem |

`-ignorePrereqFailure` est nécessaire en conteneur (sysctl, swap, mémoire non représentatifs) et
`CV_ASSUME_DISTID=OL8` est exporté parce que le CVU ne reconnaît pas UBI.

---

## 6. Étapes communes aux deux images

**`scripts/verify_gold_image.sh`** — refuse la publication si :
- `OPatch/opatch`, `inventory/ContentsXML/comps.xml`, `oraclehomeproperties.xml` ou l'installeur
  (`runInstaller` / `gridSetup.sh`) manquent ;
- le zip contient `log/`, `cfgtoollogs/`, des `install/*.log`, des `*.bak`, des `.ora` hors
  `network/admin/samples/`, un `crsconfig_params` (Grid) ou un fichier de paramètres dans `dbs/`
  autre que `init.ora` (RDBMS) ;
- la version composite ne correspond pas au RU demandé ;
- le zip dépasse 8 Go.

Il produit `manifest.json` : `type`, `ru`, `mrp`, `version`, `patches[]` (issus de `lspatches`),
`base_zip_sha256`, `image_sha256`, `image_size`, `build_container_tag`, `commit`, `run_id`, `date`.

**`scripts/publish_artifactory.sh`** — trois fichiers par image (`.zip`, `.lspatches.txt`,
`.manifest.json`) dans `{rdbms,grid}/19/<RU>/`, avec `X-Checksum-Sha256` et propriétés matrix
(`type`, `ru`, `mrp`, `commit`, `run`, `sha256`, `status=built`). Un `HEAD` précède l'upload :
**un objet existant n'est jamais écrasé** sans l'input `force`, parce qu'il a pu être importé dans
FPP. Après upload, le sha256 et la propriété `sha256` sont relus côté serveur.

Chaque job termine par un `detachHome` puis un nettoyage `if: always()`, et affiche `df -h` avant
et après.

---

## 7. Acquisition des numéros de patch

Les numéros ne sont plus saisis au lancement : ils vivent dans une **table versionnée**,
`config/patches/<mrp_label>.json`, lue par le job `resolve`
(`scripts/resolve_patches.sh`). Un build est donc rejouable à l'identique et chaque changement de
numéro passe par une PR.

```json
{
  "mrp_label": "19.28.0.0.250915",
  "ru_version": "19.28",
  "db_ru_patch": "38xxxxxx",
  "gi_ru_patch": "38xxxxxx",
  "gi_oneoffs": "38xxxxxx,38xxxxxx",
  "db_oneoffs": "auto",
  "opatch_patch": "6880880"
}
```

Le résolveur refuse le run si une clé obligatoire manque, si `mrp_label` diffère du nom du fichier,
si `mrp_label` ne commence pas par `ru_version`, ou si un numéro n'est pas strictement numérique —
ces valeurs alimentent des chemins Artifactory et des lignes de commande. Détail des champs :
[`config/patches/README.md`](config/patches/README.md).

Le workflow ne prend plus que quatre inputs : `mrp_label` (`latest` par défaut, = la table la plus
récente au tri de version), `build_rdbms`, `build_grid`, `force`.

**Ce qui reste manuel** : relever les numéros du mois sur MOS et remplir le fichier. Côté RDBMS,
`patch1.patch=RECOMMENDED` fait déjà la sélection — `db_ru_patch` ne sert qu'à vérifier que le
téléchargement a ramené le bon RU et à désigner le répertoire passé à `-applyRU`. Côté Grid, il
n'existe pas d'équivalent : AutoUpgrade ne couvre que les homes RDBMS.

## 8. Runbook mensuel

1. Relever les numéros de patch du mois (DB RU, GI RU, MRP GI) sur MOS.
2. `cp config/patches/TEMPLATE.json config/patches/<mrp_label>.json`, remplir, PR, merge.
3. `workflow_dispatch` sur `oracle-gold-images.yml` — `mrp_label=latest` suffit.
4. `resolve` valide la table, puis les deux jobs tournent en parallèle
   (< 3 h attendu, `timeout-minutes: 180`).
5. Lire le résumé du run : URLs, sha256, commandes `rhpctl import image` prêtes à copier.
6. Transmettre à DBOPS pour l'import FPP.

Rejouer le même MRP sans `force` échoue volontairement à la publication (immutabilité).

## 9. Import côté FPP (DBOPS)

```bash
curl -fsS -H "Authorization: Bearer $TOKEN" -o /fpp/staging/gi_19.28.0.0.250915.zip \
  "$ART/$ARTIFACTORY_REPO/grid/19/19.28/gi_19.28.0.0.250915.zip"
sha256sum /fpp/staging/gi_19.28.0.0.250915.zip   # comparer au manifeste / à la propriété sha256

rhpctl import image -image gi_19_28_0_0_250915 -zip /fpp/staging/gi_19.28.0.0.250915.zip \
  -imagetype ORACLEGISOFTWARE -series gi19
rhpctl import image -image db_19_28_0_0_250915 -zip /fpp/staging/db_19.28.0.0.250915.zip \
  -imagetype ORACLEDBSOFTWARE -series db19
```

---

## 10. Arborescence

```
.github/workflows/build-base-image.yml   # build + smoke test + push du conteneur de base
.github/workflows/oracle-gold-images.yml # orchestration des deux gold images
container/Dockerfile                     # UBI 8 + prérequis 19c (voir container/README.md)
config/patches/<mrp_label>.json          # table de patches du mois (source unique des numéros)
config/autoupgrade-patch.cfg             # AutoUpgrade, téléchargement seul
config/db_swonly.rsp                     # response file DB software-only
config/grid_swonly.rsp                   # response file Grid software-only
scripts/resolve_patches.sh               # lit la table de patches et alimente les jobs
scripts/fetch_base.sh                    # récupère un artefact Artifactory + vérifie le sha256
scripts/autoupgrade_download.sh          # AutoUpgrade -mode download + contrôle du contenu
scripts/mos_download.sh                  # patches GI depuis MOS
scripts/build_rdbms.sh                   # home DB patché + gold image
scripts/build_grid.sh                    # home Grid patché + gold image
scripts/verify_gold_image.sh             # contrôles avant publication + manifest.json
scripts/publish_artifactory.sh           # publication immuable + relecture des métadonnées
```

---

## 11. Chemins et identités

| Élément | Valeur |
| --- | --- |
| `ORACLE_HOME` | `/u01/app/oracle/product/19.0.0/dbhome_1` |
| `ORACLE_BASE` | `/u01/app/oracle` |
| `GRID_HOME` | `/u01/app/19.0.0/grid` |
| Inventaire | `/u01/app/oraInventory` (dans le conteneur, jetable) |
| Espace de travail | `/u01/gha` (monté depuis l'hôte) |
| UID/GID | `oracle=54321`, `grid=54322`, `oinstall=54321`, `dba=54322` |

Le chemin n'est pas contractuel — FPP relocalise au `add workingcopy` — mais reste aligné sur les VM
pour éliminer une variable.

---

## 12. Prérequis

**Runner self-hosted, label `oracle-build`**
- Podman, accès Artifactory et MOS, ≥ 60 Go libres sous `/u01/gha` (propriétaire `oracle:oinstall`).
- Keystore AutoUpgrade créé **une seule fois** sous `/u01/gha/autoupgrade/keystore`
  (propriétaire `oracle`, mode 700), jamais committé :
  ```bash
  java -jar autoupgrade.jar -config patch.cfg -patch -load_password
  # add MOS
  # save -convert_to_auto_login
  # exit
  ```
- Un seul build à la fois par runner (`concurrency` côté GitHub).

**Artifactory**
- `BASE_IMAGES_REPO` : `oracle/19.3/LINUX.X64_193000_db_home.zip`, `…_grid_home.zip`.
- `TOOLS_REPO` : `autoupgrade/<version>/autoupgrade.jar`, `getmospatch/getMOSPatch.jar`.
- `ARTIFACTORY_REPO` : dépôt Generic local, layout `{rdbms,grid}/19/<RU>/<fichier>`.
- Registre de conteneurs pour `dbops/oracle-build-base`.

**Secrets GitHub** : `MOS_USER`, `MOS_PASS` (Grid uniquement), `ARTIFACTORY_TOKEN`.
**Variables GitHub** : `ARTIFACTORY_URL`, `ARTIFACTORY_USER`, `ARTIFACTORY_REPO`,
`BASE_IMAGES_REPO`, `TOOLS_REPO`, `CONTAINER_REGISTRY`, `AUTOUPGRADE_VERSION`.

---

## 13. Points à valider en pilote

- Syntaxe exacte de `patch1.patch` selon la version d'`autoupgrade.jar` déployée : si `RECOMMENDED`
  ne ramène pas le MRP attendu, basculer sur `RU:<ver>,MRP,OPATCH,OJVM` (ligne commentée dans
  `config/autoupgrade-patch.cfg`) ou sur `mos_download.sh`, comme pour le Grid.
- `CV_ASSUME_DISTID=OL8` : confirmer que le CVU accepte UBI 8 avec cette valeur.
- Acceptation par `rhpctl import image` des zips produits en conteneur (FPP vérifie version et
  plateforme à l'import).
- UID/GID réels des VM du parc, si différents des défauts Oracle.
