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
  --disk        FILE|BLOCKDEV  A filename or block device on which to write the
                               generated image.
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
		[disk]=''
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
	# local repartArgs=( --exclude-partitions=swap )
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
	fuse-overlayfs -o lowerdir="$(Join : "${lowers[@]}")",upperdir="${args[root]}",workdir="${args[workdir]}" /overlay || { >&2 Print 1 packages "overlay mount failed"; return 1; }

	# SetupRoot "${args[root]}"
	# local includes=( usr boot )
	# [[ -d /overlay/efi ]] && includes+=( efi )
	# tar --directory=/overlay --create --preserve-permissions "${excludes[@]}" "${includes[@]}" \
	# 	|tar --directory="${args[root]}" --extract --keep-directory-symlink

	# cp /etc/ca-certificates.conf "${args[root]}"/usr/share/factory/etc/
	# echo 'C /etc/ca-certificates.conf' >"${args[root]}"/usr/lib/tmpfiles.d/ssl.conf
	# echo 'd /etc/ssl/certs' >>"${args[root]}"/usr/lib/tmpfiles.d/ssl.conf

	#
	# generate the locales
	#
	# [[ -n "${args[locales]}" ]] && locale-gen --prefix /overlay --config "${args[locales]}"

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
	# mkdir -p "${args[root]}"/boot/EFI/BOOT
	# mkdir -p "${args[root]}"/boot/loader/entries
	# cp /boot/loader.conf "${args[root]}"/boot/loader/
	# cp /boot/entries.srel "${args[root]}"/boot/loader/
	# cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi "${args[root]}"/boot/EFI/BOOT/BOOTX64.EFI
	# bootctl --esp-path="${args[root]}"/boot random-seed

	#
	# build the diskimage
	#
	local -r tempfile=$(mktemp)
	[[ -n "${args[disk]}" ]] && systemd-repart --root=/overlay --seed="${args[seed]}" "${repartArgs[@]}" \
		--defer-partitions=esp --definitions=/usr/lib/repart.d \
		--empty=create --size=auto --split=yes --json=short "${args[disk]}" >"${tempfile}"
	# local -r rootUUID=$(jq -r '.[] | select(.type == "root-x86-64").uuid' "${tempfile}")
	local -r usrhash=$(jq -r '.[] | select(.type == "usr-x86-64").roothash' "${tempfile}")
	# cp "${tempfile}" repart.out
	rm "${tempfile}"

	Print 5 image 'built image'
	# echo "rootUUID:${rootUUID}"
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
	# 		root=PARTUUID="$rootUUID"
	kernel_args+=( usrhash="$usrhash")
	mkdir -p /overlay/efi
	ukify build --linux=/overlay/boot/vmlinuz --cmdline="${kernel_args[*]}" \
		--os-release=@/overlay/usr/lib/os-release --initrd=/overlay/boot/initramfs.cpio.zst \
		--secureboot-private-key=verity.key --secureboot-certificate=verity.crt \
		--output=/overlay/efi/uki.efi

	Print 5 image 'built uki'
	# builder -- ukify --cmdline='consoleblank=60 systemd.hostname=installer rw systemd.set_credential=passwd.hashed-password.root: rdinit=/usr/lib/systemd/systemd' --microcode=build/kernel/efi/intel-uc.img

	Print 5 image 'systemd-repart 2nd run'
	systemd-repart --root=/overlay --seed="${args[seed]}" --include-partitions=esp --definitions=/usr/lib/repart.d --split=yes --dry-run=no "${args[disk]}"

	#
	# unmount the overlay
	#
	fusermount3 -u /overlay
}
Main "$@"
