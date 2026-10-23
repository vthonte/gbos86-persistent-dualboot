# Complete Guide: Installing gbOS86 Dual-Boot with Full Persistence Alongside Ubuntu (Non-Destructive)

This document provides a complete, step-by-step technical guide, architectural findings, and reproducible instructions for installing **gbOS86** (Googlebook OS for x86_64 PCs) alongside an existing Linux installation (such as Ubuntu on an external USB SSD or internal drive), with **full persistence** and **zero risk to your internal SSD/Windows installation**.

Included in this repository is an automated, production-ready script: [`install_gbos86_dualboot.sh`](file:///home/neo/work/gbosx86/install_gbos86_dualboot.sh) which automates every step described here.

---

## 1. Overview & Technical Architecture

### What is gbOS86?
gbOS86 ports Google's official **Googlebook OS** (`lapis` desktop Android 15/16) to standard x86_64 PC hardware (Intel 6th-gen Skylake through modern Intel Core Ultra / Meteor Lake / Lunar Lake, and AMD Ryzen). Key architectural components include:
* **Custom Kernel (`BOOTX64.EFI`):** An Android Common Kernel 6.18 with an embedded BusyBox `stage0` initramfs.
* **Stage0 Boot Engine (`stage0_init.sh`):** Scans block devices by filesystem volume label (`GBOSSYS`, `GBOS_META`, `GBOS_DATA`), recovers journals, verifies filesystems, loops and maps Google's Android logical partitions via device-mapper (`dm-linear`), applies runtime hooks, and executes `switch_root` into Android `init`.
* **Dynamic Super Image (`super.img`):** Contains Google's logical system partitions: `system_a`, `vendor_a`, `product_a`, `system_ext_a`, `system_dlkm_a`, and `vendor_dlkm_a`.
* **Hardware Detection & Coldplug (`hwdetect.sh`):** Probes PCI/USB buses at early boot and selectively loads modules (Wi-Fi, Bluetooth, Intel/Realtek SOF audio, touchpads, panel brightness).
* **Root & Management:** Built-in KernelSU support.

---

## 2. Key Findings & Gotchas (Troubleshooting & Hardware Compatibility)

During hardware implementation and simulation on modern PC hardware (specifically Intel Core Ultra / Meteor Lake / Intel Arc Graphics), several critical architectural quirks were discovered and resolved:

### Finding 1: UEFI Secure Boot Rejection (`bad shim lock signature`)
* **Symptom:** Selecting the Googlebook OS entry from GRUB fails immediately with:
  ```text
  error: bad shim lock signature.
  error: you need to load the kernel first.
  ```
* **Root Cause:** Ubuntu's bootloader uses `shimx64.efi` signed by Microsoft's 3rd Party UEFI CA. Shim enforces verification of downstream binaries. gbOS86's `BOOTX64.EFI` is a custom-compiled Linux kernel and is not signed by Microsoft.
* **Solution:** **Secure Boot must be disabled in UEFI/BIOS settings.** (Reboot -> F2/F12 -> Security -> Secure Boot: Disabled).

### Finding 2: Kernel Panic / Fatal Exception on Intel Core Ultra (Meteor Lake / Arc Graphics)
* **Symptom:** During early boot, immediately following `[ 1] KernelSU: welcome to KernelSU...`, the system crashes:
  ```text
  Fatal exception in interrupt
  Kernel panic ! please reboot your computer
  ```
* **Root Cause:** By default, upstream `gbos.cfg` has `LOAD_I915=1`. The legacy `i915.ko` driver was designed for Intel Gen 9 through Gen 11/12 (UHD/Iris). Modern Intel Core Ultra (Meteor Lake, Arrow Lake, Lunar Lake) with Intel Arc Graphics (Xe-LPG architecture) are **incompatible** with `i915` register access and require the modern `xe.ko` kernel driver. Probing `i915` causes a null dereference or unhandled interrupt panic.
* **Solution:** In `/gbos/gbos.cfg` on the `GBOSSYS` partition:
  ```sh
  LOAD_I915=0
  XE_PARAMS="enable_psr=0 enable_fbc=0"
  EXTRA_SLEEP=2
  ```

### Finding 3: Upstream Release Module Path Discrepancy
* **Symptom:** Wi-Fi, Bluetooth, and sound modules fail to load; `hwdetect.txt` logs module loading errors.
* **Root Cause:** The upstream release archive (`gbos86-modules-6.18.21-gbos-whl-r4.tar.xz`) extracts modules to `lib/modules/6.18.21-gbos-whl+` (with a trailing `+`). However, the compiled `BOOTX64.EFI` kernel reports `uname -r` as `6.18.21-gbos-whl` (without the `+`). `modprobe` fails to locate the module directory.
* **Solution:** Ensure a symlink or copy exists on the `GBOSSYS` partition:
  ```bash
  cd /mnt/gbossys/gbos/modules/lib/modules
  sudo cp -rn 6.18.21-gbos-whl+ 6.18.21-gbos-whl
  ```

### Finding 4: Why Direct Boot from Ventoy ISO/IMG Fails
* **Symptom:** Booting a raw ISO or DD image via Ventoy drops to an emergency shell after 60 seconds with `findfs: unable to resolve 'LABEL=GBOSSYS'`.
* **Root Cause:** Ventoy stores ISOs on an exFAT filesystem. gbOS86's minimal BusyBox `stage0` initramfs lacks exFAT kernel drivers and Ventoy loopback detection scripts. It directly queries block devices for `LABEL=GBOSSYS` and `LABEL=GBOS`.
* **Solution:** Partition the target USB/disk directly with GPT partitions and standard FAT32 / ext4 filesystems with exact labels.

### Finding 5: Why the Built-In Installer (`install.sh`) Must Never Be Used on Dual-Boot Systems
* Option 2 in the default gbOS86 boot menu executes `usb/install.sh`.
* **WARNING:** `install.sh` wipes the partition table of the internal NVMe disk (`/dev/nvme0n1`), destroying Windows, Linux, and all partition tables.
* By using dedicated partitions on an external drive (e.g. Samsung Fit Plus) or existing free space, your internal SSD remains untouched and 100% safe.

---

## 3. Storage Layout for Non-Destructive Dual-Boot

Instead of wiping any disk, create 3 dedicated partitions in **unallocated space** on your target GPT drive:

| Partition | Label | Filesystem | Suggested Size | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Partition 3** | `GBOSSYS` | FAT32 (`vfat`) | 10 GB | OS root (`super.img`, firmware, modules, `gbos.cfg`, `BOOTX64.EFI`) |
| **Partition 4** | `GBOS_META` | ext4 | 64 MB | Android `/metadata` (encryption keys, update metadata) |
| **Partition 5** | `GBOS_DATA` | ext4 (`-O verity`) | 32–64+ GB | Persistent Android `/data` (Google apps, user accounts, files) |

*The existing Linux root partition (e.g. `sda1` Ubuntu) and EFI partition (e.g. `sda2` `/boot/efi`) remain completely untouched.*

---

## 4. Automated Installation Script (`install_gbos86_dualboot.sh`)

We provide an automated script that performs all prerequisite checks, partitioning, downloading, patching, config generation, EFI installation, and GRUB integration.

### Quick Run
```bash
cd ~/work/gbosx86
sudo ./install_gbos86_dualboot.sh --target /dev/sda
```

### Script Capabilities & Safety Safeguards
1. **Safety Interlock:** Automatically detects and blocks accidental targeting of internal NVMe drives (`nvme*`) unless explicitly confirmed.
2. **Space Verification:** Checks that the drive is GPT and has at least ~75 GB of unallocated free space.
3. **Hardware Detection:** Inspects host CPU and GPU:
   - If Intel Core Ultra (Meteor Lake/Arrow Lake/Lunar Lake) or Intel Arc Graphics is detected, automatically configures `LOAD_I915=0` and `XE_PARAMS="enable_psr=0 enable_fbc=0"`.
   - If AMD is detected, configures `GPU_SOFTWARE=auto` and `GPU_VULKAN=auto`.
4. **Module Path Normalization:** Automatically fixes the `6.18.21-gbos-whl+` directory mismatch.
5. **Streaming Extraction:** Downloads Google recovery partitions on-the-fly and assembles `super.img` without requiring 20+ GB of host temp space.
6. **Dual Boot Registration:** Installs `BOOTX64.EFI` to `/boot/efi/EFI/gbos/`, creates an Ubuntu GRUB menu entry in `/etc/grub.d/40_custom`, and registers an NVRAM entry via `efibootmgr` without altering the primary boot default.

---

## 5. Manual Step-by-Step Installation Guide

For users and AI assistants who prefer manual execution:

### Step 1: Install Host Prerequisites
```bash
sudo apt update
sudo apt install -y gdisk dosfstools e2fsprogs curl python3 tar xz-utils efibootmgr busybox-static qemu-system-x86
```

### Step 2: Partition Unallocated Space on Target Disk (`/dev/sda`)
```bash
# Preview changes safely
sudo sgdisk --pretend \
  -n 3:0:+10G -t 3:0700 -c 3:"GBOSSYS" \
  -n 4:0:+64M -t 4:8300 -c 4:"GBOS_META" \
  -n 5:0:+64G -t 5:8300 -c 5:"GBOS_DATA" \
  -p /dev/sda

# Apply partition creation
sudo sgdisk \
  -n 3:0:+10G -t 3:0700 -c 3:"GBOSSYS" \
  -n 4:0:+64M -t 4:8300 -c 4:"GBOS_META" \
  -n 5:0:+64G -t 5:8300 -c 5:"GBOS_DATA" \
  /dev/sda

sudo partprobe /dev/sda
```

### Step 3: Format Partitions with Mandatory Labels
```bash
# Partition 3: FAT32 GBOSSYS
sudo mkfs.vfat -F 32 -n GBOSSYS /dev/sda3

# Partition 4: ext4 GBOS_META
sudo mkfs.ext4 -F -L GBOS_META /dev/sda4

# Partition 5: ext4 GBOS_DATA with verity
sudo mkfs.ext4 -F -O verity -L GBOS_DATA /dev/sda5
```

### Step 4: Clone Repository & Download Assets
```bash
mkdir -p ~/work/gbosx86 && cd ~/work/gbosx86
git clone https://github.com/linuxkid473/gbos-x86.git repo
cd repo

mkdir -p build/dl usb/ksu kernel/out
cp /usr/bin/busybox kernel/out/busybox

# Modules (v39)
curl -fL --retry 5 -o build/dl/modules.tar.xz \
  https://github.com/linuxkid473/gbos-x86/releases/download/v39/gbos86-modules-6.18.21-gbos-whl-r4.tar.xz
tar -xJf build/dl/modules.tar.xz -C usb

# Firmware (v35)
curl -fL --retry 5 -o build/dl/firmware.tar.xz \
  https://github.com/linuxkid473/gbos-x86/releases/download/v35/gbos86-firmware-12dfe670-sof2026.09.2-r4.tar.xz
tar -xJf build/dl/firmware.tar.xz -C usb

# KernelSU (v3.3.1)
curl -fL --retry 5 -o usb/ksu/manager.apk \
  https://github.com/tiann/KernelSU/releases/download/v3.3.1/KernelSU_v3.3.1_32680-release.apk
curl -fL --retry 5 -o usb/ksu/ksud \
  https://github.com/tiann/KernelSU/releases/download/v3.3.1/ksud-x86_64-linux-android
chmod 755 usb/ksu/ksud
```

### Step 5: Extract Google Logical Partitions & Pack `super.img`
```bash
source lapis/BUILD
curl -fL --retry 5 -C - -o lapis/recovery.zip "$URL"

# Extract partitions
python3 tools/fetch_google_parts.py lapis/recovery.zip lapis/parts \
  system_a vendor_a product_a system_ext_a system_dlkm_a vendor_dlkm_a

rm -f lapis/recovery.zip

# Pack dynamic super.img
python3 usb/make_super.py build/super.img build/super.layout \
  system_a=lapis/parts/system_a.img \
  vendor_a=lapis/parts/vendor_a.img \
  product_a=lapis/parts/product_a.img \
  system_ext_a=lapis/parts/system_ext_a.img \
  system_dlkm_a=lapis/parts/system_dlkm_a.img \
  vendor_dlkm_a=lapis/parts/vendor_dlkm_a.img

rm -rf lapis/parts
```

### Step 6: Populate `GBOSSYS` Partition (`sda3`)
```bash
sudo mkdir -p /mnt/gbossys
sudo mount /dev/sda3 /mnt/gbossys

sudo mkdir -p /mnt/gbossys/EFI/BOOT /mnt/gbossys/gbos/logs
sudo cp usb/out/BOOTX64.EFI /mnt/gbossys/EFI/BOOT/BOOTX64.EFI
sudo cp kernel/out/busybox /mnt/gbossys/busybox
sudo cp build/super.img build/super.layout /mnt/gbossys/gbos/

for f in hook.sh aidiag.sh early_patch.sh hwdetect.sh install.sh apex_patch.sh gbos.cfg \
         crossystem bootdisk.img libkm_compat.so system_ext_manifest.xml soft_gk; do
  sudo cp "usb/$f" "/mnt/gbossys/gbos/$f"
done

for d in firmware patched audio installer kmod modules surface ksu; do
  sudo cp -R "usb/$d" "/mnt/gbossys/gbos/$d"
done

# Fix module directory path mismatch
if [ -d /mnt/gbossys/gbos/modules/lib/modules/6.18.21-gbos-whl+ ]; then
  sudo cp -rn /mnt/gbossys/gbos/modules/lib/modules/6.18.21-gbos-whl+ \
              /mnt/gbossys/gbos/modules/lib/modules/6.18.21-gbos-whl
fi

# Apply Hardware Tuning in gbos.cfg
sudo sed -i 's/^MODE=.*/MODE=boot/' /mnt/gbossys/gbos/gbos.cfg
sudo sed -i 's/^LOAD_I915=.*/LOAD_I915=0/' /mnt/gbossys/gbos/gbos.cfg
if ! grep -q 'XE_PARAMS=' /mnt/gbossys/gbos/gbos.cfg; then
  echo 'XE_PARAMS="enable_psr=0 enable_fbc=0"' | sudo tee -a /mnt/gbossys/gbos/gbos.cfg
fi

sync
sudo umount /mnt/gbossys
```

### Step 7: Configure EFI, GRUB, and UEFI NVRAM
```bash
# 1. Install EFI binary to EFI partition
sudo mkdir -p /boot/efi/EFI/gbos
sudo cp usb/out/BOOTX64.EFI /boot/efi/EFI/gbos/BOOTX64.EFI

# 2. Get EFI Partition UUID
EFI_UUID=$(sudo blkid -s UUID -o value /dev/sda2)

# 3. Add GRUB menu entry to /etc/grub.d/40_custom
sudo bash -c "cat << EOF >> /etc/grub.d/40_custom

menuentry \"Googlebook OS (gbOS86)\" --class android --class os {
    insmod part_gpt
    insmod fat
    insmod chain
    search --no-floppy --fs-uuid --set=root $EFI_UUID
    chainloader /EFI/gbos/BOOTX64.EFI
}
EOF"

sudo update-grub

# 4. Register UEFI NVRAM boot entry
sudo efibootmgr -c -d /dev/sda -p 2 -L "Googlebook OS (gbOS86)" -l '\EFI\gbos\BOOTX64.EFI'
```

---

## 6. Testing in Simulation via QEMU/KVM (No Host Reboot Required!)

Before rebooting physical hardware, test the bootloader, stage0, filesystem mounting, and Android init within Ubuntu using the included `run_vm.sh`:

```bash
cd ~/work/gbosx86

# Run in Graphical VM Window
./run_vm.sh

# Or run in Direct Terminal Console Mode (Full kernel & Android logs printed to shell)
./run_vm.sh --terminal
```

### What `run_vm.sh` Verifies:
1. **Unmounts guest partitions** on the host to avoid filesystem locking.
2. Boots QEMU with `-cpu host` (KVM passthrough), enabling AVX2, SHA, and exact host CPU features.
3. Maps `sda3` via an emulated xHCI USB controller (`usb-storage`) and `sda4`/`sda5` as block devices.
4. Executes `BOOTX64.EFI`.
5. Logs results to `/gbos/logs/boot-N/` on partition 3:
   - `fsck.txt`: Confirms journal recovery and clean ext4 mount of `GBOS_META` and `GBOS_DATA`.
   - `kmsg.log` & `logcat.txt`: Confirms Android `init`, `servicemanager`, `keystore2`, and userspace services are running.
   - `crash.txt`: Confirms 0 kernel panics or fatal exceptions.

---

## 7. Troubleshooting & FAQ

| Symptom | Diagnostic Log | Root Cause | Solution |
| :--- | :--- | :--- | :--- |
| `error: bad shim lock signature` | GRUB screen | Secure Boot is enabled. Custom kernel is not Microsoft CA signed. | Disable Secure Boot in BIOS/UEFI. |
| `Fatal exception in interrupt` / Kernel Panic | Screen console right after KernelSU | `LOAD_I915=1` on Intel Core Ultra (Meteor Lake / Arc Graphics). | Set `LOAD_I915=0` and `XE_PARAMS="enable_psr=0 enable_fbc=0"` in `gbos.cfg`. |
| `findfs: unable to resolve 'LABEL=GBOSSYS'` | Stage0 emergency shell | Partition volume label is missing or partition is formatted incorrectly. | Re-label partitions: `fatlabel /dev/sda3 GBOSSYS`, `e2label /dev/sda4 GBOS_META`, `e2label /dev/sda5 GBOS_DATA`. |
| Wi-Fi or Audio not working | `/gbos/logs/boot-N/hwdetect.txt` | Module path has trailing `+` mismatch (`6.18.21-gbos-whl+`). | Copy module tree to `6.18.21-gbos-whl` on `GBOSSYS`. |
| Screen freezing or flickering on modern Intel panels | `stage0-dmesg.txt` shows FIFO underrun or PSR errors | Panel Self Refresh (PSR) or Framebuffer Compression (FBC) incompatibility. | Add `enable_psr=0 enable_fbc=0` to `XE_PARAMS` in `gbos.cfg`. |

---

## 8. Complete Uninstallation / Reversion

If you ever wish to remove gbOS86 completely and reclaim disk space:
```bash
# 1. Remove GRUB entry: delete the menuentry from /etc/grub.d/40_custom
sudo nano /etc/grub.d/40_custom
sudo update-grub

# 2. Remove UEFI boot entry (find entry number with efibootmgr, e.g. Boot0003)
sudo efibootmgr -b 0003 -B

# 3. Remove EFI file
sudo rm -rf /boot/efi/EFI/gbos

# 4. Delete the 3 gbOS86 partitions using sgdisk
sudo sgdisk -d 3 -d 4 -d 5 /dev/sda
sudo partprobe /dev/sda
```
The space returns to unallocated, and Ubuntu and Windows will boot untouched.