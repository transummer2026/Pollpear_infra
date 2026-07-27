# Roadmap déploiement

## 1. dockerfile prod

### priority high

- [x] frontend : stage prod = nginx:alpine + `dist/` + conf SPA (fallback index.html)
  - note : les `VITE_*` sont bakées au build → l'URL de l'API est figée au build de l'image
- [x] backend : `nest build` + CLI prisma conservé dans l'image (pour `migrate deploy` au deploy)
  - piège : le `postinstall` lance `prisma generate` → pas de `npm ci --omit=dev` naïf
  - healthchecks : cf. section 2
- [x] gateway : code attendu sous 1-2 jours → build target musl (`x86_64-unknown-linux-musl`),
      runtime alpine
  - préférer rustls à openssl pour éviter la friction musl
  - healthchecks : cf. section 2

### priority low

- [ ] ai : pas de code encore, rien à faire pour l'instant

## 2. healthchecks

objectif : chaque service expose une route `/health`, compose passe tout en `service_healthy`, le
deploy valide avec `up --wait` (cf. section 5)

- [x] backend : créer la route `/health` (n'existe pas dans le code) ; healthcheck compose en
      `node -e "fetch(...)"` — node:slim n'a ni curl ni wget
- [x] frontend : healthcheck du stage prod (nginx) en wget ; l'actuel `node healthcheck.ts` pointe
      vers un fichier inexistant
- [x] gateway : route `/health` à prévoir dès l'écriture du code ; healthcheck en wget (alpine n'a
      pas curl)
- [x] ai : route `/health` quand le code arrivera (healthcheck déjà en TODO dans compose.yml)
- déjà en place ✓ : nginx (`/healthz`), postgres (`pg_isready`), redis (`redis-cli ping`), vault
  (`vault status`), monitoring (wget/curl)

## 3. compose

- [x] compose.yml -> rework : redevient le builder des seuls services pollpear +
      postgres/redis/vault (le monitoring en sort)
  - fix : virgules parasites dans les env de gateway (`${FRONTEND_URL},` → la virgule fait partie de
    la valeur)
  - healthchecks (fichiers fantômes, passage en `service_healthy`) : cf. section 2
- [x] compose.monitoring.yml -> nouveau : prometheus, grafana, alertmanager + exporters
  - inclus par staging, et par dev à la demande (cible make dédiée)
  - adapter les `-f` du Makefile
- [x] compose.dev.yml -> rework : lance uniquement les services pollpear
- [x] compose.staging.yml -> rework
  - fix : clé `frontend:` manquante (le bloc `build: target: dev` est rattaché à gateway → frontend
    build le stub prod vide = page nginx par défaut)
  - fix : désactiver `ai` (profile disabled comme gateway) tant que pas de code
  - services internes en build local (buildés au deploy), images infra depuis GHCR
- [x] compose.prod.yml -> différé (YAGNI) : les différences avec staging (domaine, htpasswd,
      ressources) se gèrent par variables d'env sur le même fichier
- vault staging : cf. section 10 (en suspens)

## 4. images infra (ghcr)

