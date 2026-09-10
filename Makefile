# SPDX-License-Identifier: GPL-2.0
#
# Makefile for AW88399 HDA DKMS package
#
# Builds:
#   - snd-hda-codec-alc269.ko      (patched Realtek codec with AW88399 fixup)
#   - snd-soc-aw88399.ko           (patched ASoC codec with exports)
#   - snd-hda-scodec-aw88399.ko    (new HDA side codec driver)
#   - snd-hda-scodec-aw88399-i2c.ko (new I2C interface)
#   - serial-multi-instantiate.ko  (patched with AWDZ8399 support)
#   - aw88399-setup.ko             (scan.c workaround helper)

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
PWD := $(shell pwd)

# Module definitions
obj-m += snd-hda-codec-alc269.o
obj-m += snd-soc-aw88399.o
obj-m += snd-hda-scodec-aw88399.o
obj-m += snd-hda-scodec-aw88399-i2c.o
obj-m += serial-multi-instantiate.o
obj-m += aw88399-setup.o

# Object file mappings
snd-hda-codec-alc269-y := realtek/alc269.o
snd-soc-aw88399-y := soc-codecs/aw88399.o
snd-hda-scodec-aw88399-y := side-codecs/aw88399_hda.o
snd-hda-scodec-aw88399-i2c-y := side-codecs/aw88399_hda_i2c.o
aw88399-setup-y := aw88399_setup.o

# Include paths - we ship local copies of headers not in kernel-headers pkg
ccflags-y += -I$(src)/common
ccflags-y += -I$(src)/codecs

# Subdirectory-specific flags
CFLAGS_realtek/alc269.o += -I$(src)/realtek -I$(src)/common -I$(src)/codecs -I$(src)/side-codecs -I$(src)
CFLAGS_soc-codecs/aw88399.o += -I$(src)/soc-codecs -I$(src)/soc-codecs/aw88395
CFLAGS_side-codecs/aw88399_hda.o += -I$(src)/side-codecs -I$(src)/common -I$(src)/codecs -I$(src)
CFLAGS_side-codecs/aw88399_hda_i2c.o += -I$(src)/side-codecs

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

install:
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install
	depmod -a $(KVER)

.PHONY: all clean install
