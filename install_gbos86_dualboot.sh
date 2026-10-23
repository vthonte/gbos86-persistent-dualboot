#!/usr/bin/env bash
#
# install_gbos86_dualboot.sh: Automated, Non-Destructive Persistent Dual-Boot Installer for gbOS86
#
# Designed for laptops with Intel (Core Ultra / Meteor Lake / legacy UHD) or AMD processors.
# Preserves existing Linux (Ubuntu) and Windows internal SSD installations.
#

set -euo pipefail

# --- Color formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Defaults ---
TARGET_DISK=""
EFI_PART=""
SYS_SIZE="10G"
META_SIZE="64M"
DATA_SIZE="64G"
REFORMAT=false
DRY_RUN=false
SKIP_DOWNLOAD=false
TEST_VM=false
ALLOW_INTERNAL=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/repo"

usage() {
    echo -e "${BOLD}Usage:${NC} sudo $0 --target <disk> [options]

${BOLD}Options:${NC}
  --target <disk>      Target disk (e.g. /dev/sda, /dev/sdb). REQUIRED.
  --efi-part <part>    Existing EFI system partition (default: auto-detected, e.g. /dev/sda2).
  --sys-size <size>    Size for GBOSSYS partition (default: 10G).
  --meta-size <size>   Size for GBOS_META partition (default: 64M).
  --data-size <size>   Size for GBOS_DATA partition (default: 64G).
  --reformat           Force re-formatting of existing gbOS86 partitions.
  --skip-download      Use existing files in repo directory if already built.
  --test-vm            Launch QEMU hardware simulation after setup.
  --allow-internal     Bypass safety protection for internal NVMe drives.
  --dry-run            Simulate operations without making any changes to disk.
  -h, --help           Show this help message.

${BOLD}Example:${NC}
  sudo $0 --target /dev/sda
  sudo $0 --target /dev/sda --test-vm"
    exit "${1:-1}"
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET_DISK="$2"
            shift 2
            ;;
        --efi-part)
            EFI_PART="$2"
            shift 2
            ;;
        --sys-size)
            SYS_SIZE="$2"
            shift 2
            ;;
        --meta-size)
            META_SIZE="$2"
            shift 2
            ;;
        --data-size)
            DATA_SIZE="$2"
            shift 2
            ;;
        --reformat)
            REFORMAT=true
            shift
            ;;
        --skip-download)
            SKIP_DOWNLOAD=true
            shift
            ;;
        --test-vm)
            TEST_VM=true
            shift
            ;;
        --allow-internal)
            ALLOW_INTERNAL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# --- Privilege Check ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root (use sudo).${NC}"
    exit 1
fi

# --- Check Target Disk ---
if [[ -z "$TARGET_DISK" ]]; then
    echo -e "${RED}Error: --target <disk> is required.${NC}"
    echo -e "${CYAN}Available disks on this system:${NC}"
    lsblk -d -o NAME,SIZE,MODEL,TRAN,TYPE
    echo ""
    usage
fi

if [[ ! -b "$TARGET_DISK" ]]; then
    echo -e "${RED}Error: Block device $TARGET_DISK does not exist.${NC}"
    exit 1
fi

# --- Safety Interlock for Internal NVMe Drives ---
if [[ "$TARGET_DISK" =~ nvme ]] && [ "$ALLOW_INTERNAL" = false ]; then
    echo -e "${RED}${BOLD}========================================================================${NC}"
    echo -e "${RED}${BOLD} SAFETY VIOLATION: $TARGET_DISK appears to be an internal NVMe SSD!${NC}"
    echo -e "${RED} This script is designed to preserve your internal OS (Windows / Linux).${NC}"
    echo -e "${RED} To install to an external USB/SSD (recommended), specify e.g. /dev/sda or /dev/sdb.${NC}"
    echo -e "${RED} If you REALLY intended to target NVMe, pass --allow-internal.${NC}"
    echo -e "${RED}${BOLD}========================================================================${NC}"
    exit 1
fi

echo -e "${BLUE}${BOLD}========================================================================${NC}"
echo -e "${BLUE}${BOLD}   gbOS86 Automated Non-Destructive Dual-Boot Installer               ${NC}"
echo -e "${BLUE}${BOLD}========================================================================${NC}"
echo -e "Target Disk:     ${BOLD}$TARGET_DISK${NC}"
echo -e "Partition Sizes: GBOSSYS: $SYS_SIZE | GBOS_META: $META_SIZE | GBOS_DATA: $DATA_SIZE"
echo -e "Dry Run Mode:    ${BOLD}$DRY_RUN${NC}"

