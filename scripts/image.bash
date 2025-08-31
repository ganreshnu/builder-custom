#!/bin/bash
set -euo pipefail
. /usr/share/scripts/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [DIRECTORY...]

Options:
  --root DIRECTORY           The directory in which to install the emergeArgs.
  --disk FILE|BLOCKDEV       A filename or block device on which to write the
                             generated image.
  --seed UUID                A seed to use for reproducable partition tables.
  --locales FILE             A locale.gen formatted file with the locales to
                             build.
  --help                     Display this message and exit.

Creates a pruned image of the composite directories.
EOD
}
Main() {
	local -A args=(
		[root]=
		[disk]=
		[seed]=random
		[locales]=
	)
	local argv=()
	while (( $# > 0 )); do
		case "$1" in
			--root* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[root]="$value"
				;;
			--disk* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[disk]="$value"
				;;
			--seed* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[seed]="$value"
				;;
			--locales* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[locales]="$value"
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
	local includes=( usr )
	[[ -d /overlay/efi ]] && includes+=( efi )
	tar --directory=/overlay --create --preserve-permissions "${excludes[@]}" "${includes[@]}" \
		|tar --directory="${args[root]}" --extract --keep-directory-symlink

	#
	# copy the gcc redis folder
	#
	TarCp /usr/lib/gcc/x86_64-pc-linux-gnu/14/ "${args[root]}"/usr/lib64/


	cp /etc/ca-certificates.conf "${args[root]}"/usr/share/factory/etc/
	# echo 'C /etc/ca-certificates.conf' >"${args[root]}"/usr/lib/tmpfiles.d/ssl.conf
	# echo 'd /etc/ssl/certs' >>"${args[root]}"/usr/lib/tmpfiles.d/ssl.conf

	#
	# generate the locales
	#
	[[ -n "${args[locales]}" ]] && locale-gen --destdir "${args[root]}" --config "${args[locales]}"

	#
	# build the diskimage
	#
	[[ -n "${args[disk]}" ]] && systemd-repart --root="${args[root]}" --seed="${args[seed]}" \
		--certificate=verity.pem --private-key=verity-key.pem \
		--exclude-partitions=swap --empty=create --size=auto "${args[disk]}"

	#
	# unmount the overlay
	#
	fusermount3 -u /overlay
}
Main "$@"
