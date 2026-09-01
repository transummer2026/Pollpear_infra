#!/bin/sh

# Entrypoint of the certbot side-car: attempts a Let's Encrypt renewal every 12h
# (certbot no-ops until a cert is within its renewal window). The nginx reload loop
# in 99-cert-reload.sh then serves the refreshed cert.

# trap + backgrounded sleep so SIGTERM stops the container promptly instead of
# waiting out the 12h sleep.
trap exit TERM
while :; do
  certbot renew --webroot -w /var/www/certbot
  sleep 12h &
  wait $!
done
