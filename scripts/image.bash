#!/bin/bash
set -euo pipefail
. /usr/share/scripts/util.bash

Usage() {
	cat <<EOD
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] [DIRECTORY...]

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
		[root]=''
		[disk]=''
		[seed]=random
		[locales]=''
	)
	local argv=()
	while (( $# > 0 )); do
		case "$1" in
			--root* )
				local value='' count=0
				ExpectArg value count "$@"; shift $count
				args[root]="$value"
				;;
			--disk* )
				local value='' count=0
				ExpectArg value count "$@"; shift $count
				args[disk]="$value"
				;;
			--seed* )
				local value='' count=0
				ExpectArg value count "$@"; shift $count
				args[seed]="$value"
				;;
			--locales* )
				local value='' count=0
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

	local lowers=()
	local excludes=(
		--exclude=efi/kconfig.zst
		--exclude=efi/System.map
		--exclude=usr/lib/systemd/system-environment-generators/10-gentoo-path
		--exclude=usr/share/factory/etc/locale.conf
		--exclude=usr/share/factory/etc/vconsole.conf
	)
	local repartArgs=( --exclude-partitions=swap )
	for arg in "$@"; do
		if [[ -d "${arg}" ]]; then
			lowers+=( "${arg}" )
		elif [[ -f "${arg}" ]]; then
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
	fuse-overlayfs -o lowerdir="$(Join : "${lowers[@]}")" /overlay || { >&2 Print 1 packages "overlay mount failed"; return 1; }

	# SetupRoot "${args[root]}"
	# local includes=( usr boot )
	# [[ -d /overlay/efi ]] && includes+=( efi )
	# tar --directory=/overlay --create --preserve-permissions "${excludes[@]}" "${includes[@]}" \
	# 	|tar --directory="${args[root]}" --extract --keep-directory-symlink

	#
	# copy the gcc redis folder
	#
	# TarCp /usr/lib/gcc/x86_64-pc-linux-gnu/14/ "${args[root]}"/usr/lib64/

	# cp /etc/ca-certificates.conf "${args[root]}"/usr/share/factory/etc/
	# echo 'C /etc/ca-certificates.conf' >"${args[root]}"/usr/lib/tmpfiles.d/ssl.conf
	# echo 'd /etc/ssl/certs' >>"${args[root]}"/usr/lib/tmpfiles.d/ssl.conf

	#
	# generate the locales
	#
	[[ -n "${args[locales]}" ]] && locale-gen --prefix "$(realpath "${args[root]}")" --config "${args[locales]}"

	# #
	# # build the bootloader
	# #
	# Print 5 kernel "building the bootloader"
	# mkdir -p "${args[root]}"/efi/EFI/BOOT
	# grub-mkimage --config=/usr/share/grub-internal.cfg --compression=auto --format=x86_64-efi --prefix='(memdisk)' --output="${args[root]}"/efi/EFI/BOOT/BOOTX64.efi \
	# 	bli part_gpt efi_gop configfile fat search echo linux multiboot2 gzio regexp sleep chain
	#
	# # copy over xen.gz
	# mkdir -p "${args[root]}"/efi/xen
	# cp -L /boot/xen.gz "${args[root]}"/efi/xen/
	# cp /boot/*-uc.bin "${args[root]}"/efi/xen/
	mkdir -p "${args[root]}"/boot/EFI/BOOT
	mkdir -p "${args[root]}"/boot/loader/entries
	cp /boot/loader.conf "${args[root]}"/boot/loader/
	cp /boot/entries.srel "${args[root]}"/boot/loader/
	cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi "${args[root]}"/boot/EFI/BOOT/BOOTX64.EFI
	# bootctl --esp-path="${args[root]}"/boot random-seed

	#
	# build the diskimage
	#
	local -r tempfile=$(mktemp)
	[[ -n "${args[disk]}" ]] && systemd-repart --root="${args[root]}" --seed="${args[seed]}" "${repartArgs[@]}" \
		--defer-partitions=esp \
		--empty=create --size=auto --split=yes --json=short "${args[disk]}" >"${tempfile}"
	local -r rootUUID=$(jq -r '.[] | select(.type == "root-x86-64").uuid' "${tempfile}")
	local -r usrhash=$(jq -r '.[] | select(.type == "usr-x86-64").roothash' "${tempfile}")
	# cp "${tempfile}" repart.out
	rm "${tempfile}"

	Print 5 image built image
	echo "rootUUID:${rootUUID}"
	echo "usrhash:${usrhash}"
	# veritysetup dump "${args[disk]/.raw/.usr-x86-64-verity.raw}" >cmd.veritysetup.stdout
	# local -r dataBlocks=$(awk '/^Data blocks/ {print $NF}' cmd.veritysetup.stdout)
	# local -r dataBlockSize=$(awk '/^Data block size/ {print $(NF-1)}' cmd.veritysetup.stdout)
	# local -r dataSectors=$(( $dataBlocks * $dataBlockSize / 512 ))
	# local -r hashBlockSize=$(awk '/^Hash block size/ {print $(NF-1)}' cmd.veritysetup.stdout)
	# local -r hashAlgorithm=$(awk '/^Hash algorithm/ {print $NF}' cmd.veritysetup.stdout)
	# local -r salt=$(awk '/^Salt/ {print $NF}' cmd.veritysetup.stdout)
	# dm-mod.create="usr-verity,,,ro,0 ${dataSectors} verity 1 /dev/nvme0n1p2 /dev/nvme0n1p3 ${dataBlockSize} ${hashBlockSize} ${dataBlocks} 1 ${hashAlgorithm} ${usrhash} ${salt} 1 ignore_zero_blocks"

	# local -r microcode=amd-uc.img
	# local -r microcode=intel-uc.img
	# local -r microcode=
	local cmdlineArgs=(
		consoleblank=60
		rw
		root=PARTUUID="$rootUUID"
		usrhash="$usrhash"
	)
	ukify build --linux=/overlay/efi/vmlinuz --cmdline="${cmdlineArgs[*]}" \
		--os-release=@/overlay/usr/lib/os-release --initrd=/overlay/efi/initramfs.cpio.zst \
		--secureboot-private-key=verity.key --secureboot-certificate=verity.crt \
		--output="${args[root]}"/efi/uki.efi

	systemd-repart --root="${args[root]}" --seed="${args[seed]}" --include-partitions=esp --split=yes --dry-run=no "${args[disk]}"

	#
	# unmount the overlay
	#
	fusermount3 -u /overlay
}
Main "$@"
