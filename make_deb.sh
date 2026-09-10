#!/bin/bash
# Build a .deb package for AW88399 HDA DKMS
# Usage: ./make_deb.sh [version]
set -e

PKGNAME="aw88399-hda-dkms"
VERSION="${1:-1.0.2}"
ARCH="all"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$(mktemp -d)"
PKG_DIR="$BUILD_DIR/${PKGNAME}_${VERSION}"

echo "=== Building ${PKGNAME}_${VERSION}_${ARCH}.deb ==="

# --- Package directory structure ---
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/usr/src/${PKGNAME}-${VERSION}"
mkdir -p "$PKG_DIR/lib/firmware"
mkdir -p "$PKG_DIR/etc/modprobe.d"
mkdir -p "$PKG_DIR/etc/default/grub.d"
mkdir -p "$PKG_DIR/usr/share/wireplumber/wireplumber.conf.d"

# --- Copy DKMS source (only what's needed to build) ---
DKMS_DST="$PKG_DIR/usr/src/${PKGNAME}-${VERSION}"

# Source files
cp "$SCRIPT_DIR/dkms.conf" "$DKMS_DST/"
cp "$SCRIPT_DIR/Makefile" "$DKMS_DST/"
cp "$SCRIPT_DIR/aw88399_setup.c" "$DKMS_DST/"
cp "$SCRIPT_DIR/aw88399_pdata.h" "$DKMS_DST/"
cp "$SCRIPT_DIR/serial-multi-instantiate.c" "$DKMS_DST/"

cp -r "$SCRIPT_DIR/realtek" "$DKMS_DST/"
cp -r "$SCRIPT_DIR/soc-codecs" "$DKMS_DST/"
cp -r "$SCRIPT_DIR/side-codecs" "$DKMS_DST/"
cp -r "$SCRIPT_DIR/common" "$DKMS_DST/"
cp -r "$SCRIPT_DIR/codecs" "$DKMS_DST/"
cp -r "$SCRIPT_DIR/helpers" "$DKMS_DST/"

# Remove build artifacts
find "$DKMS_DST" \( -name '*.o' -o -name '*.ko' -o -name '*.mod' \
    -o -name '*.mod.c' -o -name '*.cmd' -o -name 'modules.order' \
    -o -name 'Module.symvers' -o -name '.tmp_versions' \
    -o -name '.module-common.o' \) -exec rm -rf {} + 2>/dev/null || true

# Update dkms.conf version
sed -i "s/PACKAGE_VERSION=.*/PACKAGE_VERSION=\"${VERSION}\"/" "$DKMS_DST/dkms.conf"

# --- Firmware ---
if [ -f "$SCRIPT_DIR/firmware/aw88399_acf.bin" ]; then
    cp "$SCRIPT_DIR/firmware/aw88399_acf.bin" "$PKG_DIR/lib/firmware/"
fi

# --- modprobe config ---
cat > "$PKG_DIR/etc/modprobe.d/aw88399-hda.conf" << 'EOF'
# AW88399 HDA sound fix for Lenovo Legion
softdep snd-hda-scodec-aw88399-i2c pre: aw88399-setup
softdep snd-hda-codec-alc269 pre: snd-hda-scodec-aw88399-i2c
EOF

# --- WirePlumber config (SOF DSP broken pipe workaround) ---
cat > "$PKG_DIR/usr/share/wireplumber/wireplumber.conf.d/50-aw88399-sof-fix.conf" << 'EOF'
# Fix broken pipe / XRUN issue with SOF HDA DSP speaker output
# on Lenovo Legion laptops with AW88399 smart amplifiers.
# PipeWire's default headroom is too tight for the SOF DSP pipeline,
# causing snd_pcm_avail recovery loops and no audio output.
monitor.alsa.rules = [
  {
    matches = [
      {
        # WirePlumber uses a regular expression after '~', not a shell glob.
        node.name = "~alsa_output[.]pci-.*-platform-skl_hda_dsp_generic[.].*"
      }
    ]
    actions = {
      update-props = {
        api.alsa.period-size   = 2048
        api.alsa.headroom      = 8192
      }
    }
  }
]
EOF

# --- grub config ---
cat > "$PKG_DIR/etc/default/grub.d/99-aw88399-hda.cfg" << 'EOF'
# AW88399 requires SOF DSP driver for I2S clock
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT snd_intel_dspcfg.dsp_driver=3"
EOF

