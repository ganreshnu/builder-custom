#!/bin/bash
set -euo pipefail
. /usr/share/scripts/util.bash

Usage() {
	cat <<EOD
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] [DIRECTORY...]

Options:
  --root        DIRECTORY      The directory in which to install the emergeArgs.
  --workdir     DIRECTORY      OverlayFS workdir which must be on the same
                               partition as the layer directories.
  --seed        UUID           A seed to use for reproducable partition tables.
  --kernel-arg  STRING         Kernel command line argument(s). Can be passed
                               multiple times.
  --help                       Display this message and exit.

Creates a esp image containing an installer.
EOD
}
Main() {
	local -A args=(
		[root]=''
		[workdir]=''
		[outputdir]=''
		[seed]=random
	)
	local argv=()
	local kernel_args=(
		consoleblank=60
		rw rdinit=/usr/lib/systemd/systemd
	)
	while (( $# > 0 )); do
		case "$1" in
			--root* )
				local value='' count=0
				ExpectArg value count "$@"; shift $count
				args[root]="$value"
				;;
			--workdir* )
				local value='' count=0
				ExpectArg value count "$@"; shift $count
				args[workdir]="$value"
				;;
			--seed* )
				local value='' count=0
				ExpectArg value count "$@"; shift $count
				args[seed]="$value"
				;;
			--kernel-arg* )
				local value='' count=0
				ExpectArg value count "$@"; shift $count
				kernel_args+=( "$value" )
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

	local lowers=()
	local excludes=(
		--exclude=efi/kconfig.zst
		--exclude=efi/System.map
		--exclude=usr/lib/systemd/system-environment-generators/10-gentoo-path
		--exclude=usr/share/factory/etc/locale.conf
		--exclude=usr/share/factory/etc/vconsole.conf
	)
	local repartArgs=()
	for arg in "$@"; do
		if [[ -d "${arg}" ]]; then
			lowers+=( "${arg}" )
		elif [[ -f "${arg}" ]]; then
			# file of excludes
			mapfile -t <"${arg}"
			for item in "${MAPFILE[@]}"; do
				[[ "${item}" != \#* ]] && excludes+=( --exclude="${item}" )
				done
		elif [[ "${arg}" =~ ^-- ]]; then
			repartArgs+=( "${arg}" )
		else
			excludes+=( --exclude="${arg}" )
		fi
	done

	#
	# mount the overlay
	#
	(( ${#lowers[@]} == 0 )) && lowers+=( /var/empty )
	fuse-overlayfs -o lowerdir="$(Join : "${lowers[@]}")",upperdir="${args[root]}",workdir="${args[workdir]}" /overlay || { >&2 Print 1 installer "overlay mount failed"; return 1; }

	local -r distdir=/overlay/efi/EFI/Linux

	mkdir -p "$distdir"
	mkdir -p /overlay/efi/loader/entries
	cp /boot/loader.conf /overlay/efi/loader/
	cp /boot/entries.srel /overlay/efi/loader/
	mkdir /overlay/efi/EFI/BOOT
	cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi /overlay/efi/EFI/BOOT/BOOTX64.EFI
	# bootctl --esp-path=/overlay/efi random-seed

	ukify build --linux=/overlay/boot/vmlinuz --cmdline="${kernel_args[*]}" \
		--os-release=@/overlay/usr/lib/os-release --initrd=/overlay/boot/initramfs.cpio.zst \
		--secureboot-private-key=verity.key --secureboot-certificate=verity.crt \
		--output="$distdir"/installer.efi
	Print 5 image 'built uki'

	#
	# build the diskimage
	#
	systemd-repart --root=/overlay --seed="${args[seed]}" "${repartArgs[@]}" \
		--empty=create --size=auto --definitions=/usr/lib/repart.d \
		--include-partitions=esp,linux-generic /overlay/installer.raw
	Print 5 image "built image"

	#
	# unmount the overlay
	#
	fusermount3 -u /overlay
}
Main "$@"