# --- Check Required Tools ---
REQUIRED_CMDS=("sgdisk" "partprobe" "mkfs.vfat" "mkfs.ext4" "curl" "python3" "tar" "xz" "efibootmgr" "update-grub")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${YELLOW}Missing tool: $cmd. Installing required packages...${NC}"
        if [ "$DRY_RUN" = false ]; then
            apt-get update -qq && apt-get install -y -qq gdisk dosfstools e2fsprogs curl python3 tar xz-utils efibootmgr busybox-static
        fi
        break
    fi
done

# --- Detect EFI Partition ---
if [[ -z "$EFI_PART" ]]; then
    # Try finding mounted /boot/efi
    DETECTED_EFI=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || true)
    if [[ -n "$DETECTED_EFI" ]]; then
        EFI_PART="$DETECTED_EFI"
    else
        # Guess partition 2 on target disk
        if [[ -b "${TARGET_DISK}2" ]]; then
            EFI_PART="${TARGET_DISK}2"
        elif [[ -b "${TARGET_DISK}p2" ]]; then
            EFI_PART="${TARGET_DISK}p2"
        fi
    fi
fi

if [[ -z "$EFI_PART" || ! -b "$EFI_PART" ]]; then
    echo -e "${RED}Error: Could not identify EFI system partition. Please specify with --efi-part <part>.${NC}"
    exit 1
fi
echo -e "EFI Partition:   ${BOLD}$EFI_PART${NC}"

# --- Identify Target Partition Device Names ---
# Check if partitions with labels GBOSSYS, GBOS_META, GBOS_DATA already exist on the target disk
EXISTING_SYS=$(lsblk -rn -o NAME,LABEL "$TARGET_DISK" | awk '$2=="GBOSSYS"{print $1}' || true)
EXISTING_META=$(lsblk -rn -o NAME,LABEL "$TARGET_DISK" | awk '$2=="GBOS_META"{print $1}' || true)
EXISTING_DATA=$(lsblk -rn -o NAME,LABEL "$TARGET_DISK" | awk '$2=="GBOS_DATA"{print $1}' || true)

if [[ -n "$EXISTING_SYS" && -n "$EXISTING_META" && -n "$EXISTING_DATA" ]]; then
    ALREADY_PARTITIONED=true
    SYS_PART="/dev/$EXISTING_SYS"
    META_PART="/dev/$EXISTING_META"
    DATA_PART="/dev/$EXISTING_DATA"
    echo -e "${GREEN}Detected existing gbOS86 partitions on $TARGET_DISK:${NC}"
    echo -e "  System:   ${BOLD}$SYS_PART${NC}"
    echo -e "  Metadata: ${BOLD}$META_PART${NC}"
    echo -e "  Data:     ${BOLD}$DATA_PART${NC}"
else
    ALREADY_PARTITIONED=false
    if [[ "$TARGET_DISK" =~ [0-9]$ ]]; then
        P_PREFIX="${TARGET_DISK}p"
    else
        P_PREFIX="${TARGET_DISK}"
    fi
    SYS_PART="${P_PREFIX}3"
    META_PART="${P_PREFIX}4"
    DATA_PART="${P_PREFIX}5"
fi

# --- Verify Free Space on Target Disk ---
echo -e "\n${CYAN}[1/8] Verifying partition table and free space...${NC}"
if ! sgdisk -v "$TARGET_DISK" &>/dev/null; then
    echo -e "${RED}Error: $TARGET_DISK does not appear to have a valid GPT partition table.${NC}"
    exit 1
fi

# Check existing partitions
EXISTING_PARTS=$(lsblk -n -o NAME,SIZE,FSTYPE,LABEL "$TARGET_DISK" | tail -n +2 || true)
echo -e "Current layout of $TARGET_DISK:\n$EXISTING_PARTS"

if [ "$ALREADY_PARTITIONED" = false ]; then
    echo -e "\n${CYAN}Partition creation preview:${NC}"
    sgdisk --pretend \
        -n 3:0:+"$SYS_SIZE"  -t 3:0700 -c 3:"GBOSSYS" \
        -n 4:0:+"$META_SIZE" -t 4:8300 -c 4:"GBOS_META" \
        -n 5:0:+"$DATA_SIZE" -t 5:8300 -c 5:"GBOS_DATA" \
        -p "$TARGET_DISK"
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "\n${YELLOW}[DRY RUN] Halting before making disk changes.${NC}"
    exit 0
