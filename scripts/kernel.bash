#!/bin/bash
set -euo pipefail
. /usr/share/scripts/util.bash

Usage() {
	cat <<EOD
Usage: $(basename ${BASH_SOURCE[0]}) [OPTIONS] [DIRECTORY...]

Options:
  --nproc INT                Number of threads to use.
  --kconfig FILE             Kernel configuration fragment file to apply. Can
                             be passed multiple times.
  --rootpw                   Root password for initrd encrypted with mkpasswd(1).
  --root DIRECTORY           The directory in which to install the emergeArgs.
  --workdir DIRECTORY        OverlayFS workdir which must be on the same
                             partition as the layer directories.
  --help                     Display this message and exit.

Configures and builds a kernel. If directories are passed, creates an initramfs.

NOTE: mkpasswd(1) is a part of the whois package.
EOD
}

Main() {
	local -A args=(
		[nproc]=$(nproc)
		[rootpw]=
		[root]=
		[workdir]=
	)
	local argv=()
	local kconfigs=()
	while (( $# > 0 )); do
		case "$1" in
			--nproc* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[nproc]="$value"
				;;
			--kconfig* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				kconfigs+=( "$value" )
				;;
			--rootpw* )
				local value= count=0
				ExpectArg value count "$@"; shift $count
				args[rootpw]="$value"
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

	[[ -z "${args[root]}" ]] && { >&2 Print 1 kernel "missing required option --root"; return 1; }
	[[ -z "${args[workdir]}" ]] && { >&2 Print 1 kernel "missing required option --workdir"; return 1; }

	local -r rootPath="$(realpath ${args[root]})"

	#
	# build the kernel
	#
	if [[ ! -f "${args[root]}"/efi/kconfig.zst ]]; then
		Print 5 kernel "building the kernel"
		# configure the kernel sources
		/usr/share/scripts/kconfig.bash "${kconfigs[@]}"
		# build and install the kernel
		pushd /usr/src/linux >/dev/null
		make -j"${args[nproc]}" --quiet
		# Print 5 kernel "built kernel"
		[[ -d "${rootPath}"/usr/lib/modules/"$(KVersion)" ]] && rm -r "${rootPath}"/usr/lib/modules/"$(KVersion)"
		make INSTALL_MOD_PATH="${rootPath}"/usr INSTALL_MOD_STRIP=1 modules_install
		make INSTALL_PATH="${rootPath}"/efi install
		# Print 5 kernel "installed modules and kernel to ${args[root]}"
		cp /boot/*-uc.img "${rootPath}"/efi/
		zstd --quiet .config -o "${rootPath}"/efi/kconfig.zst
		# Print 5 kernel "saved kernel configuration to ${args[root]}/efi/kconfig.zst"
		popd >/dev/null #/usr/src/linux
	fi

	#
	# build the initramfs
	#
	if (( $# > 0 )) && [[ ! -f "${args[root]}"/efi/initramfs.cpio.zst ]]; then
		local lowers=() modules=()
		for arg in "$@"; do
			if [[ -d "${arg}" ]]; then
				lowers+=( "${arg}" )
			elif [[ -f "${arg}" ]]; then
				mapfile -t <"${arg}"
				for item in "${MAPFILE[@]}"; do
					[[ "${item}" != \#* ]] && modules+=( "${item}" )
					done
				else
					modules+=( "${arg}" )
			fi
		done

		Print 5 kernel "building the initramfs"

		#
		# mount the overlay
		#
		fuse-overlayfs -o lowerdir=$(Join : "${lowers[@]}"),upperdir="${args[root]}",workdir="${args[workdir]}" /overlay || { >&2 Print 1 packages "overlay mount failed"; return 1; }

		#
		# copy the base files
		#
		local -r excludes=(
			--exclude=usr/lib/systemd/system-environment-generators/10-gentoo-path
			--exclude=usr/share/factory/etc/locale.conf
			--exclude=usr/share/factory/etc/vconsole.conf
		)
		mkdir -p /tmp/initramfs
		tar --directory=/overlay --create --preserve-permissions "${excludes[@]}" bin lib lib64 sbin usr \
			|tar --directory=/tmp/initramfs --extract --keep-directory-symlink

		#
		# unmount the overlay
		#
		fusermount3 -u /overlay

		#
		# copy modules
		#
		mkdir -p /tmp/initramfs/usr/lib/modules/$(KVersion)
		rm -fr /tmp/initramfs/usr/lib/modules/$(KVersion)/*
		for module in "${modules[@]}"; do CopyModule "${module}"; done
		cp "${args[root]}"/usr/lib/modules/$(KVersion)/modules.{order,builtin,builtin.modinfo} /tmp/initramfs/usr/lib/modules/$(KVersion)/
		depmod --basedir=/tmp/initramfs --outdir=/tmp/initramfs $(KVersion)

		#
		# setup the filesystem
		#
		mkdir -p /tmp/initramfs/{dev,etc,proc,run,sys,tmp}
		ln -sf ../usr/lib/os-release /tmp/initramfs/etc/initrd-release
		ln -sf usr/lib/systemd/systemd /tmp/initramfs/init
		systemd-sysusers --root=/tmp/initramfs
		# systemd-tmpfiles --root=/tmp/initramfs --create

		# set root password
		[[ -n "${args[rootpw]}" ]] && echo "root:${args[rootpw]}" |chpasswd --prefix /tmp/initramfs --encrypted

		#
		# create cpio
		#
		Print 6 kernel "initramfs uncompressed size is $(du -sh /tmp/initramfs |cut -f1)"
		pushd /usr/src/linux >/dev/null
		mkdir -p "${rootPath}"/efi
		usr/gen_initramfs.sh -o /dev/stdout /tmp/initramfs \
			| zstd --compress --stdout > "${rootPath}"/efi/initramfs.cpio.zst
		popd >/dev/null #/usr/src/linux/
	fi

	#
	# build the bootloader
	#
	Print 5 kernel "building the bootloader"
	mkdir -p "${args[root]}"/efi/EFI/BOOT
	grub-mkimage --config=/usr/share/grub-internal.cfg --compression=auto --format=x86_64-efi --prefix='(memdisk)' --output="${args[root]}"/efi/EFI/BOOT/BOOTX64.efi \
		bli part_gpt efi_gop configfile fat search echo linux multiboot2 gzio regexp sleep

	# copy over xen.gz
	mkdir -p "${args[root]}"/efi/xen
	cp -L /boot/xen.gz "${args[root]}"/efi/xen/
	cp /boot/*-uc.bin "${args[root]}"/efi/xen/
}
CopyModule() {
	for module in $(modprobe --dirname="${args[root]}/usr" --set-version="$(KVersion)" --show-depends "$*" |cut -d ' ' -f 2); do

		local modulefile=$(modinfo --basedir="${args[root]}" -k "${args[root]}"/usr/lib/modules/$(KVersion)/vmlinuz --field=filename "${module}")
		modulefile="${modulefile#${PWD}/${args[root]}/}"

		mkdir -p /tmp/initramfs/"$(dirname $modulefile)"
		cp "${args[root]}"/"${modulefile}" /tmp/initramfs/"${modulefile}"
		Print 6 CopyModule "copied ${modulefile}"
	done
}
Main "$@"
