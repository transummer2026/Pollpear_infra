#!/usr/bin/env bash
# Provisions Garage for Pollpear, idempotently:
#   node layout -> bucket -> import of the backend key (creds from Vault)
#   -> read/write grant -> public website serving for the bucket.
# Run automatically by 'make up' once garage is healthy.
# The S3 creds (GARAGE_S3_ACCESS_KEY / _SECRET_KEY) come from Vault
# (secret/pollpear/s3, seeded from .env): the key is IMPORTED, so it stays stable
# even after a 'make fclean' that deletes the garage volume.
# Overridable: GARAGE_CONTAINER, GARAGE_ZONE, GARAGE_CAPACITY, GARAGE_KEY_NAME
set -euo pipefail

CONTAINER="${GARAGE_CONTAINER:-pollpear-garage}"
SECRETS_VOLUME="${GARAGE_SECRETS_VOLUME:-pollpear-garage-secrets}"
ZONE="${GARAGE_ZONE:-dc1}"
CAPACITY="${GARAGE_CAPACITY:-10GB}"
KEY_NAME="${GARAGE_KEY_NAME:-pollpear-backend}"

# Read one secret file the garage vault-agent rendered into the shared secrets volume.
vsecret() {
  docker run --rm --user root --entrypoint cat -v "${SECRETS_VOLUME}:/secrets:ro" pollpear-vault:dev "/secrets/$1"
}

BUCKET="$(vsecret s3_bucket)"
GARAGE_S3_ACCESS_KEY="$(vsecret s3_access_key)"
GARAGE_S3_SECRET_KEY="$(vsecret s3_secret_key)"
: "${GARAGE_S3_ACCESS_KEY:?missing in vault secret/pollpear/s3}"
: "${GARAGE_S3_SECRET_KEY:?missing in vault secret/pollpear/s3}"

# Run a garage CLI command inside the running container.
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

# `bucket list` only answers once a cluster layout is applied, so it doubles as a
# "layout already present?" probe on a fresh (or fcleaned) garage data volume.
if g bucket list >/dev/null 2>&1; then
  echo "Layout already present"
else
  echo "No layout: assigning role to node..."
  # Single-node cluster: give this node a zone/capacity role and apply as layout v1.
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
