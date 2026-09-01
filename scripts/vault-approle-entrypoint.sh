#!/bin/sh
set -e

# Entrypoint wrapper for the long-running app services (backend, gateway, frontend,
# ai, studio). Waits for this service's AppRole env to appear on the shared volume,
# exports ROLE_ID / SECRET_ID into the environment, then execs the real command so
# the app can authenticate to Vault itself. $APPROLE_ENV names the file to source.

: "${APPROLE_ENV:?APPROLE_ENV is not set}"
approle="/vault/approle/${APPROLE_ENV}"

# Poll up to 30s for the AppRole file the Vault seeder writes at startup.

i=0
until [ -f "$approle" ]; do
  if [ "$i" -ge 30 ]; then
    echo "timeout waiting for ${approle}" >&2
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done

# set -a: export every var the AppRole file defines into the app's environment.
set -a
. "$approle"
set +a

# Hand off to the container's real command (CMD / compose command).
exec "$@"
