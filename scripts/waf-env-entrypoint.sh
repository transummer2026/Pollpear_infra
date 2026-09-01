#!/bin/sh
set -e

# nginx/ModSecurity entrypoint. Loads the WAF tuning env (SecRuleEngine, paranoia
# level, anomaly thresholds...) that the nginx vault-agent rendered into
# /secrets/waf.env, then hands off to the upstream nginx entrypoint.
set -a
. /secrets/waf.env
set +a

exec /docker-entrypoint.sh "$@"
