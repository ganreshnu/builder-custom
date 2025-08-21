FROM gentoo/stage3:nomultilib-systemd
COPY portage /etc/portage

ARG jobs=2
#
# install the kernel sources
#
RUN emerge --jobs=$jobs sys-kernel/vanilla-sources
# make the initramfs builder
RUN cd /usr/src/linux && make -C usr gen_init_cpio
# copy in kernel.config
COPY kernel.config /usr/src/linux/arch/x86/configs/
RUN cd /usr/src/linux; make defconfig && make kernel.config

ENV PACKAGES="dev-vcs/git \
	sys-boot/grub \
	sys-kernel/linux-firmware sys-firmware/intel-microcode net-wireless/wireless-regdb \
	sys-fs/dosfstools sys-fs/fuse-overlayfs sys-fs/erofs-utils"
# RUN emerge --pretend ${PACKAGES} && exit 1
RUN emerge --jobs=$jobs ${PACKAGES}

# deal with the microcode
RUN cpio -i --to-stdout </boot/intel-uc.img kernel/x86/microcode/GenuineIntel.bin > /boot/intel-uc.bin
RUN cpio -i --to-stdout </boot/amd-uc.img kernel/x86/microcode/AuthenticAMD.bin > /boot/amd-uc.bin

# generate locales
COPY locale.gen /etc/
RUN locale-gen --update

# create the overlay directory
RUN mkdir /overlay

# copy the basefs and initramfs configs
COPY basefs initramfs /usr/share/

# copy the scripts
COPY scripts /usr/share/scripts
RUN cd /usr/bin; for script in ../share/scripts/*.bash; do [[ -x "$script" ]] && { fileName="$(basename $script)"; ln -s "${script}" "${fileName%.bash}"; } || true; done

ENTRYPOINT [ "unshare", "--mount", "--map-users=all", "--map-groups=all", "entrypoint" ]
