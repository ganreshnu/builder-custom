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

Creates a pruned image of the composite directories.
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
	local -r efitemp=$(mktemp -d)
	mkdir "$efitemp"/efi
	lowers+=( "$efitemp" )

	(( ${#lowers[@]} == 0 )) && lowers+=( /var/empty )
	fuse-overlayfs -o lowerdir="$(Join : "${lowers[@]}")",upperdir="${args[root]}",workdir="${args[workdir]}" /overlay || { >&2 Print 1 image "overlay mount failed"; return 1; }

	. /overlay/usr/lib/os-release

	#
	# build the diskimage
	#
	mkdir /overlay/dist
	local -r tempfile=$(mktemp)
	systemd-repart --root=/overlay --seed="${args[seed]}" "${repartArgs[@]}" \
		--definitions=/usr/lib/repart.d --defer-partitions=esp,linux-generic --split=yes \
		--empty=create --size=auto --json=short /overlay/"$IMAGE_ID"-"$IMAGE_VERSION".raw >"$tempfile"
	# kernel_args+=(
	# 	root=dissect
	# 	systemd.image_policy=esp=unprotected:usr=verity+signed+read-only-on:root=unprotected+encrypted+read-only-off:=*
	# )
	kernel_args+=( usrhash="$(jq -r '.[] | select(.type == "usr-x86-64").roothash' "$tempfile")" )
	# kernel_args+=( root=PARTUUID="$(jq -r '.[] | select(.type == "root-x86-64").uuid' "$tempfile")" )
	# cp "${tempfile}" repart.out
	rm "$tempfile"
	rmdir /overlay/dist
	Print 5 image "built image"

	ukify build --linux=/overlay/boot/vmlinuz --cmdline="${kernel_args[*]}" \
		--os-release=@/overlay/usr/lib/os-release --initrd=/overlay/boot/initramfs.cpio.zst \
		--secureboot-private-key=verity.key --secureboot-certificate=verity.crt \
		--output=/overlay/"$IMAGE_ID"-"$IMAGE_VERSION".efi
	Print 5 image 'built uki'
	Print 6 image "${kernel_args[*]}"

	local -r tempdir=$(mktemp -d);
	mkdir -p "$tempdir"/efi "$tempdir"/usr/lib "$tempdir"/dist

	# create the bootloader
	chmod 0700 "$tempdir"/efi
	mount --bind "$tempdir"/efi "$tempdir"/efi
	SYSTEMD_RELAX_ESP_CHECKS=1 bootctl --variables=no --esp-path="$tempdir"/efi install
	umount "$tempdir"/efi

	cp /overlay/"$IMAGE_ID"-"$IMAGE_VERSION".efi "$tempdir"/efi/EFI/Linux/
	cp /overlay/usr/lib/os-release "$tempdir"/usr/lib/
	cp /overlay/"$IMAGE_ID"-"$IMAGE_VERSION".{os,hash,sig}-*.raw "$tempdir"/dist/

	systemd-repart --root="$tempdir" --seed="${args[seed]}" "${repartArgs[@]}" \
		--definitions=/usr/lib/repart.d --include-partitions=esp,linux-generic \
		--dry-run=no /overlay/"$IMAGE_ID"-"$IMAGE_VERSION".raw

	rm -r "$tempdir"

	#
	# unmount the overlay
	#
	fusermount3 -u /overlay
}
Main "$@"
