#!/usr/bin/env bash
set -euo pipefail

# Applies the Prisma migrations to the prod stack's database before the backend
# starts. Needed because the prod service command is `node dist/src/main`, which
# does not migrate: only the dev stack's `start:dev` chains `prisma migrate deploy`
# before Nest. Without this step any fresh database (first up, or volume recreated
# by an fclean) makes the backend crash-loop on
# `relation "public.users" does not exist`.
#
# Idempotent: `migrate deploy` never replays an already-applied migration.
# Called by `make up_prod` and by deploy.sh.

cd "$(dirname "$0")/../.."

compose() {
  docker compose --env-file .env \
    -f Pollpear_infra/compose.yml \
    -f Pollpear_infra/compose.monitor.yml \
    -f Pollpear_infra/compose.prod.yml "$@"
}

[[ -f .env ]] || { echo "error: .env missing at the super-repo root"; exit 1; }

# Bring postgres up first (it pulls its secrets from Vault via postgres-secrets),
# so the backend's approle entrypoint can read DATABASE_URL from Vault too.
echo "starting postgres"
compose up -d --wait postgres

echo "running prisma migrations"
# One-off container, --no-deps so it does not drag the rest of the stack up; the
# backend image ships the Prisma CLI and schema even though its prod command omits it.
compose run --rm --no-deps backend npx prisma migrate deploy --config prisma.config.mts
