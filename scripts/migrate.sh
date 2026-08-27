#!/usr/bin/env bash
set -euo pipefail

# Applique les migrations Prisma sur la base du stack prod, avant tout demarrage
# du backend. Necessaire parce que la commande du service en prod est
# `node dist/src/main`, qui ne migre pas : seul le `start:dev` du stack dev
# enchaine `prisma migrate deploy` avant Nest. Sans cette etape, toute base
# neuve (premier up, ou volume recree par un fclean) fait boucler le backend
# sur `relation "public.users" does not exist`.
#
# Idempotent : `migrate deploy` ne rejoue jamais une migration deja appliquee.
# Appele par `make up_prod` et par deploy.sh.

cd "$(dirname "$0")/../.."

compose() {
  docker compose --env-file .env \
    -f Pollpear_infra/compose.yml \
    -f Pollpear_infra/compose.monitor.yml \
    -f Pollpear_infra/compose.prod.yml "$@"
}

[[ -f .env ]] || { echo "error: .env missing at the super-repo root"; exit 1; }

# postgres tire vault via postgres-secrets : l'entrypoint approle du backend
# a donc de quoi lire DATABASE_URL dans Vault.
echo "starting postgres"
compose up -d --wait postgres

echo "running prisma migrations"
compose run --rm --no-deps backend npx prisma migrate deploy --config prisma.config.mts