fi

# --- Create Partitions ---
if [ "$ALREADY_PARTITIONED" = false ]; then
    echo -e "\n${CYAN}[2/8] Creating dedicated gbOS86 partitions (3, 4, 5)...${NC}"
    sgdisk \
        -n 3:0:+"$SYS_SIZE"  -t 3:0700 -c 3:"GBOSSYS" \
        -n 4:0:+"$META_SIZE" -t 4:8300 -c 4:"GBOS_META" \
        -n 5:0:+"$DATA_SIZE" -t 5:8300 -c 5:"GBOS_DATA" \
        "$TARGET_DISK"

    partprobe "$TARGET_DISK"
    sleep 2
else
    echo -e "\n${CYAN}[2/8] Partitions already exist. Skipping partition creation.${NC}"
fi

# --- Format Partitions ---
if [ "$ALREADY_PARTITIONED" = false ] || [ "$REFORMAT" = true ]; then
    echo -e "\n${CYAN}[3/8] Formatting partitions with required filesystem labels...${NC}"
    echo "Formatting $SYS_PART as FAT32 (LABEL=GBOSSYS)..."
    mkfs.vfat -F 32 -n GBOSSYS "$SYS_PART"

    echo "Formatting $META_PART as ext4 (LABEL=GBOS_META)..."
    mkfs.ext4 -F -L GBOS_META "$META_PART"

    echo "Formatting $DATA_PART as ext4 (LABEL=GBOS_DATA, verity)..."
    mkfs.ext4 -F -O verity -L GBOS_DATA "$DATA_PART"
else
    echo -e "\n${CYAN}[3/8] Partitions are already formatted. (Pass --reformat to re-format).${NC}"
fi

# --- Clone or Prepare Repository Assets ---
echo -e "\n${CYAN}[4/8] Preparing gbOS86 components and assets...${NC}"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "Cloning gbOS-x86 repository..."
    git clone https://github.com/linuxkid473/gbos-x86.git "$REPO_DIR"
fi

mkdir -p build/dl usb/ksu kernel/out
if command -v busybox &>/dev/null; then
    cp "$(command -v busybox)" kernel/out/busybox
fi

if [ "$SKIP_DOWNLOAD" = false ] || [ ! -f "usb/out/BOOTX64.EFI" ]; then
    echo "Downloading kernel modules, firmware, and KernelSU..."
    curl -fL --retry 5 -C - -o build/dl/modules.tar.xz \
        https://github.com/linuxkid473/gbos-x86/releases/download/v39/gbos86-modules-6.18.21-gbos-whl-r4.tar.xz
    tar -xJf build/dl/modules.tar.xz -C usb

    curl -fL --retry 5 -C - -o build/dl/firmware.tar.xz \
        https://github.com/linuxkid473/gbos-x86/releases/download/v35/gbos86-firmware-12dfe670-sof2026.09.2-r4.tar.xz
    tar -xJf build/dl/firmware.tar.xz -C usb

    curl -fL --retry 5 -C - -o usb/ksu/manager.apk \
        https://github.com/tiann/KernelSU/releases/download/v3.3.1/KernelSU_v3.3.1_32680-release.apk
    curl -fL --retry 5 -C - -o usb/ksu/ksud \
        https://github.com/tiann/KernelSU/releases/download/v3.3.1/ksud-x86_64-linux-android
    chmod 755 usb/ksu/ksud
fi

# Build super.img if not already present on target or in repo
NEED_SUPER=true
TEMP_CHK="/tmp/chk_super_mnt"
mkdir -p "$TEMP_CHK"
if mount "$SYS_PART" "$TEMP_CHK" 2>/dev/null; then
    if [ -f "$TEMP_CHK/gbos/super.img" ] && [ "$REFORMAT" = false ]; then
        echo -e "${GREEN}Existing super.img found on $SYS_PART. Re-download skipped.${NC}"
        NEED_SUPER=false
    fi
    umount "$TEMP_CHK"
fi
rmdir "$TEMP_CHK" 2>/dev/null || true

