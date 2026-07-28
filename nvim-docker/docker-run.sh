#!/bin/bash

read -p "Use read-only (public) registry? (n to use local built image) [y/N]: " useReadOnlyRegistry
useReadOnlyRegistry=${useReadOnlyRegistry:-N}
if [ "$useReadOnlyRegistry" == "Y" ] || [ "$useReadOnlyRegistry" == "y" ]; then
	dockerRegistry="dockerregistry-ro.gouws.org"
else
	dockerRegistry="dockerregistry.gouws.org"
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
x11_args=()
if [ -n "$DISPLAY" ]; then
	displayNumber="${DISPLAY##*:}"
	displayNumber="${displayNumber%%.*}"
	x11Socket="/tmp/.X11-unix/X${displayNumber}"
	if [ -e "$x11Socket" ]; then
		# NOTE: mounted READ-WRITE on purpose (no :ro, unlike the mounts below).
		# A read-only bind mount of the X socket dir is reported to break connect()
		# on some setups. The security exposure here is the X socket itself, not
		# filesystem write access to that directory.
		x11_args=(-e DISPLAY="$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix)
		echo "X11: enabled (DISPLAY=$DISPLAY)"
	else
		echo "X11: no socket at $x11Socket - skipping (container will have no clipboard)"
	fi
else
	echo "X11: DISPLAY not set - skipping (container will have no clipboard)"
fi

# We wrap the command with op run, and use sudo -E to preserve the injected 
# NPM_AUTH_TOKEN environment variable across the sudo boundary.
# For more information about op and npm-env, see
# https://wiki.sandfield.co.nz/Node.js#Linux_and_macOS
op run --account sandfield.1password.com --env-file=$HOME/.config/op/npm-env -- \
	sudo -E docker run -d \
	--name nvim-docker \
	--hostname nvim-docker \
	-e TZ=Pacific/Auckland \
	-e NPM_AUTH_TOKEN \
	-e SSH_AUTH_SOCK=/home/dev/.1password/agent.sock \
	-e IN_DOCKER=true \
	"${x11_args[@]}" \
	-v /home/albert/.1password/agent.sock:/home/dev/.1password/agent.sock \
	-v /home/albert/source:/home/dev/source-host:ro \
	-v /home/albert/notes:/home/dev/notes:ro \
	$dockerRegistry/nvim-docker:latest
