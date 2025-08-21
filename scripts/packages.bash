#!/bin/bash
set -euo pipefail
. /usr/share/scripts/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [DIRECTORY...]

Options:
  --nproc INT                Number of threads to use.
  --jobs INT                 Number of jobs to split threads among.
  --root DIRECTORY           The directory in which to install the emergeArgs.
  --workdir DIRECTORY        OverlayFS workdir which must be on the same
                             partition as the layer directories.
  --portage-conf DIRECTORY   Customized files that are copied into
                             /etc/portage/
  --extra-dir DIRECTORY      Additional files to copy into /usr.
  --help                     Display this message and exit.

Installs portage packages to the specified root.
EOD
}
Main() {
	local -A args=(
		[nproc]=$(nproc)
		[jobs]=2
		[root]=
		[workdir]=
		[portage-conf]=/var/empty
	)
	local argv=() extras=()
	while (( $# > 0 )); do
		case "$1" in
			--nproc* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[nproc]="$value"
				;;
			--jobs* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[jobs]="$value"
				;;
			--root* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[root]="$value"
				;;
			--workdir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[workdir]="$value"
				;;
			--portage-conf* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[portage-conf]="$value"
				;;
			--extra-dir* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				extras+=( "$value" )
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
	[[ -z "${args[workdir]}" ]] && { >&2 Print 1 packages "missing required option --workdir"; return 1; }

	local lowers=() emergeArgs=()
	for arg in "$@"; do
		if [[ -d "${arg}" ]]; then
			lowers+=( "${arg}" )
		elif [[ -f "${arg}" ]]; then
			mapfile -t <"${arg}"
			for item in "${MAPFILE[@]}"; do
				[[ "${item}" != \#* ]] && emergeArgs+=( "${item}" )
				done
		else
			emergeArgs+=( "${arg}" )
		fi
	done

	#
	# mount the overlay
	#
	(( ${#lowers[@]} == 0 )) && lowers+=( /var/empty )
	fuse-overlayfs -o lowerdir=$(Join : "${lowers[@]}"),upperdir="${args[root]}",workdir="${args[workdir]}" /overlay || { >&2 Print 1 packages "overlay mount failed"; return 1; }

	#
	# setup the rootfs
	#
	SetupRoot /overlay

	#
	# configure portage
	#
	tar --directory=/etc --create --zstd --file=/tmp/portage.tar.zst portage \
		&& TarCp "${args[portage-conf]}" /etc/portage

	#
	# execute emerge
	#
	MAKEOPTS="-j$(( ${args[nproc]} / ${args[jobs]} ))" KERNEL_DIR=/usr/src/linux \
		emerge --root=/overlay --jobs=${args[jobs]} "${emergeArgs[@]}"

	#
	# restore portage configuration
	#
	rm -r /etc/portage && tar --directory=/etc --extract --file=/tmp/portage.tar.zst && rm /tmp/portage.tar.zst

	#
	# copy extras in
	#
	for extra in "${extras[@]}"; do
		TarCp "${extra}" /overlay/usr
	done

	#
	# unmount the overlay
	#
	fusermount3 -u /overlay
}
Main "$@"
