#!/usr/bin/env bash
set -euo pipefail

# make init_staging 1st time on the server, after filling .env and generating Pollpear_infra/nginx/htpasswd.

cd "$(dirname "$0")/../.."

compose() {
  docker compose --env-file .env \
    -f Pollpear_infra/compose.yml \
    -f Pollpear_infra/compose.staging.yml "$@"
}
[[ -f .env ]] || { echo "✗ .env missing at the super-repo root"; exit 1; }
set -a
source .env
set +a

: "${STAGING_DOMAIN:?STAGING_DOMAIN manquant dans .env}"
: "${ACME_EMAIL:?ACME_EMAIL manquant dans .env}"

if [[ ! -f Pollpear_infra/nginx/htpasswd ]]; then
  echo "✗ Pollpear_infra/nginx/htpasswd missing, generate it with:"
  echo "  docker run --rm httpd:2.4-alpine htpasswd -Bbn pollpear 'password' > Pollpear_infra/nginx/htpasswd"
  exit 1
fi

live="/etc/letsencrypt/live/${STAGING_DOMAIN}"

if compose run --rm --entrypoint sh certbot -c \
    "openssl x509 -in ${live}/fullchain.pem -noout -issuer 2>/dev/null" \
    | grep -qi "encrypt"; then
  echo "✓ Certificate Let's Encrypt present, nothing to do"
  exit 0
fi

echo "creating self-signed cert for ${STAGING_DOMAIN}..."
compose run --rm --entrypoint sh certbot -c "
  mkdir -p ${live} &&
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout ${live}/privkey.pem -out ${live}/fullchain.pem \
    -subj '/CN=${STAGING_DOMAIN}'"
echo "nginx starting..."
compose up -d --no-deps nginx

compose run --rm --entrypoint sh certbot -c "
  rm -rf /etc/letsencrypt/live/${STAGING_DOMAIN} \
         /etc/letsencrypt/archive/${STAGING_DOMAIN} \
         /etc/letsencrypt/renewal/${STAGING_DOMAIN}.conf &&
  certbot certonly --webroot -w /var/www/certbot \
    -d ${STAGING_DOMAIN} --email ${ACME_EMAIL} \
    --agree-tos --no-eff-email"

echo "reloading nginx..."
compose exec nginx nginx -s reload

echo "✓ Certificate ready, you can launch make up_staging"
