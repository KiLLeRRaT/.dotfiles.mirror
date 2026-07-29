#!/usr/bin/env bash

# Run from the project directory so docker compose finds docker-compose.yaml
# and the .env file that feeds it (DOCKER_REGISTRY, IMAGE_TAG, host paths, ...).
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" || exit 1

if [ ! -f .env ]; then
	echo "No .env found in $(pwd) - copy .env.example to .env and edit it first." >&2
	exit 1
fi

# X11 CLIPBOARD ACCESS
# We authorise the container against the host X server using the peer-UID rule
# instead of handing it an X cookie. WHY NOT MOUNT ~/.Xauthority: bind-mounting a
# single file pins that file's inode, and xauth rewrites ~/.Xauthority via
# temp-file-plus-rename (new inode). After an X restart the container would still
# be looking at the old inode and would silently hold a stale cookie.
# SI:localuser has no such problem - X checks the peer credentials on the socket.
# The container's `dev` user is UID 1000, same as the host user, and there is no
# userns remapping, so the peer-credential check passes.
# Non-fatal: if xhost moans we still want the container to come up.
if [ -n "$DISPLAY" ] && command -v xhost >/dev/null 2>&1; then
	xhost +SI:localuser:"$(id -un)" >/dev/null
fi

# ONLY pass X11 through if the socket is ACTUALLY there. A DISPLAY that is set but
# non-functional is WORSE than no DISPLAY at all: neovim will pick the xclip
# provider, xclip will fail to connect, and you get errors instead of a clean
# fallback to OSC 52.
# Handles :0, :0.0 and localhost:10.0 - strip up to and including the colon, then
# strip any .screen suffix.
# This conditional CANNOT be expressed in compose, which is why the X11 bits live
# in a separate override file that we only layer on when the socket exists. If we
# put them in the base file, DISPLAY would always be set inside the container and
# /tmp/.X11-unix would be created as an empty directory on hosts without X.
compose_files=(-f docker-compose.yaml)
if [ -n "$DISPLAY" ]; then
	displayNumber="${DISPLAY##*:}"
	displayNumber="${displayNumber%%.*}"
	x11Socket="/tmp/.X11-unix/X${displayNumber}"
	if [ -e "$x11Socket" ]; then
		compose_files+=(-f docker-compose.x11.yaml)
		echo "X11: enabled (DISPLAY=$DISPLAY)"
	else
		echo "X11: no socket at $x11Socket - skipping (container will have no clipboard)"
	fi
else
	echo "X11: DISPLAY not set - skipping (container will have no clipboard)"
fi

# We wrap the command with op run, and use sudo -E to preserve the injected
# NPM_AUTH_TOKEN environment variable across the sudo boundary.
# NPM_AUTH_TOKEN is listed (bare, with no value) under `environment:` in
# docker-compose.yaml so that compose forwards it from this process environment
# into the container - .env is interpolation-only and cannot do that.
# For more information about op and npm-env, see
# https://wiki.sandfield.co.nz/Node.js#Linux_and_macOS
#
# --no-build --pull missing keeps this a pure "run" step with the same semantics
# as the `docker run -d` it replaced: never build here (that is docker-build.sh's
# job), just pull the image if it is not already in the local cache. Without
# --no-build, compose would build the image locally instead of pulling it, which
# defeats the point of DOCKER_REGISTRY=dockerregistry-ro.gouws.org.
op run --account sandfield.1password.com --env-file=$HOME/.config/op/npm-env -- \
	sudo -E docker compose "${compose_files[@]}" up -d --pull missing --no-build
