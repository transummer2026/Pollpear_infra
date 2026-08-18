#!/bin/sh
set -e

set -a
. /secrets/waf.env
set +a

exec /docker-entrypoint.sh "$@"
