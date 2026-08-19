#!/bin/sh
set -e

: "${SERVICE:?SERVICE is not set}"
approle="/vault/approle/${SERVICE}.env"

i=0
until [ -f "$approle" ]; do
  if [ "$i" -ge 60 ]; then
    echo "timeout waiting for ${approle}" >&2
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done

. "$approle"
printf '%s' "$ROLE_ID" > /tmp/role_id
printf '%s' "$SECRET_ID" > /tmp/secret_id

exec vault agent -config=/agent/agent.hcl -exit-after-auth