if [ "$NEED_SUPER" = true ] && [ ! -f "build/super.img" ]; then
    echo "Streaming Google recovery logical partitions..."
    # shellcheck disable=SC1091
    source lapis/BUILD
    curl -fL --retry 5 -C - -o lapis/recovery.zip "$URL"
    python3 tools/fetch_google_parts.py lapis/recovery.zip lapis/parts \
        system_a vendor_a product_a system_ext_a system_dlkm_a vendor_dlkm_a
    rm -f lapis/recovery.zip

    echo "Packing dynamic super.img..."
    python3 usb/make_super.py build/super.img build/super.layout \
        system_a=lapis/parts/system_a.img \
        vendor_a=lapis/parts/vendor_a.img \
        product_a=lapis/parts/product_a.img \
        system_ext_a=lapis/parts/system_ext_a.img \
        system_dlkm_a=lapis/parts/system_dlkm_a.img \
        vendor_dlkm_a=lapis/parts/vendor_dlkm_a.img
    rm -rf lapis/parts
fi

# --- Hardware Detection & Driver Tuning ---
echo -e "\n${CYAN}[5/8] Inspecting host hardware & configuring gbos.cfg...${NC}"
CPU_INFO=$(grep -m1 "model name" /proc/cpuinfo || true)
VGA_INFO=$(lspci 2>/dev/null | grep -i 'vga\|3d\|display' || true)

echo -e "Detected CPU: ${BOLD}$CPU_INFO${NC}"
echo -e "Detected GPU: ${BOLD}$VGA_INFO${NC}"

MNT_SYS="/tmp/gbos_sys_mnt"
mkdir -p "$MNT_SYS"
mount "$SYS_PART" "$MNT_SYS"

# Copy structure to GBOSSYS
mkdir -p "$MNT_SYS/EFI/BOOT" "$MNT_SYS/gbos/logs"
cp usb/out/BOOTX64.EFI "$MNT_SYS/EFI/BOOT/BOOTX64.EFI"
cp kernel/out/busybox "$MNT_SYS/busybox"
[ -f "build/super.img" ] && cp build/super.img build/super.layout "$MNT_SYS/gbos/"

for f in hook.sh aidiag.sh early_patch.sh hwdetect.sh install.sh apex_patch.sh gbos.cfg \
         crossystem bootdisk.img libkm_compat.so system_ext_manifest.xml soft_gk; do
    [ -f "usb/$f" ] && cp "usb/$f" "$MNT_SYS/gbos/$f"
done

for d in firmware patched audio installer kmod modules surface ksu; do
    if [ -d "usb/$d" ]; then
        mkdir -p "$MNT_SYS/gbos/$d"
        cp -r --update=none "usb/$d/." "$MNT_SYS/gbos/$d/"
    fi
done

# Fix module directory path mismatch (6.18.21-gbos-whl+ vs 6.18.21-gbos-whl)
if [ -d "$MNT_SYS/gbos/modules/lib/modules/6.18.21-gbos-whl+" ] && [ ! -d "$MNT_SYS/gbos/modules/lib/modules/6.18.21-gbos-whl" ]; then
    echo "Applying upstream module directory normalization..."
    cp -r --update=none "$MNT_SYS/gbos/modules/lib/modules/6.18.21-gbos-whl+" \
           "$MNT_SYS/gbos/modules/lib/modules/6.18.21-gbos-whl"
fi

# Tune gbos.cfg for persistent booting & hardware
sed -i 's/^MODE=.*/MODE=boot/' "$MNT_SYS/gbos/gbos.cfg"

# Intel Arc / Core Ultra (Meteor Lake / Arrow Lake / Lunar Lake) check:
if echo "$CPU_INFO $VGA_INFO" | grep -Ei 'ultra|meteor|lunar|arrow|arc|battlemage|xe' >/dev/null; then
    echo -e "${YELLOW}Detected modern Intel Core Ultra / Arc GPU: Applying xe driver parameters and disabling legacy i915...${NC}"
    sed -i 's/^LOAD_I915=.*/LOAD_I915=0/' "$MNT_SYS/gbos/gbos.cfg"
    if grep -q 'XE_PARAMS=' "$MNT_SYS/gbos/gbos.cfg"; then
        sed -i 's/^XE_PARAMS=.*/XE_PARAMS="enable_psr=0 enable_fbc=0"/' "$MNT_SYS/gbos/gbos.cfg"
    else
        echo 'XE_PARAMS="enable_psr=0 enable_fbc=0"' >> "$MNT_SYS/gbos/gbos.cfg"
    fi
    sed -i 's/^EXTRA_SLEEP=.*/EXTRA_SLEEP=2/' "$MNT_SYS/gbos/gbos.cfg"
