#!/usr/bin/env bash
set -euo pipefail

./docker-build.sh --git-email="albert@gouws.org" --git-name="Albert Gouws"
sudo docker stop nvim-docker
sudo docker rm nvim-docker
./docker-run.sh
./docker-exec.sh
