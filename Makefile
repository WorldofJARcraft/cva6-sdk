# Makefile for RISC-V toolchain; run 'make help' for usage. set XLEN here to 32 or 64.

BOARD    ?= genesys2
target   ?= cv64a6_imafdc_sv39

# e.g., cv64a6
CVA6_TYPE=$(firstword $(subst _, ,$(target)))
# e.g., imafdc
ISA_TYPE=$(word 2,$(subst _, ,$(target)))

SED ?= sed

ifeq ($(CVA6_TYPE), cv64a6)
XLEN := 64
CVA6_IS_CV64A6 := y
CVA6_IS_CV32A6 := n
else
XLEN := 32
CVA6_IS_CV32A6 := y
CVA6_IS_CV64A6 := n
endif

ifeq ($(ISA_TYPE), imafdc)
CVA6_HAS_FPU := y
else
CVA6_HAS_FPU := n
endif

$(info CVA6_TYPE is $(CVA6_TYPE) ISA_TYPE is $(ISA_TYPE) XLEN is $(XLEN))

ifeq ($(BOARD), nexys_video)
DRAM_SIZE_64 ?= 0x20000000 #512MB
DRAM_SIZE_32 ?= 0x08000000 #128MB
CLOCK_FREQUENCY ?= 25000000 #25MHz
HALF_CLOCK_FREQUENCY ?= 12500000 #12.5MHz
UART_BITRATE ?= 57600
HAS_ETHERNET ?= 0
else
ifeq ($(BOARD), arty_a7_100)
DRAM_SIZE_64 ?= 0x10000000 #256MB
DRAM_SIZE_32 ?= 0x08000000 #128MB
CLOCK_FREQUENCY ?= 25000000 #25MHz
HALF_CLOCK_FREQUENCY ?= 12500000 #12.5MHz
UART_BITRATE ?= 57600
HAS_ETHERNET ?= 0
else
DRAM_SIZE_64 ?= 0x40000000 #1GB
DRAM_SIZE_32 ?= 0x08000000 #128MB
CLOCK_FREQUENCY ?= 50000000 #50MHz
HALF_CLOCK_FREQUENCY ?= 25000000 #25MHz
UART_BITRATE ?= 115200
HAS_ETHERNET ?= 1
endif
endif

ifeq ($(HAS_ETHERNET), 1)
SED_DELETE_OPT = -e "/DELETE_ETH/d"
else
SED_DELETE_OPT =
endif

ROOT     := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
RISCV    := $(PWD)/install$(XLEN)
DEST     := $(abspath $(RISCV))
PATH     := $(DEST)/bin:$(PATH)

TOOLCHAIN_PREFIX := $(ROOT)/buildroot/output/host/bin/riscv$(XLEN)-buildroot-linux-gnu-
CC          := $(TOOLCHAIN_PREFIX)gcc
OBJCOPY     := $(TOOLCHAIN_PREFIX)objcopy
MKIMAGE     := u-boot/tools/mkimage

NR_CORES := $(shell nproc)

# SBI options
PLATFORM := fpga/ariane
FW_FDT_PATH ?=
sbi-mk = PLATFORM=$(PLATFORM) CROSS_COMPILE=$(TOOLCHAIN_PREFIX) $(if $(FW_FDT_PATH),FW_FDT_PATH=$(FW_FDT_PATH),)
ifeq ($(XLEN), 32)
sbi-mk += PLATFORM_RISCV_ISA=rv32$(ISA_TYPE) PLATFORM_RISCV_XLEN=32
else
sbi-mk += PLATFORM_RISCV_ISA=rv64$(ISA_TYPE) PLATFORM_RISCV_XLEN=64
endif

# U-Boot options
ifeq ($(XLEN), 32)
UIMAGE_LOAD_ADDRESS := 0x80400000
UIMAGE_ENTRY_POINT  := 0x80400000
else
UIMAGE_LOAD_ADDRESS := 0x80200000
UIMAGE_ENTRY_POINT  := 0x80200000
endif

# default configure flags
tests-co              = --prefix=$(RISCV)/target

# specific flags and rules for 32 / 64 version
ifeq ($(XLEN), 32)
isa-sim-co            = --prefix=$(RISCV) --with-isa=RV32IMA --with-priv=MSU
else
isa-sim-co            = --prefix=$(RISCV)
endif

# default make flags
isa-sim-mk              = -j$(NR_CORES)
tests-mk         		= -j$(NR_CORES)
buildroot-mk       		= -j$(NR_CORES)

