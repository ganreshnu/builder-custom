FROM docker.io/gentoo/stage3:systemd
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

RUN emerge --jobs=$jobs --update --newuse --deep @world
# sys-boot/grub 
ENV PACKAGES="dev-vcs/git app-portage/gentoolkit \
	app-emulation/xen \
	sys-kernel/linux-firmware sys-firmware/intel-microcode net-wireless/wireless-regdb \
	sys-fs/dosfstools sys-fs/fuse-overlayfs sys-fs/erofs-utils sys-fs/mtools sys-fs/btrfs-progs \
	dev-lang/go app-misc/jq \
	app-crypt/sbsigntools"
RUN emerge --jobs=$jobs ${PACKAGES}
# RUN emerge --jobs=$jobs sys-boot/grub sys-boot/shim
RUN git -C /usr/share clone --depth=1 https://github.com/square/certstrap.git \
	&& cd /usr/share/certstrap && go build && ln -s /usr/share/certstrap/certstrap /usr/bin/certstrap

# deal with the microcode
RUN cpio -i --to-stdout </boot/intel-uc.img kernel/x86/microcode/GenuineIntel.bin > /boot/intel-uc.bin
RUN cpio -i --to-stdout </boot/amd-uc.img kernel/x86/microcode/AuthenticAMD.bin > /boot/amd-uc.bin

# generate locales
COPY locale.gen /etc/
# RUN locale-gen
RUN touch /etc/machine-id

# COPY catalyst* /etc/catalyst/
# COPY catalyst.conf /etc/catalyst/catalyst.conf
# COPY catalystrc /etc/catalyst/catalystrc

# create the overlay directory
RUN mkdir /overlay

# copy the basefs and initramfs configs
COPY basefs /usr/share/basefs
COPY initramfs /usr/share/initramfs

COPY verity-cert.config /usr/share/verity-cert.config
COPY grub-internal.cfg /usr/share/grub-internal.cfg
COPY loader.conf /boot/loader.conf
COPY entries.srel /boot/entries.srel

# copy the scripts
COPY scripts /usr/share/scripts
RUN cd /usr/bin; for script in ../share/scripts/*.bash; do [[ -x "$script" ]] && { fileName="$(basename $script)"; ln -s "${script}" "${fileName%.bash}"; } || true; done

ENTRYPOINT [ "unshare", "--mount", "--map-users=all", "--map-groups=all", "entrypoint" ]
