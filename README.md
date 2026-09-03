# AW88399 HDA DKMS - Speaker Fix for Lenovo Legion Laptops

DKMS-based speaker driver for Lenovo Legion laptops using **Awinic AW88399** smart amplifiers. No kernel recompilation required.

## Supported Laptops

| Model | Product ID | Subsystem ID |
|-------|-----------|-------------|
| Lenovo Legion Pro 7 16IAX10H (Intel) | 83F5 | 17aa:3906 |
| Lenovo Legion Y9000P IAX10H | 83F4 | 17aa:3907 |
| Lenovo Legion Pro 7 16AFR10H (AMD) | 83RU | 17aa:3938 |

## Quick Install

```bash
# From .deb package:
sudo dpkg -i aw88399-hda-dkms_1.0.1_all.deb
sudo reboot

# Or from source:
make
sudo ./install.sh
sudo reboot
```

## What This Does

These laptops have speakers wired through **Awinic AW88399** smart amplifiers connected via I2C. The HDA codec (Realtek ALC287) handles headphones and mic directly, but the speakers need the AW88399 amps to be initialized with firmware and controlled via I2C. Linux has no upstream support for this configuration, resulting in barely audible speakers.

This package builds 6 kernel modules via DKMS and installs firmware + boot configuration:

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

| File | Location | Purpose |
|------|----------|---------|
| `aw88399_acf.bin` | `/lib/firmware/` | AW88399 DSP firmware (from Windows driver) |
| `aw88399-hda.conf` | `/etc/modprobe.d/` | Module loading order (softdeps) |
| `99-aw88399-hda.cfg` | `/etc/default/grub.d/` | Sets `snd_intel_dspcfg.dsp_driver=3` boot parameter |

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
sudo dmesg | grep -i aw88399

# Expected output:
#   aw88399_setup: Hardware reset complete via GPIO
#   aw88399_setup: _DSM calibration data: 01 f4 0b 2c 10 48 0d f8 11
#   aw88399-hda ...: AW88399 HDA side codec registered successfully
#   aw88399-hda ...: Bound to HDA codec, channel 0
#   aw88399-hda ...: Bound to HDA codec, channel 1
#   aw88399-hda ...: start success

# Check DSP driver mode
cat /sys/module/snd_intel_dspcfg/parameters/dsp_driver
# Should be: 3

# Check loaded modules
lsmod | grep aw88

# Check sound card
aplay -l | grep ALC287
```

## Building the .deb Package

```bash
./make_deb.sh 1.0
# Output: aw88399-hda-dkms_1.0_all.deb
```

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
