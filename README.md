# AW88399 HDA DKMS - Speaker Fix for Lenovo Legion Laptops

DKMS-based speaker driver for Lenovo Legion laptops using **Awinic AW88399** smart amplifiers. No kernel recompilation required.

## Supported Laptops

| Model | Product ID | Subsystem ID |
|-------|-----------|-------------|
| Lenovo Legion Pro 7 16IAX10H / Legion Y9000P IAX10H (Intel) | 83F5 | 17aa:3906 |
| Lenovo Legion Y9000P IAX10H | 83F4 | 17aa:3907 |
| Lenovo Legion Pro 7 16AFR10H (AMD) | 83RU | 17aa:3938 |

Model names vary by region. The inspected Y9000P IAX10H reports product ID
`83F5` and **codec** subsystem ID `17aa:3906`; its PCI audio controller reports
`17aa:3d6c`, which is a different identifier.

## Compatibility with the installed system (2026-09-11)

Checked on Ubuntu **26.04.1 LTS**, kernel **7.0.0-31-generic**, Lenovo
**83F5 / Legion Y9000P IAX10H**, Realtek **ALC287**, with PipeWire **1.6.2**
and WirePlumber **0.5.13**:

- **Keep this DKMS package on this kernel.** The stock kernel has the ASoC
  AW88399 driver, but lacks the AW88399 HDA side-codec integration. At boot,
  `aw88399-setup` still replaces the single ACPI client with the two amplifier
  clients required by this machine.
- DKMS **1.0.2** is installed for the running kernel
  (`7.0.0-31-generic`). The previous **1.0.1** remains installed for
  `7.0.0-30-generic` and in the `built` state for `7.0.0-31-generic`, as
  expected after the current-kernel-only upgrade described below. All six
  loaded modules have source versions matching their installed counterparts,
  and their installed `vermagic` matches the running kernel. The installed
  DKMS source matches this checkout's driver source. Both amplifiers bind to
  ALC287, with channels 1 and 0 respectively. SOF mode is `3`, and the
  installed firmware matches the repository copy.
- No kernel API/loading incompatibility was found in these checks. The boot
  message `Could not get reset GPIO: -2 (non-fatal)` is followed by successful
  registration and binding of both amplifiers; it does not by itself mean the
  driver failed.

These observations establish module loading and component binding, not a
complete audio test. Audible playback, recording, and suspend/resume were not
tested. Recheck compatibility after future kernel updates; do not infer it
from the presence of `snd-soc-aw88399` alone.

