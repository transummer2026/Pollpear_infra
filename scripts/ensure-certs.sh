#!/usr/bin/env bash
set -euo pipefail

# Garantit un certificat TLS pour $DOMAIN avant le up prod. Idempotent, appelé
# par `make up_prod` :
#   - cert Let's Encrypt déjà valide      -> ne fait rien (le renew-loop gère la suite)
#   - sinon                               -> cert auto-signé (pour que nginx démarre),
#                                            puis tentative Let's Encrypt en best-effort
# La tentative LE est non bloquante : si elle échoue (pas de DNS public, rate limit,
# challenge KO), on retombe sur l'auto-signé pour que nginx ne reste jamais sans cert
# et que le up local passe quand même.

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

if [[ "${SKIP_LETSENCRYPT:-0}" == "1" ]]; then
  compose exec nginx nginx -s reload
  exit 0
fi

echo "→ tentative Let's Encrypt pour ${DOMAIN}…"
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
