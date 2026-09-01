#!/bin/sh

# Dropped into nginx's /docker-entrypoint.d so it runs at container start, before
# nginx goes daemon-off. Reloads nginx every 6h in the background so a certificate
# renewed by the certbot side-car is picked up without restarting the container.
reload_loop() {
  while :; do
    sleep 6h
    nginx -s reload
  done
}

# Background the loop and return, letting the entrypoint continue to launch nginx.
reload_loop &
