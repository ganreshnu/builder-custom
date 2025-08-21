#!/bin/bash
set -euo pipefail
. /usr/share/scripts/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS]

Options:
  --help                     Display this message and exit.

Builds a system image from source using portage.
EOD
}

Main() {
	local -A args=(
	)
	local argv=()
	while (( $# > 0 )); do
		case "$1" in
			kconfig|packages|kernel|image )
				break
				;;
			initramfs|basefs )
				argv+=( packages --portage-conf=/usr/share/"$1"/portage --extra-dir=/usr/share/"$1"/extra /usr/share/"$1"/world )
				shift; break
				;;
			--help )
				Usage
				return 0
				;;
			--env )
				Env
				return 0
				;;
			-- )
				shift; break
				;;
			* )
				argv+=( "$1" )
				;;
		esac
		shift
	done
	argv+=( "$@" )
	set - "${argv[@]}" && unset -v argv

	(( $# == 0 )) && exec bash --login || exec "$@"
}
Env() {
	cat <<'EOD'
declare -r volumes=(
	--volume="${HOME}"/.var/db/repos:/var/db/repos
	--volume="${HOME}"/.cache/distfiles:/var/cache/distfiles
	--volume="${HOME}"/.cache/binpkgs:/var/cache/binpkgs
)
builder() {
	podman run --rm --interactive --tty \
		--device=/dev/fuse \
		"${volumes[@]}" --volume="$PWD":"$PWD" \
		--workdir="$PWD" builder-custom "$@"
}
EOD
}
Main "$@"
