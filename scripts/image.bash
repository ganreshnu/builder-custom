#!/bin/bash
set -euo pipefail
. /usr/share/scripts/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [DIRECTORY...]

Options:
  --root DIRECTORY           The directory in which to install the emergeArgs.
  --repart-conf DIRECTORY    The repart configuration directory.
  --help                     Display this message and exit.

Creates a pruned image of the composite directories.
EOD
}
Main() {
	local -A args=(
		[root]=
		[repart-conf]=
	)
	local argv=()
	while (( $# > 0 )); do
		case "$1" in
			--root* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[root]="$value"
				;;
			--repart-conf* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[repart-conf]="$value"
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

	[[ -z "${args[root]}" ]] && { >&2 Print 1 packages "missing required option --root"; return 1; }

	local lowers=() excludes=(
		--exclude=efi/kconfig.zst
		--exclude=efi/System.map
		--exclude=usr/lib/systemd/system-environment-generators/10-gentoo-path
		--exclude=usr/share/factory/etc/locale.conf
		--exclude=usr/share/factory/etc/vconsole.conf
	)
	for arg in "$@"; do
		if [[ -d "${arg}" ]]; then
			lowers+=( "${arg}" )
		elif [[ -f "${arg}" ]]; then
			mapfile -t <"${arg}"
			for item in "${MAPFILE[@]}"; do
				[[ "${item}" != \#* ]] && excludes+=( --exclude="${item}" )
				done
		else
			excludes+=( --exclude="${arg}" )
		fi
	done

	#
	# mount the overlay
	#
	(( ${#lowers[@]} == 0 )) && lowers+=( /var/empty )
	fuse-overlayfs -o lowerdir=$(Join : "${lowers[@]}") /overlay || { >&2 Print 1 packages "overlay mount failed"; return 1; }

	SetupRoot "${args[root]}"
	tar --directory=/overlay --create --preserve-permissions "${excludes[@]}" efi usr \
		|tar --directory="${args[root]}" --extract --keep-directory-symlink

	# systemd-repart --definitions="${args[repart-conf]}" --copy-source="${emptyDir}" --empty=create --size=auto --split="${args[split]}" "${overlayDir}"/"${archivename}"
	#
	# unmount the overlay
	#
	fusermount3 -u /overlay
}
Main "$@"
