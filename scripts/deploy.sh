#!/usr/bin/env bash
set -euo pipefail

# Deploiement CD dev.pollpear.com : rejoue l'equivalent de `make up_prod` depuis le
# runner self-hosted, precede des migrations Prisma. Idempotent, pilote par le
# workflow deploy_staging.yml (ou `make deploy` en manuel sur le serveur).
#   1. livre les .env persistants du serveur : structurel a la racine du
#      super-repo, secrets vault dans Pollpear_cyber/.env
#   2. build des services internes depuis le code epingle par staging
#   3. postgres up + healthy, puis migrations Prisma en one-off
#   4. certs (ensure-certs.sh) puis up complet en --wait (valide les healthchecks)
#   5. purge des images orphelines

cd "$(dirname "$0")/../.."

DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-$HOME/pollpear/.env}"
DEPLOY_VAULT_ENV_FILE="${DEPLOY_VAULT_ENV_FILE:-$HOME/pollpear/vault.env}"

compose() {
  docker compose --env-file .env \
    -f Pollpear_infra/compose.yml \
    -f Pollpear_infra/compose.monitor.yml \
    -f Pollpear_infra/compose.prod.yml "$@"
}

if [[ ! -f "$DEPLOY_ENV_FILE" ]]; then
  echo "error: env file not found at $DEPLOY_ENV_FILE (set DEPLOY_ENV_FILE)"
  exit 1
fi
if [[ ! -f "$DEPLOY_VAULT_ENV_FILE" ]]; then
  echo "error: vault env file not found at $DEPLOY_VAULT_ENV_FILE (set DEPLOY_VAULT_ENV_FILE)"
  exit 1
fi
install -m 600 "$DEPLOY_ENV_FILE" .env
install -m 600 "$DEPLOY_VAULT_ENV_FILE" Pollpear_cyber/.env
echo "env delivered from $DEPLOY_ENV_FILE and $DEPLOY_VAULT_ENV_FILE"

echo "building internal services"
compose build

echo "starting postgres"
compose up -d --wait postgres

echo "running prisma migrations"
compose run --rm --no-deps backend npx prisma migrate deploy --config prisma.config.ts

echo "ensuring TLS certificate"
bash Pollpear_infra/scripts/ensure-certs.sh

echo "starting full stack (waiting for healthchecks)"
compose up -d --wait

echo "pruning dangling images"
docker image prune -f

echo "deploy complete"