# --- Debian control ---
cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: ${PKGNAME}
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: LenovoLegionLinux <noreply@github.com>
Depends: dkms, linux-headers-generic | linux-headers-amd64
Recommends: linux-image-generic | linux-image-amd64
Section: kernel
Priority: optional
Homepage: https://github.com/nadimkobeissi/16iax10h-linux-sound-saga
Description: AW88399 smart amplifier DKMS driver for Lenovo Legion laptops
 Provides speaker support for Lenovo Legion Pro 7 Gen 10 laptops
 (16IAX10H, 16AFR10H, Y9000P) that use Awinic AW88399 smart amplifiers.
 .
 Builds and installs patched kernel modules via DKMS:
  - snd-hda-codec-alc269 (ALC287 fixup for AW88399)
  - snd-soc-aw88399 (ASoC codec with HDA exports)
  - snd-hda-scodec-aw88399 (HDA side codec bridge)
  - snd-hda-scodec-aw88399-i2c (I2C interface)
  - serial-multi-instantiate (AWDZ8399 dual I2C support)
  - aw88399-setup (ACPI workaround helper)
 .
 Also installs AW88399 firmware, sets snd_intel_dspcfg.dsp_driver=3,
 and includes a WirePlumber config to fix SOF DSP broken pipe issues.
EOF

# --- postinst ---
cat > "$PKG_DIR/DEBIAN/postinst" << 'POSTINST'
#!/bin/bash
set -e

DKMS_NAME="aw88399-hda-dkms"
DKMS_VERSION="#VERSION#"

# Register and build DKMS module
if [ -x /usr/sbin/dkms ]; then
    dkms add -m "$DKMS_NAME" -v "$DKMS_VERSION" 2>/dev/null || true
    dkms build -m "$DKMS_NAME" -v "$DKMS_VERSION" --force
    dkms install -m "$DKMS_NAME" -v "$DKMS_VERSION" --force
fi

# Update grub if available
if command -v update-grub &>/dev/null; then
    update-grub
fi

# Update initramfs for all installed kernels
if command -v update-initramfs &>/dev/null; then
    update-initramfs -u -k all
elif command -v dracut &>/dev/null; then
    dracut --force
fi

echo ""
echo "=== AW88399 HDA DKMS installed ==="
echo "Please reboot for changes to take effect."
echo ""
POSTINST
sed -i "s/#VERSION#/${VERSION}/" "$PKG_DIR/DEBIAN/postinst"
chmod 755 "$PKG_DIR/DEBIAN/postinst"

# --- prerm ---
cat > "$PKG_DIR/DEBIAN/prerm" << 'PRERM'
#!/bin/bash
set -e

DKMS_NAME="aw88399-hda-dkms"
DKMS_VERSION="#VERSION#"

if [ -x /usr/sbin/dkms ]; then
    dkms remove -m "$DKMS_NAME" -v "$DKMS_VERSION" --all 2>/dev/null || true
fi
PRERM
sed -i "s/#VERSION#/${VERSION}/" "$PKG_DIR/DEBIAN/prerm"
chmod 755 "$PKG_DIR/DEBIAN/prerm"

# --- postrm ---
cat > "$PKG_DIR/DEBIAN/postrm" << 'POSTRM'
#!/bin/bash

if [ "$1" = "purge" ] || [ "$1" = "remove" ]; then
    rm -f /lib/firmware/aw88399_acf.bin
    rm -f /etc/modprobe.d/aw88399-hda.conf
    rm -f /etc/default/grub.d/99-aw88399-hda.cfg
    rm -f /usr/share/wireplumber/wireplumber.conf.d/50-aw88399-sof-fix.conf

    if command -v update-grub &>/dev/null; then
        update-grub 2>/dev/null || true
    fi
    if command -v update-initramfs &>/dev/null; then
        update-initramfs -u -k all 2>/dev/null || true
    fi
fi
POSTRM
chmod 755 "$PKG_DIR/DEBIAN/postrm"

# --- Build .deb ---
dpkg-deb --build --root-owner-group "$PKG_DIR" 2>&1

# Move to source dir
mv "$BUILD_DIR/${PKGNAME}_${VERSION}.deb" "$SCRIPT_DIR/${PKGNAME}_${VERSION}_${ARCH}.deb"
rm -rf "$BUILD_DIR"

DEB="$SCRIPT_DIR/${PKGNAME}_${VERSION}_${ARCH}.deb"
echo ""
echo "=== Built: $(basename "$DEB") ==="
echo "Size: $(du -h "$DEB" | cut -f1)"
echo ""
echo "Install with:  sudo dpkg -i $(basename "$DEB")"
echo "Remove with:   sudo apt remove ${PKGNAME}"