# linux image
buildroot_defconfig = configs/.buildroot_defconfig
linux_defconfig = configs/.linux_defconfig
busybox_defconfig = configs/.busybox.config

install-dir:
	mkdir -p $(RISCV)

isa-sim: install-dir $(CC) 
	mkdir -p riscv-isa-sim/build
	cd riscv-isa-sim/build;\
	../configure $(isa-sim-co);\
	make $(isa-sim-mk);\
	make install;\
	cd $(ROOT)

tests: install-dir $(CC)
	mkdir -p riscv-tests/build
	cd riscv-tests/build;\
	autoconf;\
	../configure $(tests-co);\
	make $(tests-mk);\
	make install;\
	cd $(ROOT)

$(buildroot_defconfig): configs/buildroot_defconfig
	$(SED) -e "s/CVA6_IS_CV64A6/$(CVA6_IS_CV64A6)/g" \
               -e "s/CVA6_IS_CV32A6/$(CVA6_IS_CV32A6)/g" \
               -e "s/CVA6_HAS_FPU/$(CVA6_HAS_FPU)/g" \
               $(SED_DELETE_OPT) $< > $@

$(linux_defconfig): configs/linux_defconfig
	$(SED) -e "s/CVA6_IS_CV64A6/$(CVA6_IS_CV64A6)/g" \
               -e "s/CVA6_IS_CV32A6/$(CVA6_IS_CV32A6)/g" \
               -e "s/CVA6_HAS_FPU/$(CVA6_HAS_FPU)/g" \
               $(SED_DELETE_OPT) $< > $@

$(busybox_defconfig): configs/busybox.config
	$(SED) -e "s/CVA6_IS_CV64A6/$(CVA6_IS_CV64A6)/g" \
               -e "s/CVA6_IS_CV32A6/$(CVA6_IS_CV32A6)/g" \
               -e "s/CVA6_HAS_FPU/$(CVA6_HAS_FPU)/g" \
               $(SED_DELETE_OPT) $< > $@

$(CC): $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig)
	make -C buildroot defconfig BR2_DEFCONFIG=../$(buildroot_defconfig)
	make -C buildroot host-gcc-final $(buildroot-mk)

all: $(CC) isa-sim

# benchmark for the cache subsystem
rootfs/cachetest.elf: $(CC)
	cd ./cachetest/ && $(CC) cachetest.c -o cachetest.elf
	cp ./cachetest/cachetest.elf $@

# cool command-line tetris
rootfs/tetris: $(CC)
	cd ./vitetris/ && make clean && ./configure CC=$(CC) && make
	cp ./vitetris/tetris $@

$(RISCV)/vmlinux: $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig) $(CC) rootfs/cachetest.elf rootfs/tetris
	mkdir -p $(RISCV)
	make -C buildroot $(buildroot-mk)
	cp buildroot/output/images/vmlinux $@

$(RISCV)/Image: $(RISCV)/vmlinux
	$(OBJCOPY) -O binary -R .note -R .comment -S $< $@

$(RISCV)/Image.gz: $(RISCV)/Image
	gzip -9 -k --force $< > $@

# U-Boot-compatible Linux image
$(RISCV)/uImage: $(RISCV)/Image.gz $(MKIMAGE)
	$(MKIMAGE) -A riscv -O linux -T kernel -a $(UIMAGE_LOAD_ADDRESS) -e $(UIMAGE_ENTRY_POINT) -C gzip -n "CV$(XLEN)A6Linux" -d $< $@

$(RISCV)/u-boot.bin: u-boot/u-boot.bin
	mkdir -p $(RISCV)
	cp $< $@

u-boot/arch/riscv/dts/cv$(XLEN)a6.dts: u-boot/arch/riscv/dts/cv$(XLEN)a6.dts.in
	$(SED) -e "s/DRAM_SIZE_64/$(DRAM_SIZE_64)/g" \
               -e "s/DRAM_SIZE_32/$(DRAM_SIZE_32)/g" \
               -e "s/HALF_CLOCK_FREQUENCY/$(HALF_CLOCK_FREQUENCY)/g" \
               -e "s/CLOCK_FREQUENCY/$(CLOCK_FREQUENCY)/g" \
               -e "s/UART_BITRATE/$(UART_BITRATE)/g" \
               $(SED_DELETE_OPT) $< > $@
	cat $@