Upstream now has [AW88399 HDA configuration options](https://github.com/torvalds/linux/blob/master/sound/hda/codecs/side-codecs/Kconfig),
but the inspected Ubuntu kernel configuration lacks both
`CONFIG_SND_HDA_SCODEC_AW88399` and `CONFIG_SND_HDA_SCODEC_AW88399_I2C`.
Upstream support therefore does not make this package redundant on the
currently installed kernel.

### Desktop audio configuration

The previous WirePlumber rule used `pci-*`, which did not match the inspected
node `alsa_output.pci-0000_80_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink`.
Consequently, its intended `api.alsa.period-size = 2048` and
`api.alsa.headroom = 8192` overrides were absent from the live node.
Both installation scripts now use
`~alsa_output[.]pci-.*-platform-skl_hda_dsp_generic[.].*`.
WirePlumber's [ALSA rules](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/alsa.html)
use regular-expression matching after `~`, so a variable PCI address needs
`.*`. Editing this checkout does not update the already installed configuration.
Applying this configuration correction does not require rebuilding the kernel
modules.

The `ucm2/` files are legacy configuration snapshots; neither installation
script deploys them. The inspected system uses the newer distribution HDA UCM
files, without the snapshots' `83F5` microphone override. Its live input route
is labelled `Stereo Microphone` and tied to the external microphone jack;
internal-microphone routing remains unverified. Do not assume that installing
this speaker driver also installs an internal-microphone fix.

## Quick Install (new installations)

For an existing 1.0.1 installation where other kernels must remain untouched,
use the current-kernel upgrade procedure below instead.

```bash
# From .deb package:
sudo dpkg -i aw88399-hda-dkms_1.0.2_all.deb
sudo reboot

# Or from source:
make
sudo ./install.sh
sudo reboot
```

The `.deb` path installs the GRUB drop-in and runs `update-grub`. The source
installer installs modules, firmware, modprobe configuration, WirePlumber
configuration, and the initramfs update, but does **not** modify GRUB. For a
source install, add `snd_intel_dspcfg.dsp_driver=3` to `/etc/default/grub` (or
create the drop-in described in [Boot Parameter](#boot-parameter)) and run
`sudo update-grub` before rebooting. When building for a non-running kernel,
pass the same release to both commands, for example:

```bash
make KVER=7.0.0-31-generic
sudo ./install.sh 7.0.0-31-generic
```

## Upgrading only the current kernel from 1.0.1 to 1.0.2

Version **1.0.2** contains the corrected WirePlumber node-matching rule and
updated compatibility documentation. The kernel driver C code and amplifier
firmware are unchanged from 1.0.1.

The release package's extracted source was built successfully for both
`7.0.0-31-generic` and `7.0.0-30-generic` (all six modules, including MODPOST).
Package contents, maintainer-script syntax, and the WirePlumber configuration
were checked. BTF debug information was skipped because `vmlinux` was not
available; the modules themselves built successfully. The 1.0.2 modules are
installed and component binding is verified on the running system; audible
playback, recording, and suspend/resume remain untested.

The installed 1.0.1 package's `prerm` removes its DKMS modules from **all**
kernels. Running `dpkg -i` on the new package would invoke that old script.
To preserve every other kernel, extract the new package without running its
maintainer scripts and install its DKMS source for `uname -r` explicitly.

Run the following from this checkout. The subshell stops on errors and removes
its temporary extraction directory automatically. It refuses to overwrite an
existing 1.0.2 source directory; if that directory already exists, inspect the
previous attempt before continuing.

```bash
(
    set -e
    aw88399_kernel="$(uname -r)"
    aw88399_stage="$(mktemp -d)"
    trap 'rm -rf -- "$aw88399_stage"' EXIT

    test ! -e /usr/src/aw88399-hda-dkms-1.0.2
    dpkg-deb --extract ./aw88399-hda-dkms_1.0.2_all.deb "$aw88399_stage"
    sudo cp -a "$aw88399_stage/usr/src/aw88399-hda-dkms-1.0.2" /usr/src/
    sudo dkms add -m aw88399-hda-dkms -v 1.0.2
    sudo dkms build -m aw88399-hda-dkms -v 1.0.2 -k "$aw88399_kernel"
    sudo dkms install -m aw88399-hda-dkms -v 1.0.2 -k "$aw88399_kernel" --force
    sudo install -m 0644 \
        "$aw88399_stage/usr/share/wireplumber/wireplumber.conf.d/50-aw88399-sof-fix.conf" \
        /usr/share/wireplumber/wireplumber.conf.d/50-aw88399-sof-fix.conf
    sudo update-initramfs -u -k "$aw88399_kernel"
)
dkms status -m aw88399-hda-dkms
```

On the inspected machine, expect **1.0.2** to be `installed` for
`7.0.0-31-generic`, with **1.0.1** still `installed` for `7.0.0-30-generic`.
The old version may also remain in the `built` state for the current kernel.
Only the current kernel's modules and initramfs are updated; the existing
firmware and GRUB settings are reused. WirePlumber configuration is shared by
the system, so its corrected buffering rule applies regardless of boot kernel.

This is a manual DKMS upgrade: the Debian package database still reports
**1.0.1**, while `dkms status` reports the actual module version for each
kernel. The new source keeps `AUTOINSTALL=yes` for future kernel installations;
this procedure does not run autoinstall on any other existing kernel.

Once installation succeeds and the expected DKMS status is confirmed, reboot
to load the current kernel's new installation and WirePlumber configuration:

```bash
sudo reboot
```

After reboot, select the internal speakers as the output device in the desktop
sound settings, then verify amplifier binding and the buffering rule:

```bash
dkms status -m aw88399-hda-dkms
journalctl -k -b --no-pager | grep -E 'AW88399 HDA side codec|Bound to HDA codec'
wpctl inspect @DEFAULT_AUDIO_SINK@ \
  | grep -E 'api.alsa.(period-size|headroom)'
```

The buffering properties should be `2048` and `8192`, respectively. These
kernel releases are specific to the inspected machine; use the actual kernel
releases on other systems.

## What This Does

These laptops have speakers wired through **Awinic AW88399** smart amplifiers connected via I2C. The HDA codec (Realtek ALC287) handles headphones and mic directly, but the speakers need the AW88399 amps to be initialized with firmware and controlled via I2C. The stock kernel checked above lacks this HDA integration, resulting in barely audible speakers without the fix.

This package builds 6 kernel modules via DKMS. The `.deb` package installs the
firmware, module-loading configuration, GRUB setting, and WirePlumber rule;
the source installer installs the firmware, module-loading configuration,
WirePlumber rule, and initramfs update, but leaves GRUB configuration to the
user.

### Modules

| Module | Purpose |
|--------|---------|
| `snd-hda-codec-alc269` | Patched Realtek codec with `ALC287_FIXUP_LENOVO_LEGION_AW88399` quirk and `SND_PCI_QUIRK` entries for the 3 subsystem IDs |
| `snd-soc-aw88399` | Patched ASoC codec — exports `aw88399_start/stop/init/request_firmware_file`, relaxes BSTS status checks, removes ACPI match to avoid binding conflict |
| `snd-hda-scodec-aw88399` | New HDA side codec bridge — component binding, playback hooks (start/stop amp on PCM open/close), runtime PM, DMI-based L/R channel swap for Legion |
| `snd-hda-scodec-aw88399-i2c` | I2C probe/remove interface for the bridge driver |
| `serial-multi-instantiate` | Patched to add `AWDZ8399` SMI node for dual I2C client creation |
| `aw88399-setup` | Workaround for `drivers/acpi/scan.c` (built into vmlinux, can't be DKMS'd). Unbinds the single ACPI I2C client, performs GPIO hardware reset, queries ACPI `_DSM` calibration data, acquires fault IRQ, then creates two named I2C clients for HDA component matching |

### Additional Files

| File | Location | Installed by | Purpose |
|------|----------|--------------|---------|
| `aw88399_acf.bin` | `/lib/firmware/` | `.deb` / `install.sh` | AW88399 DSP firmware (from Windows driver) |
| `aw88399-hda.conf` | `/etc/modprobe.d/` | `.deb` / `install.sh` | Module loading order (softdeps) |
| `99-aw88399-hda.cfg` | `/etc/default/grub.d/` | `.deb` only | Sets `snd_intel_dspcfg.dsp_driver=3` boot parameter |
| `50-aw88399-sof-fix.conf` | `/usr/share/wireplumber/wireplumber.conf.d/` | `.deb` / `install.sh` when WirePlumber is present | Sets SOF output buffering through WirePlumber ALSA rules |

## How It Works

```
Boot (with snd_intel_dspcfg.dsp_driver=3 for SOF I2S clock)
  │
  ├─ ACPI enumerates AWDZ8399 → single I2C client at 0x35
  │
  ├─ aw88399-setup.ko loads:
  │    ├─ Gets ACPI companion for SPKR device
  │    ├─ Toggles reset GPIO (from _CRS GpioIo index 0)
  │    ├─ Queries _DSM UUID 1cc539cd-... function 3 for calibration data
  │    ├─ Gets fault IRQ from _CRS GpioInt
  │    ├─ Removes existing single I2C client
  │    ├─ Creates i2c-AWDZ8399:00-aw88399-hda.0 at 0x34 (right)
  │    └─ Creates i2c-AWDZ8399:00-aw88399-hda.1 at 0x35 (left)
  │
  ├─ snd-hda-scodec-aw88399-i2c binds to each client:
  │    ├─ Initializes regmap, loads firmware (aw88399_acf.bin)
  │    ├─ DMI match → swaps L/R channels (83F5, 83F4, 83RU)
  │    └─ Registers as HDA component
  │
  ├─ snd-hda-codec-alc269 loads:
  │    ├─ Matches codec SSID 17aa:3906 → ALC287_FIXUP_LENOVO_LEGION_AW88399
  │    ├─ Chains to ALC287_FIXUP_AW88399_I2C_2 → comp_generic_fixup()
  │    ├─ Component master binds two AW88399 components
  │    └─ Installs playback hooks on PCM
  │
  └─ Audio playback:
       ├─ PCM open  → pm_runtime_get_sync
       ├─ PCM prepare → aw88399_start() on both amps
       ├─ PCM cleanup → aw88399_stop()
       └─ PCM close  → pm_runtime_put
```

## Hardware Details (from DSDT)

- **HDA Codec:** Realtek ALC287 at PCI `0000:80:1f.3`
- **Smart Amp:** Awinic AW88399 (`AWDZ8399`), 2 chips on I2C2
- **I2C Addresses:** 0x34 (right), 0x35 (left) — wired backwards on Legion, driver swaps
- **I2C Bus:** `\_SB.PC02.I2C2`, Synopsys DesignWare, 400kHz
- **Reset GPIO:** `PGPI.GNUM(0x0016040C)` — GpioIo in `_CRS` index 0
- **Interrupt GPIO:** `PGPI.GNUM(0x0016050B)` — GpioInt, ActiveLow edge (fault alerts)
- **Speaker Pins:** 0x14 (Speaker), 0x17 (Bass Speaker), 0x21 (Headphone)
- **Firmware:** `aw88399_acf.bin` — DSP config loaded via I2C at probe time

### ACPI _DSM (UUID: 1cc539cd-5a26-4288-a572-25c5744ebf1b)

| Function | Returns | Meaning |
|----------|---------|---------|
| 0 | `02 35 02 34` | 2 devices at I2C addresses 0x35, 0x34 |
| 1 | `02` | 2 amplifiers |
| 3 | `01 F4 0B 2C 10 48 0D F8 11` | Speaker calibration data (see below) |

#### Calibration Data (Function 3)

9 bytes of factory-calibrated speaker parameters, likely:

| Bytes | Value (16-bit LE) | Interpretation |
|-------|-------------------|---------------|
| 0 | `0x01` | Profile/mode |
| 1-2 | `0x0BF4` = 3060 | Speaker 0 DC resistance (r0_calib) |
| 3-4 | `0x102C` = 4140 | Speaker 0 temp-compensated Re |
| 5-6 | `0x0D48` = 3400 | Speaker 1 DC resistance (r0_calib) |
| 7-8 | `0x11F8` = 4600 | Speaker 1 temp-compensated Re |

Currently captured and passed to the HDA driver via `platform_data`. Full application to `aw_cali_desc.cali_re` pending unit verification.

## Boot Parameter

**Required:** `snd_intel_dspcfg.dsp_driver=3`

This forces SOF (Sound Open Firmware) mode for the Intel HDA controller. The AW88399 amps need an I2S clock from the Intel DSP to lock their PLL. Without SOF, the PLL check fails and the amps can't start.

The `.deb` package installs this automatically via `/etc/default/grub.d/99-aw88399-hda.cfg`.

## Differences from Nadim's Solution

The original fix by [Lyapsus](https://github.com/Lyapsus) and [Nadim Kobeissi](https://nadim.computer) at [nadimkobeissi/16iax10h-linux-sound-saga](https://github.com/nadimkobeissi/16iax10h-linux-sound-saga) is a kernel patch that requires full kernel recompilation. This DKMS package provides the same core audio functionality without rebuilding the kernel, plus additional hardware integration.

| Aspect | Nadim/Lyapsus (kernel patch) | This (DKMS) |
|--------|---------------------|-------------|
| Install | Full kernel rebuild | `dpkg -i` / `make && install.sh` |
| Kernel updates | Must re-patch & rebuild | DKMS auto-rebuilds |
| `scan.c` workaround | Direct patch (clean) | `aw88399-setup.ko` helper module |
| ACPI GPIO reset | Not implemented | Toggles reset GPIO from `_CRS` |
| ACPI `_DSM` calibration | Not implemented | Queries and passes to driver |
| ACPI IRQ (fault alerts) | Not implemented | Acquired and passed to I2C clients |

Core audio logic (HDA scodec driver, fixups, ASoC patches) is functionally identical.

### The `scan.c` problem and our workaround

The `serial-multi-instantiate` driver creates multiple I2C client devices from a single ACPI node — exactly what we need for the two AW88399 amplifiers at addresses 0x34 and 0x35 declared under a single `AWDZ8399` ACPI device. However, for SMI to claim the ACPI device, the device's HID must be listed in the `ignore_serial_bus_ids[]` array in `drivers/acpi/scan.c`. This array tells the ACPI enumerator *not* to create a single I2C client itself, leaving the device for SMI to handle instead.

The problem: `scan.c` is compiled directly into `vmlinux` — it is not a loadable module. DKMS can only build and replace kernel modules (`.ko` files), so there is no way to patch `scan.c` without rebuilding the entire kernel. This is the fundamental obstacle that makes a pure DKMS solution non-trivial.

**Nadim/Lyapsus's approach** patches `scan.c` directly, adding `{"AWDZ8399", }` to `ignore_serial_bus_ids[]`. Clean and correct, but requires a full kernel rebuild.

**Our approach** uses `aw88399-setup.ko`, a helper module that works *after* the ACPI enumerator has already created its single I2C client:

1. At boot, `scan.c` does not know about `AWDZ8399`, so it creates a single I2C client (`i2c-AWDZ8399:00`) at one of the two addresses (typically 0x35).
2. `aw88399-setup.ko` loads and finds this existing client by scanning `i2c_bus_type` for a device named `i2c-AWDZ8399:00`.
3. Before touching the client, it grabs the ACPI companion device to access hardware resources:
   - Toggles the reset GPIO (from `_CRS` GpioIo index 0) to hardware-reset both amplifiers
   - Queries `_DSM` function 3 for factory speaker calibration data (9 bytes)
   - Acquires the fault interrupt IRQ from `_CRS` GpioInt
4. It unbinds and unregisters the single ACPI-created client.
5. It creates **two** new I2C client devices with carefully crafted `dev_name` values (`AWDZ8399:00-aw88399-hda.0` at 0x34, `AWDZ8399:00-aw88399-hda.1` at 0x35) that match the HDA component binding pattern expected by the Realtek codec fixup (`comp_generic_fixup` with match string `"-%s:00-aw88399-hda.%d"`).
6. The calibration data and IRQ are passed to both clients via `platform_data`.

From this point on, `snd-hda-scodec-aw88399-i2c` binds to the two clients and the rest of the audio pipeline works identically to the kernel patch approach. The patched `serial-multi-instantiate.c` is still included in the DKMS package (with the `AWDZ8399` SMI node added) but acts as a no-op since `aw88399-setup.ko` handles device creation first. It is kept for forward-compatibility — if `AWDZ8399` is eventually added to `scan.c` upstream, SMI will take over and `aw88399-setup.ko` will gracefully find no existing client to replace.

## Troubleshooting

```bash
# Check if modules loaded and amps bound
sudo journalctl -k -b --no-pager | grep -i aw88399

# A successful setup includes these messages. A missing reset GPIO is
# non-fatal when the later client creation and binding messages are present.
#   aw88399_setup: Could not get reset GPIO: -2 (non-fatal)
#   aw88399_setup: _DSM calibration data: 01 f4 0b 2c 10 48 0d f8 11
#   aw88399-hda ...: AW88399 HDA side codec registered successfully
#   aw88399-hda ...: Bound to HDA codec, channel 0
#   aw88399-hda ...: Bound to HDA codec, channel 1
#   aw88399-hda ...: start success  # appears during playback

# Check DSP driver mode
cat /sys/module/snd_intel_dspcfg/parameters/dsp_driver
# Should be: 3

# Check loaded modules
lsmod | grep aw88

# Check sound card
aplay -l | grep ALC287

# Check the SOF speaker buffering rule after selecting internal speakers
wpctl inspect @DEFAULT_AUDIO_SINK@ \
  | grep -E 'api.alsa.(period-size|headroom)'
# Should include: period-size = 2048 and headroom = 8192
```

## Building the .deb Package

```bash
./make_deb.sh
# Output: aw88399-hda-dkms_1.0.2_all.deb
```

`make_deb.sh` accepts an optional version argument, for example
`./make_deb.sh 1.0.3`; omitting it defaults to `1.0.2`.

This is a DKMS **source** package: installation compiles modules for the target
kernel. Creating the `.deb` does not install or reload anything on the host.

## Links

- [Nadim's kernel patch solution](https://github.com/nadimkobeissi/16iax10h-linux-sound-saga)
- [AW88399QNR product page (Awinic)](https://www.awinic.com/en/productDetail/AW88399QNR)
- [AW88298 datasheet (related chip)](https://m5stack.oss-cn-shenzhen.aliyuncs.com/resource/docs/datasheet/core/K128%20CoreS3/AW88298.PDF)
- [ChromeOS DSM calibration docs](https://storage.googleapis.com/chromeos-factory-docs/sdk/pytests/dsm_calibration.html)
- [CachyOS issue #687 - AW88399 quirk](https://github.com/CachyOS/linux-cachyos/issues/687)
- [Fedora discussion - ALC3306 Legion audio](https://discussion.fedoraproject.org/t/problems-with-audio-driver-alc3306-in-a-legion-pro-7-gen-10-and-other-similar-lenovo-laptops/161992)

## Credits

This DKMS module is derived from the kernel patch solution at
[nadimkobeissi/16iax10h-linux-sound-saga](https://github.com/nadimkobeissi/16iax10h-linux-sound-saga).

- **[Lyapsus](https://github.com/Lyapsus)** — Primary author (~95% of the engineering). Wrote the HDA side-codec drivers (`aw88399_hda.c`, `aw88399_hda_i2c.c`), the ASoC codec modifications, and the Realtek ALC287 fixups.
- **[Nadim Kobeissi](https://nadim.computer)** — Initial investigation, debugging, codec cleanup, volume control fix, and documentation.
- **[Richard Garber](https://github.com/rgarber11)** — Internal microphone fix.
- **[sebetc4](https://github.com/sebetc4)** — UCM2 configuration fix for newer ALSA versions.
- **[Gianfranco Luceri](https://github.com/gluceri)** — Added 16AFR10H quirk and model support.
- **Gergo K.** — AW88399 firmware extraction from Windows driver.

Upstream kernel code used:
- `soc-codecs/aw88399.c` — Copyright (c) 2023 AWINIC Technology CO., LTD (Author: Weidong Wang)
- `serial-multi-instantiate.c` — Copyright 2018 Hans de Goede
- `realtek/alc269.c` — Linux kernel Realtek HDA codec driver

## License

GPL-2.0-only. Based on work by Lyapsus and Nadim Kobeissi
([16iax10h-linux-sound-saga](https://github.com/nadimkobeissi/16iax10h-linux-sound-saga))
and upstream Linux kernel AW88399/CS35L41 drivers.
