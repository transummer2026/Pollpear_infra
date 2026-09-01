#!/usr/bin/env bash
set -euo pipefail

# Guarantees a TLS certificate for $DOMAIN before the prod up. Idempotent, called
# by `make up_prod`:
#   - Let's Encrypt cert already valid  -> do nothing (the renew-loop takes over)
#   - otherwise                         -> self-signed cert (so nginx can start),
#                                          then a best-effort Let's Encrypt attempt
# The LE attempt is non-blocking: if it fails (no public DNS, rate limit, failed
# challenge) we fall back to the self-signed cert so nginx is never left without a
# certificate and the local up still succeeds.

cd "$(dirname "$0")/../.."

compose() {
  docker compose --env-file .env \
    -f Pollpear_infra/compose.yml \
    -f Pollpear_infra/compose.monitor.yml \
    -f Pollpear_infra/compose.prod.yml "$@"
}

[[ -f .env ]] || { echo "✗ .env missing at the super-repo root"; exit 1; }
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${DOMAIN:?DOMAIN missing in .env}"
: "${ACME_EMAIL:?ACME_EMAIL missing in .env}"

live="/etc/letsencrypt/live/${DOMAIN}"

self_signed() {
  compose run --rm --entrypoint sh certbot -c "
    mkdir -p ${live} &&
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
      -keyout ${live}/privkey.pem -out ${live}/fullchain.pem \
      -subj '/CN=${DOMAIN}' \
      -addext 'subjectAltName=DNS:${DOMAIN},DNS:localhost,IP:127.0.0.1'"
}

# Skip everything if the live cert was issued by Let's Encrypt (issuer contains
# "encrypt"); a missing file or a self-signed cert falls through to reissue below.
if compose run --rm --entrypoint sh certbot -c \
    "openssl x509 -in ${live}/fullchain.pem -noout -issuer 2>/dev/null" \
    | grep -qi "encrypt"; then
  echo "✓ Certificat Let's Encrypt présent, rien à faire"
  exit 0
fi

echo "→ cert auto-signé (pour démarrer nginx)…"
self_signed
echo "→ démarrage de nginx (sert le challenge ACME)…"
compose up -d nginx-secrets
compose up -d --no-deps nginx

# Escape hatch: stop at the self-signed cert (local runs, offline CI, no public DNS).
if [[ "${SKIP_LETSENCRYPT:-0}" == "1" ]]; then
  exit 0
fi

echo "→ tentative Let's Encrypt pour ${DOMAIN}…"
# Drop any stale LE state (leftover self-signed live dir / renewal conf) so certbot
# issues cleanly via the webroot challenge that nginx is now serving.
if compose run --rm --entrypoint sh certbot -c "
    rm -rf /etc/letsencrypt/live/${DOMAIN} \
           /etc/letsencrypt/archive/${DOMAIN} \
           /etc/letsencrypt/renewal/${DOMAIN}.conf &&
    certbot certonly --webroot -w /var/www/certbot \
      -d ${DOMAIN} --email ${ACME_EMAIL} --agree-tos --no-eff-email -n"; then
  echo "✓ certificat Let's Encrypt obtenu"
else
  echo "⚠ Let's Encrypt indisponible, on garde un cert auto-signé (browser warning attendu)"
  self_signed
fi

echo "→ reload nginx…"
compose exec nginx nginx -s reload
echo "✓ Certificat prêt"
