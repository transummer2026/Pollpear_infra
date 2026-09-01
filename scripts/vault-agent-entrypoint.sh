#!/bin/sh
set -e

# Entrypoint for the one-shot *-secrets side-cars. Waits for the Vault seeder to
# drop this service's AppRole credentials on the shared volume, feeds role_id /
# secret_id to a Vault agent that renders the service's secret files, then exits.
# $SERVICE selects which AppRole env the seeder wrote (e.g. pollpear-postgres).

: "${SERVICE:?SERVICE is not set}"
approle="/vault/approle/${SERVICE}.env"

# Poll up to 60s for the AppRole file; the seeder runs as vault's post_start hook.

i=0
until [ -f "$approle" ]; do
  if [ "$i" -ge 60 ]; then
    echo "timeout waiting for ${approle}" >&2
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done

# Split the sourced AppRole into the two files the agent's approle auto_auth reads.
. "$approle"
printf '%s' "$ROLE_ID" > /tmp/role_id
printf '%s' "$SECRET_ID" > /tmp/secret_id

# Authenticate, render the templates from the mounted agent.hcl, then exit (side-car).
exec vault agent -config=/agent/agent.hcl -exit-after-auth
