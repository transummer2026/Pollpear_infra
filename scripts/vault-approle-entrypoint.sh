#!/bin/sh
set -e

: "${APPROLE_ENV:?APPROLE_ENV is not set}"
approle="/vault/approle/${APPROLE_ENV}"

i=0
until [ -f "$approle" ]; do
  if [ "$i" -ge 30 ]; then
    echo "timeout waiting for ${approle}" >&2
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done

set -a
. "$approle"
set +a

exec "$@"
