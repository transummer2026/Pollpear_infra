#!/usr/bin/env bash
set -euo pipefail

# Full teardown of the Pollpear stack (called by `make fclean`): brings every
# compose combination down with its images and volumes, then force-removes any
# stray pollpear container the compose down could not reach.

cd "$(dirname "$0")/../.."

# DOMAIN is interpolated by the compose files; provide a placeholder so `compose
# down` parses even when no .env is present.
export DOMAIN="${DOMAIN:-fclean.local}"

flags=()
if [[ -f .env ]]; then
  flags+=(--env-file .env)
fi

infra=Pollpear_infra

down_stack() {
  docker compose "${flags[@]}" "$@" down --rmi all -v --remove-orphans --timeout 15 || true
}

# Tear down each file combination separately: a service only known to one overlay
# (e.g. studio, monitoring) is otherwise treated as orphan and left behind.
down_stack -f "$infra/compose.yml" -f "$infra/compose.dev.yml"
down_stack -f "$infra/compose.yml" -f "$infra/compose.monitor.yml" \
  -f "$infra/compose.dev.yml" -f "$infra/compose.monitor.dev.yml"
down_stack -f "$infra/compose.yml" -f "$infra/compose.monitor.yml" \
  -f "$infra/compose.prod.yml"

# Belt-and-braces: remove any pollpear-named container the compose downs missed.
leftovers=$(docker ps -aq --filter "name=pollpear")
if [[ -n "$leftovers" ]]; then
  # shellcheck disable=SC2086
  docker rm -f $leftovers >/dev/null
fi

echo "✓ fclean done"
