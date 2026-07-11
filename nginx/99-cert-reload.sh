#!/bin/sh

reload_loop() {
  while :; do
    sleep 6h
    nginx -s reload
  done
}

reload_loop &
