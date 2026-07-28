#!/bin/bash

read -p "Use read-only (public) registry? (n to use local built image) [y/N]: " useReadOnlyRegistry
useReadOnlyRegistry=${useReadOnlyRegistry:-N}
if [ "$useReadOnlyRegistry" == "Y" ] || [ "$useReadOnlyRegistry" == "y" ]; then
	dockerRegistry="dockerregistry-ro.gouws.org"
else
	dockerRegistry="dockerregistry.gouws.org"
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
	-v /home/albert/.1password/agent.sock:/home/dev/.1password/agent.sock \
	-v /home/albert/source:/home/dev/source-host:ro \
	-v /home/albert/notes:/home/dev/notes:ro \
	$dockerRegistry/nvim-docker:latest
