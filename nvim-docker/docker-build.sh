#!/usr/bin/env bash

# Run from the project directory so docker compose finds docker-compose.yaml
# and the .env file that feeds it.
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" || exit 1

# Reads a value out of .env without sourcing it (sourcing would choke on
# unquoted values containing spaces, e.g. GIT_NAME=Albert Gouws). Only used to
# decide whether to abort - compose does its own .env reading for the real value.
function envFileValue() {
	local key=$1
	local line
	local value

	[[ -f .env ]] || return 0

	line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" .env | tail -n 1)
	[[ -n $line ]] || return 0

	value="${line#*=}"
	if [[ $value == \"*\" ]]; then
		value="${value:1:${#value}-2}"
	elif [[ $value == \'*\' ]]; then
		value="${value:1:${#value}-2}"
	fi

	printf '%s' "$value"
}

function getParams() {
	# FROM: https://gist.github.com/mattmc3/804a8111c4feba7d95b6d7b984f12a53
	local positional=()
	# local flag_verbose=false
	# local filename=myfile
	# flag_verbose=false
	# filename=myfile
	git_email=""
	git_name=""

	local usage=(
		"docker-build [-h|--help]"
		# "docker-build [-v|--verbose] [-f|--filename=<file>] [<message...>]"
		"docker-build [--git-email=<email>] [--git-name=<name>]"
		""
		"--git-email and --git-name are optional; they default to GIT_EMAIL and"
		"GIT_NAME in .env and only need to be passed to override those."
	)
	opterr() { echo >&2 "docker-build: Unknown option '$1'"; }

	while (( $# )); do
		case $1 in
			--)									shift; positional+=("$@"); break			 ;;
			# Returns non-zero so the caller stops before building, which is
			# what --help did before too.
			-h|--help)					printf '%s\n' "${usage[@]}"; return 1	 ;;
			# -v|--verbose)				flag_verbose=true											 ;;
			# -f|--filename)			shift; filename=$1										 ;;
			# -f=*|--filename=*)	filename="${1#*=}"										 ;;
			--git-email)				shift; git_email=$1											;;
			--git-email=*)			git_email="${1#*=}"											;;
			--git-name)					shift; git_name=$1											;;
			--git-name=*)				git_name="${1#*=}"											;;
			-*)									opterr "$1" && return 2								 ;;
			# *)									positional+=("$@"); break							 ;;
		esac
		shift
	done

	# The git identity is baked into the image at build time, so an empty one
	# produces an image with a broken git config. The flags are no longer
	# mandatory, but a value still has to come from somewhere.
	if [[ -z $git_email && -z $(envFileValue GIT_EMAIL) ]]; then
		echo "Please provide a valid git email, via --git-email or GIT_EMAIL in .env"
		return 1
	fi
	if [[ -z $git_name && -z $(envFileValue GIT_NAME) ]]; then
		echo "Please provide a valid git name, via --git-name or GIT_NAME in .env"
		return 1
	fi

	# echo "--verbose: $flag_verbose"
	# echo "--filename: $filename"
	# echo "positional: ${positional[*]}"
	# echo "--git-email: $git_email"
	# echo "--git-name: $git_name"
}

getParams "$@" || exit $?
# exit 1

# Only export when a flag was actually passed: the process environment beats
# .env during compose interpolation, so exporting an empty value here would
# wipe out the .env default instead of falling back to it.
if [[ -n $git_email ]]; then
	export GIT_EMAIL="$git_email"
fi
if [[ -n $git_name ]]; then
	export GIT_NAME="$git_name"
fi

# The container's `dev` user has to share the host user's UID/GID: the
# bind-mounted 1Password agent socket and the X11 peer-credential check both
# depend on it. Deliberately NOT in .env - it is derived, not configured.
USER_UID=$(id -u)
USER_GID=$(id -g)
export USER_UID
export USER_GID

# GET THE CURRENT COMMIT SHA
export BUILD_DATE=$(git rev-parse HEAD)


# GET DATE IN yyyymmddHHmmss FORMAT
# export BUILD_DATE=$(date +%Y%m%d%H%M%S)

read -rp "Do you want build with --no-cache? [y/N] " REPLY
declare -a cache=()
if [[ $REPLY =~ ^[Yy]$ ]]
then
		# docker compose --progress=plain build --no-cache
		cache=("--no-cache")
fi

# GIT_EMAIL / GIT_NAME / USER_UID / USER_GID reach the build through the
# build.args block in docker-compose.yaml (exported above, hence sudo -E).
# This builds the image AND its extra build.tags entries: :latest and
# :$BUILD_DATE, which is what the old version_latest / version_date services did.
sudo -E docker compose --progress=plain build --pull "${cache[@]}"

if [[ $? -ne 0 ]]
then
		echo "Build failed"
		exit 1
fi

# Pushes `image:` plus every build.tags entry, i.e. both :latest and the git-SHA
# tag.
read -rp "Do you want to push the image? [y/N] " REPLY
if [[ $REPLY =~ ^[Yy]$ ]]
then
		sudo -E docker compose push
fi

# LIST IMAGES/REPOS:
# https://dockerregistry.gouws.org/v2/_catalog
# https://dockerregistry.gouws.org/v2/nvim-docker/tags/list
#
# DELETING IMAGES:
#·https://dockerregistry.gouws.org/v2/nvim-docker/tags/list
# DELETE	/v2/<name>/manifests/<reference>
#
#
# FROM: https://stackoverflow.com/a/43786939/182888
# curl -sSL -u "$(read 'u?Username: ';echo $u)" https://dockerregistry.gouws.org/v2/_catalog
# curl -sSL -u "$(read 'u?Username: ';echo $u)" https://dockerregistry.gouws.org/v2/nvim-docker/tags/list
# curl -sSL -u "$(read 'u?Username: ';echo $u)" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -o /dev/null -w '%header{Docker-Content-Digest}' https://dockerregistry.gouws.org/v2/nvim-docker/manifests/<tag>
# curl -sSL -u "$(read 'u?Username: ';echo $u)" -X DELETE https://dockerregistry.gouws.org/v2/nvim-docker/manifests/<digest>
# /bin/registry garbage-collect /etc/docker/registry/config.yml
