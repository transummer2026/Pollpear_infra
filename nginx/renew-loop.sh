#!/bin/sh

trap exit TERM
while :; do
  certbot renew --webroot -w /var/www/certbot
  sleep 12h &
  wait $!
done