- [x] action manuelle de mirror Docker Hub → GHCR (`mirrror.yml` + `mirror-images.sh` dans le
      .github de l'org) : idempotente par digest, multi-arch forcé, couvre les 11 images des
      composes
- note : tags `latest` assumés — le mirror est manuel, le latest GHCR ne bouge que sur relance
  volontaire (attention : une relance met à jour toutes les images qui ont bougé upstream)
- note : les services internes ne sont pas pushés — buildés sur le serveur au moment du deploy
- [ ] pull depuis le serveur : packages GHCR privés → docker login dans le job de deploy avec le
      `GITHUB_TOKEN` éphémère (`permissions: packages: read`), rien de stocké sur le serveur
  - prérequis : autoriser le repo du workflow de deploy sur chaque package GHCR (settings du package
    → manage Actions access)

## 5. ci deploy

flux : bouton README (lien) -> PR dev→staging -> une CI remplit la description -> merge -> deploy

- [ ] créer le README racine de Pollpear (le bouton n'a nulle part où vivre aujourd'hui)
- [ ] bouton = lien compare `staging...dev?quick_pull=1` dans le README
- [ ] workflow « PR description » : à l'ouverture d'une PR vers staging, un script (`scripts/*.sh`)
      génère la description (commits/diff entre staging et dev) et met à jour le body de la PR
- [ ] workflow deploy au merge sur staging (`push: staging`), `runs-on: [self-hosted, staging]`
      (runner `pollpear-staging` déjà online)
  1. checkout avec `submodules: recursive` (sinon les contextes de build sont vides)
  2. docker login GHCR avec le `GITHUB_TOKEN` éphémère (cf. section 4)
  3. up de postgres seul, puis migrations en one-off :
     `compose run --rm backend npx prisma migrate deploy` (CLI prisma dans l'image, cf. section 1)
  4. `compose up -d --build --wait` (le `--wait` valide les healthchecks, cf. section 2)
- [ ] `concurrency` group sur le workflow deploy : jamais deux deploys en parallèle
- [ ] rollback : revert du merge sur staging -> push -> le deploy se rejoue sur l'état précédent
- dépendance : le `.env` doit être livré sur le serveur avant le premier run (cf. manquants)

## 6. certificats

- [x] `scripts/ensure-certs.sh` : idempotent, appelé par `make up_prod` avant le up — skip si cert
      LE présent, sinon auto-signé 1 jour -> nginx seul -> certbot certonly webroot (best-effort :
      repli auto-signé si LE échoue, nginx ne reste jamais sans cert) -> reload. htpasswd exigé
      seulement si `NGINX_AUTH != off`
- [x] renouvellement codé : conteneur certbot en boucle `certbot renew` toutes les 12h
      (`nginx/renew-loop.sh`) + reload nginx toutes les 6h (`nginx/99-cert-reload.sh`)
- [ ] à valider en réel au premier passage serveur (dépend DNS + .env + htpasswd, cf. checklist)

## 7. ansible (provisioning serveur)

```warning
docker doit passer par le repo apt officiel (docker-ce + plugin compose) :
brew n'installe pas le daemon sous linux
```

objectif : partir d'un serveur vierge (VPS debian/ubuntu) et tout installer — le VPS actuel a été
provisionné à la main pour le runner, ansible doit couvrir cette partie aussi

- [ ] structure : `Pollpear_infra/ansible/` — playbook + inventory + `group_vars/staging`
      (vars.yml + vault.yml chiffré ansible-vault), roles (base, docker, runner, pollpear),
      idempotent (rejouable)
- [ ] base système : apt update & upgrade, unattended-upgrades, timezone + NTP
- [ ] deux users, deux rôles : admin/ansible (sudo NOPASSWD, pour le provisioning) + user de service
      pour le runner (groupe docker, SANS sudo — le compte le plus exposé a le moins de droits) ;
      clés SSH sur les deux
- [ ] durcissement ssh : clé uniquement, root login off
- [ ] ufw : deny incoming par défaut, allow 22/80/443
- [ ] fail2ban (jail sshd)
- [ ] swap 2-4 Go (filet pour les builds rust --release, évite l'OOM kill)
- [ ] docker via le repo apt officiel (clé GPG + `docker-ce`, `docker-ce-cli`,
      `docker-compose-plugin`) + `daemon.json` avec rotation des logs (max-size/max-file, sinon
      disque plein)
- [ ] git + make (le Makefile est l'interface de deploy) + curl/wget/htop (debug & monitoring)
- [ ] runner github self-hosted : install + service systemd sous le user de service, label staging
- [ ] `.env` serveur : généré par template ansible depuis `vault.yml` (ansible-vault) — les secrets
      staging vivent chiffrés dans le repo, plus de scp manuel
- [ ] hygiène disque : cron `docker system prune` hebdo (+ `image prune` en fin de deploy —
      indispensable avec le build-au-deploy)

## 8. manquants (à intégrer)

- [ ] graceful shutdown — juste après les dockerfile prod
  - backend : `app.enableShutdownHooks()` (absent aujourd'hui) + `$disconnect()` prisma via hook
  - gateway : gérer SIGTERM dès l'écriture du code (arrêt propre tokio)
  - ai : idem quand le code arrivera
  - frontend : rien à faire, le nginx de l'image prod gère les signaux nativement
- [ ] checklist premier deploy : DNS (`dev.pollpear.com` → IP serveur), htpasswd (ligne équipe +
      ligne smoke), autoriser le repo sur les packages GHCR, puis gate : valider `make up_staging` à
      la main avant d'activer la CD
  - déjà fait : branche staging ✓, runner online ✓

## 9. backups postgres

- [ ] étape 1 — local : `scripts/backup-postgres.sh` en cron quotidien (installé par ansible) :
      `pg_dump -Fc` + rotation (7 quotidiens + 4 hebdos)
- [ ] étape 2 — distant : le serveur maison TIRE les dumps du VPS en rsync via Tailscale — rien
      d'exposé chez soi, le VPS n'a aucun credential vers la maison
- [ ] restore : `scripts/restore-postgres.sh <dump>` — confirmation explicite, stop des services,
      `pg_restore --clean`, redémarrage (auto-apply à envisager plus tard, avec garde-fous)
- [ ] alerte « backup trop vieux » : timestamp du dernier dump exposé au node-exporter (textfile
      collector) + règle alertmanager si > 24h

## 10. points en suspens

- [ ] vault staging : à trancher avec le mate qui gère vault — mode dev actuel = stockage mémoire,
      secrets perdus au restart ; vrai vault = storage persistant + init/unseal
  - bloquant pour le premier deploy : backend et ai ont un `depends_on: vault: service_healthy`
- [ ] accès à vault : direct ou via gateway ? (TODO déjà noté en fin de compose.yml)
