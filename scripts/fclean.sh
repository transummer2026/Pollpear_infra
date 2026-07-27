#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

export DOMAIN="${DOMAIN:-fclean.local}"
export NGINX_AUTH="${NGINX_AUTH:-off}"
export GATEWAY_URL="${GATEWAY_URL:-http://fclean.local}"
export GRAFANA_USER="${GRAFANA_USER:-fclean}"
export GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-fclean}"

flags=()
if [[ -f .env ]]; then
  flags+=(--env-file .env)
fi

infra=Pollpear_infra

down_stack() {
  docker compose "${flags[@]}" "$@" down --rmi all -v --remove-orphans --timeout 15 || true
}

down_stack -f "$infra/compose.yml" -f "$infra/compose.dev.yml"
down_stack -f "$infra/compose.yml" -f "$infra/compose.monitor.yml" \
  -f "$infra/compose.dev.yml" -f "$infra/compose.monitor.dev.yml"
down_stack -f "$infra/compose.yml" -f "$infra/compose.monitor.yml" \
  -f "$infra/compose.prod.yml"

leftovers=$(docker ps -aq --filter "name=pollpear")
if [[ -n "$leftovers" ]]; then
  # shellcheck disable=SC2086
  docker rm -f $leftovers >/dev/null
fi

echo "✓ fclean done"
