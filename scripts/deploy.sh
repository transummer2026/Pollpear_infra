#!/usr/bin/env bash
set -euo pipefail

# CD deployment for dev.pollpear.com: replays the equivalent of `make up_prod`
# from the self-hosted runner, preceded by the Prisma migrations. Idempotent,
# driven by the deploy_staging.yml workflow (or `make deploy` by hand on the server).
#   1. deliver the server's persistent .env files: structural one at the super-repo
#      root, Vault secrets in Pollpear_cyber/.env
#   2. build the internal services from the code pinned by staging
#   3. bring postgres up + healthy, then run the Prisma migrations as a one-off
#   4. certs (ensure-certs.sh), then full up with --wait (validates the healthchecks)
#   5. prune orphaned images

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
install -m 644 "$DEPLOY_VAULT_ENV_FILE" Pollpear_cyber/.env
echo "env delivered from $DEPLOY_ENV_FILE and $DEPLOY_VAULT_ENV_FILE"

echo "building internal services"
compose build

bash Pollpear_infra/scripts/migrate.sh

echo "ensuring TLS certificate"
bash Pollpear_infra/scripts/ensure-certs.sh

echo "starting full stack (waiting for healthchecks)"
compose up -d --wait

echo "pruning dangling images"
docker image prune -f

echo "deploy complete"
