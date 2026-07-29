#!/usr/bin/env bash

# Run from the project directory so docker compose finds docker-compose.yaml
# and the .env file that feeds it.
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" || exit 1

# `down` stops and removes the container (the old `docker stop` + `docker rm`
# pair) and is a no-op when nothing is running.
sudo docker compose down
