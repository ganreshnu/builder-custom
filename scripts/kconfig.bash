#!/bin/bash
set -euo pipefail
. /usr/share/scripts/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] FILE...

Options:
  --arch STRING              Architecture of the kernel configuration.
  --edit FILE                Edit the specified file.
  --help                     Display this message and exit.

Configures the kernel sources given the specified configuration
fragment files.

Additionally, one may edit the file specified by --edit after
applying any given files. The special file 'defconfig' may be
given to configure from the kernel defconfig for the given
architecture.
EOD
}

Main() {
	local -A args=(
		[arch]=x86
		[edit]=
	)
	local argv=()
	while (( $# > 0 )); do
		case "$1" in
			--arch* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[arch]="$value"
				;;
			--edit* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[edit]="$value"
				;;
			--help )
				Usage
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

	ApplyKConfigs "$@"

	if [[ -n "${args[edit]}" ]]; then
		cp /usr/src/linux/.config /tmp/kernel.config
		ApplyKConfigs "${args[edit]}"
		pushd /usr/src/linux >/dev/null
		make --quiet nconfig \
			&& scripts/diffconfig -m /tmp/kernel.config .config > /tmp/diff.config
		popd >/dev/null #/usr/src/linux
		rm /tmp/kernel.config
		mv /tmp/diff.config "${args[edit]}"
	fi
}
ApplyKConfigs() {
	for fragmentFile in "$@"; do
		[[ "${fragmentFile}" != defconfig ]] && cp "${fragmentFile}" /usr/src/linux/arch/"${args[arch]}"/configs/
		make --directory=/usr/src/linux "$(basename ${fragmentFile})" --quiet
		Print 5 ApplyKConfigs "applied ${fragmentFile} kernel configuration fragment."
	done
}
Main "$@"
