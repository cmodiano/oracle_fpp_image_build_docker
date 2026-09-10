# syntax=docker/dockerfile:1
# Conteneur de build pour gold images Oracle 19c (RDBMS + Grid) — UBI 8, AUCUN binaire Oracle.
# Reproduit ce que fait le paquet oracle-database-preinstall-19c sur OL8 : paquets, users/groupes,
# limites, arborescence. Les sysctl du preinstall n'ont pas de sens dans un conteneur et sont omis.
#
# Build : docker build -t oracle-build-base:ubi8 --build-arg REPO_FILE=desjardins.repo container/
# (docker ne transmet pas l'entitlement RHEL de l'hôte : fournir un .repo interne via REPO_FILE)

FROM registry.access.redhat.com/ubi8/ubi:latest

ARG ORACLE_UID=54321
ARG GRID_UID=54322
ARG OINSTALL_GID=54321
ARG DBA_GID=54322
ARG OPER_GID=54323
ARG BACKUPDBA_GID=54324
ARG DGDBA_GID=54325
ARG KMDBA_GID=54326
ARG ASMDBA_GID=54327
ARG ASMOPER_GID=54328
ARG ASMADMIN_GID=54329
ARG RACDBA_GID=54330
# Fichier .repo interne (Satellite / Artifactory RPM remote) pour les paquets absents d'UBI.
# Laisser vide si l'hôte de build est un RHEL abonné.
ARG REPO_FILE=""

LABEL org.opencontainers.image.title="oracle-build-base" \
      org.opencontainers.image.description="UBI8 + prérequis Oracle 19c, sans binaires Oracle" \
      org.opencontainers.image.vendor="Desjardins DBOPS"

# --- Dépôts internes optionnels -------------------------------------------------------------
COPY ${REPO_FILE:-Dockerfile} /tmp/repo-input
RUN if [ -n "${REPO_FILE}" ]; then cp /tmp/repo-input /etc/yum.repos.d/internal.repo; fi; rm -f /tmp/repo-input

# --- Paquets : liste des dépendances d'oracle-database-preinstall-19c (OL8) + outillage build ---
RUN dnf -y install --setopt=install_weak_deps=False \
      bc binutils compat-openssl10 elfutils-libelf elfutils-libelf-devel fontconfig \
      glibc glibc-devel ksh libaio libaio-devel libX11 libXau libXi libXtst libXrender \
      libXrender-devel libgcc libnsl libstdc++ libstdc++-devel libxcb make net-tools \
      nfs-utils policycoreutils policycoreutils-python-utils smartmontools sysstat \
      unixODBC procps-ng hostname util-linux psmisc which tar gzip unzip openssl \
      java-11-openjdk-headless sudo git curl jq \
 && dnf clean all && rm -rf /var/cache/dnf

# --- Groupes et utilisateurs (mêmes UID/GID que les VM, surchargés par --build-arg) ----------
RUN groupadd -g ${OINSTALL_GID} oinstall \
 && groupadd -g ${DBA_GID} dba \
 && groupadd -g ${OPER_GID} oper \
 && groupadd -g ${BACKUPDBA_GID} backupdba \
 && groupadd -g ${DGDBA_GID} dgdba \
 && groupadd -g ${KMDBA_GID} kmdba \
 && groupadd -g ${ASMDBA_GID} asmdba \
 && groupadd -g ${ASMOPER_GID} asmoper \
 && groupadd -g ${ASMADMIN_GID} asmadmin \
 && groupadd -g ${RACDBA_GID} racdba \
 && useradd -u ${ORACLE_UID} -g oinstall \
      -G dba,oper,backupdba,dgdba,kmdba,asmdba,racdba -m -s /bin/bash oracle \
 && useradd -u ${GRID_UID} -g oinstall \
      -G dba,asmdba,asmoper,asmadmin,racdba -m -s /bin/bash grid

# --- Limites (équivalent de /etc/security/limits.d/oracle-database-preinstall-19c.conf) -------
RUN for u in oracle grid; do printf '%s\n' \
      "$u soft nofile 1024" "$u hard nofile 65536" \
      "$u soft nproc 16384" "$u hard nproc 16384" \
      "$u soft stack 10240" "$u hard stack 32768" \
      "$u soft memlock 134217728" "$u hard memlock 134217728" \
      >> /etc/security/limits.d/oracle-database-preinstall-19c.conf; done

# --- Arborescence et inventaire ---------------------------------------------------------------
RUN mkdir -p /u01/app/oraInventory /u01/app/oracle /u01/app/grid /u01/gha \
 && chown -R oracle:oinstall /u01 \
 && chown grid:oinstall /u01/app/grid \
 && chmod -R 775 /u01 \
 && printf 'inventory_loc=/u01/app/oraInventory\ninst_group=oinstall\n' > /etc/oraInst.loc \
 && chown oracle:oinstall /etc/oraInst.loc

# --- sudo restreint : root.sh et orainstRoot.sh uniquement -----------------------------------
RUN printf '%s\n' \
      'Defaults:oracle,grid !requiretty' \
      'oracle ALL=(root) NOPASSWD: /u01/app/oraInventory/orainstRoot.sh, /u01/app/oracle/product/*/*/root.sh' \
      'grid   ALL=(root) NOPASSWD: /u01/app/oraInventory/orainstRoot.sh, /u01/app/*/grid/root.sh' \
      > /etc/sudoers.d/oracle-build && chmod 440 /etc/sudoers.d/oracle-build

ENV ORACLE_BASE=/u01/app/oracle \
    LANG=en_US.UTF-8 \
    TZ=America/Toronto

USER oracle
WORKDIR /u01/gha
CMD ["/bin/bash"]
