# gbOS86: Dual Boot on USB Device Alongside Full Ubuntu Installation

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: x86_64](https://img.shields.io/badge/Platform-x86__64-orange.svg)]()
[![Tested Hardware: Intel Core Ultra 5 / Arc](https://img.shields.io/badge/Tested%20Hardware-Intel%20Core%20Ultra%20/%20Arc-green.svg)]()

An automated, non-destructive installer, hardware simulation harness, and comprehensive troubleshooting guide for installing **gbOS86** ([Googlebook OS x86_64](https://gbos86.com)) alongside an existing Linux installation (such as Ubuntu on an external USB SSD) and internal Windows drive, with **full persistence** and **zero risk to your internal SSD**.

---

## 🚀 Key Features

* **100% Non-Destructive to Internal SSDs:** Built-in safety interlocks protect `/dev/nvme*` disks from accidental wiping.
* **Full Data Persistence:** Configures persistent ext4 metadata (`GBOS_META`) and data (`GBOS_DATA`, with ext4 verity) partitions so app installs, Google account logins, and settings survive reboots.
* **Modern Intel Arc / Core Ultra (Meteor Lake / Arrow Lake / Lunar Lake) Fixes:**
  * Auto-tunes `gbos.cfg` to disable legacy `i915` (`LOAD_I915=0`) and enable modern `xe` display driver parameters (`enable_psr=0 enable_fbc=0`), preventing the fatal exception/kernel panic.
* **Upstream Module Path Bug Fix:** Automatically normalizes `6.18.21-gbos-whl+` to `6.18.21-gbos-whl` so Wi-Fi, audio, and Bluetooth drivers load properly at runtime.
* **UEFI NVRAM & GRUB Dual-Boot Integration:** Seamlessly integrates into Ubuntu GRUB and UEFI NVRAM without disrupting your primary OS boot order.
* **In-OS Hardware Simulation (QEMU/KVM):** Test the entire boot sequence, stage0 initramfs, filesystem mounting, and Android init directly from your Linux desktop without physical reboots!

---

## ⚡ Installation Methods

You can install gbOS86 dual-boot using either method:

### Method 1: Integrated Upstream `build.sh` (Official & Minimal)
We integrated the dual-boot method directly into the upstream repository build script on branch [`feature/dualboot-method`](https://github.com/vthonte/gbos-x86/tree/feature/dualboot-method):
```bash
git clone -b feature/dualboot-method https://github.com/vthonte/gbos-x86.git
cd gbos-x86
# Interactive menu (select 3 for dual-boot) or direct flag:
./build.sh --dualboot --target /dev/sda
```

### Method 2: Standalone Automation Toolkit (`install_gbos86_dualboot.sh`)
For users on Ubuntu/Debian who want an automated one-command installer with safety interlocks, GRUB configuration, and instant QEMU VM testing:
```bash
# Preview operations safely (dry-run mode)
sudo ./install_gbos86_dualboot.sh --target /dev/sda --dry-run

# Run full automated installation
sudo ./install_gbos86_dualboot.sh --target /dev/sda

# Run and immediately test in QEMU hardware simulation
sudo ./install_gbos86_dualboot.sh --target /dev/sda --test-vm
```

---

## 🌿 Repository Branches

* **`feature/dualboot-method`** ([vthonte/gbos-x86](https://github.com/vthonte/gbos-x86/tree/feature/dualboot-method)): Clean, minimal dual-boot integration directly into upstream `build.sh` and `usb/install.sh`.
* **`feature/full-optimizations`** ([vthonte/gbos-x86](https://github.com/vthonte/gbos-x86/tree/feature/full-optimizations)): Full performance suite including headless User 0 RAM debloating (saving 3 GB RAM), zram swap wear elimination, and gaming/multitasking optimizations.
* **`main`** ([vthonte/gbos86-persistent-dualboot](https://github.com/vthonte/gbos86-persistent-dualboot)): Standalone host installer, QEMU simulation harness, and technical documentation.

---

## 💻 Hardware Simulation (Test Without Rebooting)

You can verify the bootloader, stage0, filesystem mounting, and Android userspace directly inside Ubuntu:

```bash
# Run graphical VM
./run_vm.sh

# Or run in direct terminal mode (view all kernel, stage0, and Android init logs live)
./run_vm.sh --terminal
```

---

## 📖 In-Depth Technical Guide & Troubleshooting

For full architecture details, gotchas, manual step-by-step instructions, and complete troubleshooting, read:
👉 **[GBOS86_DUALBOOT_GUIDE.md](GBOS86_DUALBOOT_GUIDE.md)**

### Critical Gotchas Solved:
1. **`error: bad shim lock signature`:** Custom kernel rejected by Ubuntu's Microsoft-signed shim. **Solution:** Disable Secure Boot in BIOS/UEFI.
2. **`Fatal exception in interrupt` / Kernel Panic:** Caused by legacy `i915` driver on Intel Core Ultra (Meteor Lake / Arc Graphics). **Solution:** Set `LOAD_I915=0` and `XE_PARAMS="enable_psr=0 enable_fbc=0 enable_panel_replay=0"`.
3. **Missing Drivers / `hwdetect` Failure:** Caused by trailing `+` directory mismatch in upstream module tarball. **Solution:** Normalized directory to `6.18.21-gbos-whl`.
4. **Ventoy Loop Failure:** `stage0_init.sh` has no exFAT kernel module or Ventoy hooks. **Solution:** Direct GPT partition setup with FAT32/ext4 volume labels.
5. **SetupWizard / OOBE Crash Loops:** Stuck at account/updating step without skip button. **Solution:** Multi-layer bypass with empty directory APK masking and User 10 desktop provisioning.
6. **Black Screen with Mouse Cursor:** `system_server` crashes on missing Gatekeeper HAL without Google Trusty TEE. **Solution:** Software Gatekeeper HAL (`soft_gk`) registered via clean single-line `init.rc` syntax.
7. **USB Flash Drive Stalls & High RAM Usage:** ChromeOS `mmd` allocates 24 GB zram and 8 GB swap file on slow flash storage, while headless User 0 runs duplicate apps. **Solution:** Disable `mmd` and disk swap, de-bloat User 0, and expand cached process limits for background multitasking.

---

## 📄 License
MIT License. Feel free to use, modify, and distribute to the gbOS86 and open-source Android x86 community.