# TODO name genesysII kept for now
# DTS update makes sure this works for all boards
$(MKIMAGE) u-boot/u-boot.bin: $(CC) u-boot/arch/riscv/dts/cv$(XLEN)a6.dts
	make -C u-boot openhwgroup_cv$(XLEN)a6_genesysII_defconfig
	make -C u-boot CROSS_COMPILE=$(TOOLCHAIN_PREFIX)

# OpenSBI with u-boot as payload
$(RISCV)/fw_payload.bin: $(RISCV)/u-boot.bin
	make -C opensbi FW_PAYLOAD_PATH=$< $(sbi-mk)
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/fw_payload.elf
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/fw_payload.bin

# OpenSBI for Spike with Linux as payload
$(RISCV)/spike_fw_payload.elf: PLATFORM=generic
$(RISCV)/spike_fw_payload.elf: $(RISCV)/Image
	make -C opensbi FW_PAYLOAD_PATH=$< $(sbi-mk)
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/spike_fw_payload.elf
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/spike_fw_payload.bin

# need to run flash-sdcard with sudo -E, be careful to set the correct SDDEVICE
# Number of sector required for FWPAYLOAD partition (each sector is 512B)
FWPAYLOAD_SECTORSTART := 2048
FWPAYLOAD_SECTORSIZE = $(shell ls -l --block-size=512 $(RISCV)/fw_payload.bin | cut -d " " -f5 )
FWPAYLOAD_SECTOREND = $(shell echo $(FWPAYLOAD_SECTORSTART)+$(FWPAYLOAD_SECTORSIZE) | bc)
SDDEVICE_PART1 = $(shell lsblk $(SDDEVICE) -no PATH | head -2 | tail -1)
SDDEVICE_PART2 = $(shell lsblk $(SDDEVICE) -no PATH | head -3 | tail -1)
# Always flash uImage at 512M, easier for u-boot boot command
UIMAGE_SECTORSTART := 512M
flash-sdcard: format-sd
	dd if=$(RISCV)/fw_payload.bin of=$(SDDEVICE_PART1) status=progress oflag=sync bs=1M
	dd if=$(RISCV)/uImage         of=$(SDDEVICE_PART2) status=progress oflag=sync bs=1M

format-sd: $(SDDEVICE)
	@test -n "$(SDDEVICE)" || (echo 'SDDEVICE must be set, Ex: make flash-sdcard SDDEVICE=/dev/sdc' && exit 1)
	sgdisk --clear -g --new=1:$(FWPAYLOAD_SECTORSTART):$(FWPAYLOAD_SECTOREND) --new=2:$(UIMAGE_SECTORSTART):0 --typecode=1:3000 --typecode=2:8300 $(SDDEVICE)

# specific recipes
gcc: $(CC)
vmlinux: $(RISCV)/vmlinux
fw_payload.bin: $(RISCV)/fw_payload.bin
uImage: $(RISCV)/uImage
spike_payload: $(RISCV)/spike_fw_payload.elf

images: $(CC) $(RISCV)/fw_payload.bin $(RISCV)/uImage

clean:
	rm -rf $(buildroot_defconfig)
	rm -rf $(linux_defconfig)
	rm -rf $(busybox_defconfig)
	rm -rf u-boot/arch/riscv/dts/cv$(XLEN)a6.dts
	rm -rf $(RISCV)/vmlinux cachetest/*.elf rootfs/tetris rootfs/cachetest.elf
	rm -rf $(RISCV)/fw_payload.bin $(RISCV)/uImage $(RISCV)/Image.gz
	make -C u-boot clean
	make -C opensbi distclean

clean-all: clean
	rm -rf $(RISCV) riscv-isa-sim/build riscv-tests/build
	make -C buildroot clean

.PHONY: gcc vmlinux images help fw_payload.bin uImage

help:
	@echo "usage: $(MAKE) [tool/img] ..."
	@echo ""
	@echo "install compiler with"
	@echo "    make gcc"
	@echo ""
	@echo "install [tool] with compiler"
	@echo "    where tool can be any one of:"
	@echo "        gcc isa-sim tests"
	@echo ""
	@echo "build linux images for cva6"
	@echo "        make images"
	@echo "    for specific artefact"
	@echo "        make [vmlinux|uImage|fw_payload.bin]"
	@echo ""
	@echo "There are two clean targets:"
	@echo "    Clean only build object"
	@echo "        make clean"
	@echo "    Clean everything (including toolchain etc)"
	@echo "        make clean-all"
