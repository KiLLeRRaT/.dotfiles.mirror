#!/usr/bin/env bash

# Run from the project directory so docker compose finds docker-compose.yaml
# and the .env file that feeds it.
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" || exit 1

# `docker compose exec` allocates a TTY by default, so there is no -it here.
sudo docker compose exec nvim-docker /bin/zsh