elif echo "$VGA_INFO" | grep -Ei 'amd|radeon' >/dev/null; then
    echo -e "${YELLOW}Detected AMD GPU: Configuring software Vulkan rendering...${NC}"
    sed -i 's/^LOAD_I915=.*/LOAD_I915=0/' "$MNT_SYS/gbos/gbos.cfg"
    sed -i 's/^GPU_SOFTWARE=.*/GPU_SOFTWARE=auto/' "$MNT_SYS/gbos/gbos.cfg"
    sed -i 's/^GPU_VULKAN=.*/GPU_VULKAN=auto/' "$MNT_SYS/gbos/gbos.cfg"
else
    echo "Detected standard/legacy Intel GPU: Keeping default i915 probe."
fi

sync
umount "$MNT_SYS"
rmdir "$MNT_SYS"

# --- Install EFI Bootloader ---
echo -e "\n${CYAN}[6/8] Installing gbOS86 EFI loader into EFI partition...${NC}"
MNT_EFI="/tmp/gbos_efi_mnt"
mkdir -p "$MNT_EFI"

# Check if EFI partition is currently mounted
if findmnt -n "$EFI_PART" >/dev/null; then
    EFI_MOUNT_POINT=$(findmnt -n -o TARGET "$EFI_PART")
    mkdir -p "$EFI_MOUNT_POINT/EFI/gbos"
    cp "$REPO_DIR/usb/out/BOOTX64.EFI" "$EFI_MOUNT_POINT/EFI/gbos/BOOTX64.EFI"
else
    mount "$EFI_PART" "$MNT_EFI"
    mkdir -p "$MNT_EFI/EFI/gbos"
    cp "$REPO_DIR/usb/out/BOOTX64.EFI" "$MNT_EFI/EFI/gbos/BOOTX64.EFI"
    sync
    umount "$MNT_EFI"
fi
rmdir "$MNT_EFI" 2>/dev/null || true

# --- Configure GRUB Menu Entry ---
echo -e "\n${CYAN}[7/8] Configuring GRUB dual-boot entry in /etc/grub.d/40_custom...${NC}"
EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")

if ! grep -q "Googlebook OS (gbOS86)" /etc/grub.d/40_custom 2>/dev/null; then
    cat << EOF >> /etc/grub.d/40_custom

menuentry "Googlebook OS (gbOS86)" --class android --class os {
    insmod part_gpt
    insmod fat
    insmod chain
    search --no-floppy --fs-uuid --set=root $EFI_UUID
    chainloader /EFI/gbos/BOOTX64.EFI
}
EOF
    echo "Added gbOS86 menuentry to /etc/grub.d/40_custom."
else
    echo "GRUB entry already present in /etc/grub.d/40_custom."
fi

update-grub

# --- Register UEFI NVRAM Entry ---
echo -e "\n${CYAN}[8/8] Registering UEFI NVRAM boot entry with efibootmgr...${NC}"
EFI_PART_NUM=$(echo "$EFI_PART" | grep -o '[0-9]*$')
if ! efibootmgr | grep -q "Googlebook OS (gbOS86)"; then
    efibootmgr -c -d "$TARGET_DISK" -p "$EFI_PART_NUM" -L "Googlebook OS (gbOS86)" -l '\EFI\gbos\BOOTX64.EFI'
    echo "Registered UEFI NVRAM entry: Googlebook OS (gbOS86)"
else
    echo "UEFI NVRAM entry already registered."
fi

echo -e "\n${GREEN}${BOLD}========================================================================${NC}"
echo -e "${GREEN}${BOLD} Installation Complete!                                                ${NC}"
echo -e "${GREEN}${BOLD}========================================================================${NC}"
echo -e "Your system is ready for persistent dual-booting."
echo -e "You can select ${BOLD}Googlebook OS (gbOS86)${NC} from your GRUB or F12 boot menu."
echo -e "Remember: Ensure ${BOLD}Secure Boot is DISABLED${NC} in your UEFI/BIOS firmware."

# --- Optional QEMU/KVM Test ---
if [ "$TEST_VM" = true ]; then
    echo -e "\n${CYAN}Starting QEMU/KVM Hardware Simulation test...${NC}"
    "${SCRIPT_DIR}/run_vm.sh" --terminal
fi
