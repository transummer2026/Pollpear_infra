#!/usr/bin/env bash
# Provisionne Garage pour Pollpear, de facon idempotente :
#   layout du noeud -> bucket -> import de la cle backend (creds depuis Vault)
#   -> droits read/write -> service web public du bucket.
# Lance automatiquement par 'make up' une fois garage healthy.
# Les creds S3 (GARAGE_S3_ACCESS_KEY / _SECRET_KEY) viennent de Vault
# (secret/pollpear/s3, seede depuis .env) : la cle est IMPORTEE, donc stable
# meme apres un 'make fclean' qui supprime le volume garage.
# Surchargeables : GARAGE_CONTAINER, GARAGE_ZONE, GARAGE_CAPACITY, GARAGE_KEY_NAME
set -euo pipefail

CONTAINER="${GARAGE_CONTAINER:-pollpear-garage}"
VAULT_CONTAINER="${VAULT_CONTAINER:-pollpear-vault}"
ZONE="${GARAGE_ZONE:-dc1}"
CAPACITY="${GARAGE_CAPACITY:-10GB}"
KEY_NAME="${GARAGE_KEY_NAME:-pollpear-backend}"

vkv() {
  docker exec "${VAULT_CONTAINER}" sh -c \
    "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=\"\$VAULT_DEV_ROOT_TOKEN_ID\" vault kv get -field=$1 secret/pollpear/s3"
}

BUCKET="$(vkv bucket)"
GARAGE_S3_ACCESS_KEY="$(vkv access_key)"
GARAGE_S3_SECRET_KEY="$(vkv secret_key)"
: "${GARAGE_S3_ACCESS_KEY:?missing in vault secret/pollpear/s3}"
: "${GARAGE_S3_SECRET_KEY:?missing in vault secret/pollpear/s3}"

g() { docker exec -e RUST_LOG=warn "${CONTAINER}" /garage "$@"; }

wait_buckets() {
  for _ in $(seq 1 30); do
    if g bucket list >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

echo "Waiting for Garage (${CONTAINER})..."
for _ in $(seq 1 30); do
  if g status >/dev/null 2>&1; then break; fi
  sleep 1
done
g status >/dev/null 2>&1 || { echo "Garage not responding"; exit 1; }

if g bucket list >/dev/null 2>&1; then
  echo "Layout already present"
else
  echo "No layout: assigning role to node..."
  node_id="$(g node id -q 2>/dev/null | head -1 | cut -d@ -f1)"
  g layout assign -z "${ZONE}" -c "${CAPACITY}" "${node_id}" >/dev/null
  g layout apply --version 1 >/dev/null
  echo "Waiting for layout to become active..."
  wait_buckets || { echo "Layout not active"; exit 1; }
fi

if g bucket list | grep -qw "${BUCKET}"; then
  echo "Bucket ${BUCKET} already present"
else
  echo "Creating bucket ${BUCKET}..."
  g bucket create "${BUCKET}" >/dev/null
fi

if g key list | grep -q "${GARAGE_S3_ACCESS_KEY}"; then
  echo "Key ${KEY_NAME} already present"
else
  echo "Importing key ${KEY_NAME} (creds from vault)..."
  g key import --yes -n "${KEY_NAME}" "${GARAGE_S3_ACCESS_KEY}" "${GARAGE_S3_SECRET_KEY}" >/dev/null
fi

echo "Applying read/write permissions..."
g bucket allow --read --write "${BUCKET}" --key "${GARAGE_S3_ACCESS_KEY}" >/dev/null

echo "Enabling public website on bucket..."
g bucket website --allow "${BUCKET}" >/dev/null

echo "Garage ready: bucket '${BUCKET}', key ${GARAGE_S3_ACCESS_KEY} (imported from vault)"
