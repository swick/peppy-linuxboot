###################################
# chromebook c720 peppy linuxboot #
###################################

# TODO make sure dependencies are installed
# TODO make update to update coreboot, linux and u-root

SHELL := /bin/bash


### SETTINGS ###

# where the original firmware image resides or should be read to
ORIGINAL_FIRMWARE := peppy.rom
# git repository to clone for coreboot
COREBOOT_GIT := https://review.coreboot.org/coreboot.git
# git checkout to build coreboot from
COREBOOT_CHECKOUT := master
# git repository to clone for linux
LINUX_GIT := git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
# git checkout to build linux from
LINUX_CHECKOUT := master
# u-root to go get from
U_ROOT_SRC := github.com/u-root/u-root
# u-root cmds and/or modules to build into the linux initramfs
U_ROOT_CMDS := core/init core/elvish core/dmesg core/ls core/lsmod core/mount core/umount boot/localboot
U_ROOT_MODULES := 
# programmer to use for reading/writing the peppy SPI flash
FLASHROM_PROGRAMMER := ch341a_spi
# the config to build coreboot from:	coreboot-peppy-linuxboot.config
# the config to build linux from:	linux-peppy-linuxboot.config


### GOALS ###

# all		create the linuxboot flash rom for peppy (peppy-linuxboot.rom)
# blobs		extract blobs from the original firmware
# flash_read	read the original firmware from the SPI flash chip
# flash_write	write the linuxboot firmware to the SPI flash chip
# clean		clean all build artifacts
# clean_blobs	clean all the extracted firmware blobs
# distclean	clean everything including the downloaded sources
.PHONY: all blobs flash_read flash_write clean clean_blobs distclean


### INTERNAL ###

pwd:=$(shell pwd)
gopath := GOPATH=$(pwd)/go PATH="$(pwd)/go/bin:$$PATH"

ifdtool_dir := ./coreboot/util/ifdtool
ifdtool := $(ifdtool_dir)/ifdtool

cbfstool_dir := ./coreboot/util/cbfstool
cbfstool := $(cbfstool_dir)/cbfstool

xgcc := ./coreboot/util/crossgcc/xgcc/bin/i386-elf-gcc
u_root_src := $(pwd)/go/src/github.com/u-root/u-root
u_root_cmds := $(foreach module,$(U_ROOT_CMDS),$(U_ROOT_SRC)/cmds/$(module))

all: peppy-linuxboot.rom

clean:
	rm -f peppy-linuxboot.rom bzImage initramfs.cpio initramfs.cpio.xz

clean_blobs:
	rm -rf blobs/

distclean: clean clean_blobs
	rm -rf coreboot/ linux/ go/

flash_read:
	flashrom -p $(FLASHROM_PROGRAMMER) -r $(ORIGINAL_FIRMWARE)

flash_write: peppy-linuxboot.rom
	flashrom -p $(FLASHROM_PROGRAMMER) -w peppy-linuxboot.rom

bzImage: linux/ linux-peppy-linuxboot.config
	cp linux-peppy-linuxboot.config linux/.config
	$(MAKE) -C linux olddefconfig
	$(MAKE) -C linux bzImage
	cp linux/arch/x86/boot/bzImage .

$(u_root_src):
	$(gopath) go get $(U_ROOT_SRC)

initramfs.cpio: | $(u_root_src)
	$(gopath) u-root -build=bb $(u_root_cmds) $(U_ROOT_MODULES)
	cp /tmp/initramfs.linux_amd64.cpio $@

initramfs.cpio.xz: initramfs.cpio
	xz --check=crc32 -9 --lzma2=dict=1MiB --stdout $< | dd conv=sync bs=512 of=$@

coreboot/:
	git clone "$(COREBOOT_GIT)" coreboot && \
	cd coreboot && \
	git submodule update --init --checkout && git checkout $(COREBOOT_CHECKOUT)

linux/:
	git clone "$(LINUX_GIT)" linux
	git checkout $(LINUX_CHECKOUT)

$(xgcc): | coreboot/
	$(MAKE) -C coreboot crossgcc-i386

define err_no_orig_firmware =
Original chromebook c720/peppy flash image is missing!
The original peppy flash image is required to extract firmware blobs.
	use `make ORIGINAL_FIRMWARE=path/to/firmware.rom`
	or place the firmware in the file `peppy.rom`
endef
$(ORIGINAL_FIRMWARE):
	$(error $(err_no_orig_firmware))

$(ifdtool): | coreboot/
	$(MAKE) -C $(ifdtool_dir)

$(cbfstool): | coreboot/
	$(MAKE) -C $(cbfstool_dir)

blobs: blobs/descriptor.bin blobs/me.bin blobs/mrc.bin

blobs/descriptor.bin: $(ORIGINAL_FIRMWARE) | $(ifdtool)
	mkdir -p blobs
	$(ifdtool) -x $<
	mv flashregion_0_flashdescriptor.bin $@
	rm flashregion*

blobs/me.bin: $(ORIGINAL_FIRMWARE) | $(ifdtool)
	mkdir -p blobs
	$(ifdtool) -x $<
	mv flashregion_2_intel_me.bin $@
	rm flashregion*

blobs/mrc.bin: $(ORIGINAL_FIRMWARE) | $(cbfstool)
	mkdir -p blobs
	$(cbfstool) $< extract -r BOOT_STUB -n mrc.bin -f $@

peppy-linuxboot.rom: coreboot-peppy-linuxboot.config bzImage initramfs.cpio.xz blobs/descriptor.bin blobs/me.bin blobs/mrc.bin | coreboot/ $(xgcc)
	$(MAKE) -C coreboot defconfig KBUILD_DEFCONFIG=../coreboot-peppy-linuxboot.config
	$(MAKE) -C coreboot
	cp coreboot/build/coreboot.rom $@

