#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Git identity now comes from GIT_EMAIL / GIT_NAME in .env; pass
# --git-email / --git-name here only if you need to override it for one build.
./docker-build.sh
./docker-stop-and-remove.sh
./docker-run.sh
./docker-exec.sh
