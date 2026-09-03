#!/bin/bash
# AW88399 HDA DKMS Install Script
# Installs patched kernel modules, firmware, and UCM2 config for
# Lenovo Legion laptops with Awinic AW88399 smart amplifiers
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KVER="${1:-$(uname -r)}"
MOD_DIR="/lib/modules/$KVER"

echo "=== AW88399 HDA Sound Fix Installer ==="
echo "Kernel: $KVER"
echo ""

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

if [ ! -d "$MOD_DIR" ]; then
    echo "Kernel module directory not found: $MOD_DIR"
    exit 1
fi

MODULES=(
    "$SCRIPT_DIR/snd-hda-codec-alc269.ko"
    "$SCRIPT_DIR/snd-soc-aw88399.ko"
    "$SCRIPT_DIR/snd-hda-scodec-aw88399.ko"
    "$SCRIPT_DIR/snd-hda-scodec-aw88399-i2c.ko"
    "$SCRIPT_DIR/serial-multi-instantiate.ko"
    "$SCRIPT_DIR/aw88399-setup.ko"
)

# Validate the complete module set before changing the running system.
for ko in "${MODULES[@]}"; do
    if [ ! -f "$ko" ]; then
        echo "ERROR: $(basename "$ko") not found - run 'make' first"
        exit 1
    fi

    VERMAGIC="$(modinfo -F vermagic "$ko")"
    case "$VERMAGIC" in
        "$KVER "*) ;;
        *)
            echo "ERROR: $(basename "$ko") was not built for $KVER"
            echo "Found vermagic: $VERMAGIC"
            echo "Rebuild first with: make clean && make KVER=$KVER"
            exit 1
            ;;
    esac
done

if ! modinfo -F firmware "$SCRIPT_DIR/snd-soc-aw88399.ko" | grep -Fxq aw88399_acf.bin; then
    echo "ERROR: snd-soc-aw88399.ko does not declare aw88399_acf.bin"
    echo "Refusing to create an initramfs that cannot initialize the amplifiers"
    exit 1
fi

# Step 1: Install firmware
echo "[1/5] Installing firmware..."
if [ -f "$SCRIPT_DIR/firmware/aw88399_acf.bin" ]; then
    cp "$SCRIPT_DIR/firmware/aw88399_acf.bin" /lib/firmware/
    echo "  Installed /lib/firmware/aw88399_acf.bin"
else
    echo "  WARNING: firmware/aw88399_acf.bin not found!"
    echo "  You need to extract it from Windows drivers."
    echo "  Place it at /lib/firmware/aw88399_acf.bin"
fi

# Step 2: Install modules
echo "[2/5] Installing kernel modules..."
DEST="$MOD_DIR/updates/dkms"
mkdir -p "$DEST"

for ko in "${MODULES[@]}"; do
    cp "$ko" "$DEST/"
    echo "  Installed $(basename "$ko")"
done

depmod -a "$KVER"
echo "  Module dependencies updated"

# Step 3: Configure module loading order
echo "[3/5] Configuring module loading..."
cat > /etc/modprobe.d/aw88399-hda.conf << 'MODCONF'
# AW88399 HDA sound fix for Lenovo Legion
# Blacklist the old snd_soc_aw88399 ACPI binding (we use HDA scodec instead)
# The setup module must load before the HDA I2C driver
softdep snd-hda-scodec-aw88399-i2c pre: aw88399-setup
softdep snd-hda-codec-alc269 pre: snd-hda-scodec-aw88399-i2c
MODCONF
echo "  Created /etc/modprobe.d/aw88399-hda.conf"

# Step 4: Install WirePlumber config (SOF DSP broken pipe workaround)
echo "[4/5] Installing WirePlumber config..."
WP_DIR="/usr/share/wireplumber/wireplumber.conf.d"
if [ -d "$(dirname "$WP_DIR")" ]; then
    mkdir -p "$WP_DIR"
    cat > "$WP_DIR/50-aw88399-sof-fix.conf" << 'WPCONF'
# Fix broken pipe / XRUN issue with SOF HDA DSP speaker output
# on Lenovo Legion laptops with AW88399 smart amplifiers.
monitor.alsa.rules = [
  {
    matches = [
      {
        node.name = "~alsa_output.pci-*-platform-skl_hda_dsp_generic.*"
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
WPCONF
    echo "  Created $WP_DIR/50-aw88399-sof-fix.conf"
else
    echo "  WirePlumber not found, skipping"
fi

# Step 5: Update initramfs
echo "[5/5] Updating initramfs..."
if command -v update-initramfs &>/dev/null; then
    update-initramfs -u -k "$KVER"
elif command -v dracut &>/dev/null; then
    dracut --force --kver "$KVER"
else
    echo "  WARNING: Could not find initramfs update tool"
    echo "  Please update your initramfs manually"
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "IMPORTANT: You still need to:"
echo "  1. Ensure /lib/firmware/aw88399_acf.bin exists"
echo "  2. Reboot to load the new modules"
echo ""
echo "After reboot, check with:"
echo "  sudo dmesg | grep -i aw88399"
echo "  lsmod | grep aw88"
echo "  aplay -l"
