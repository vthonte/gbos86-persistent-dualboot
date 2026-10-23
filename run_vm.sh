#!/bin/bash
# run_vm.sh: Test and debug gbOS86 directly inside Ubuntu using QEMU + KVM
# Zero need to reboot your laptop!

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL="$DIR/repo/usb/out/BOOTX64.EFI"

# Ensure host hasn't auto-mounted the guest partitions
sudo umount /dev/sda3 2>/dev/null || true
sudo umount /dev/sda4 2>/dev/null || true
sudo umount /dev/sda5 2>/dev/null || true

# Check if terminal mode requested
if [ "$1" = "--terminal" ] || [ "$1" = "-t" ]; then
    echo "=========================================================="
    echo " Starting gbOS86 in Terminal Console Mode"
    echo " All kernel, stage0, and Android init logs will print here."
    echo " Press Ctrl+A then X to exit QEMU."
    echo "=========================================================="
    sudo qemu-system-x86_64 \
      -enable-kvm -cpu host -m 4096 -smp 4 \
      -drive file=/dev/sda3,format=raw,if=none,id=sys -device qemu-xhci -device usb-storage,drive=sys \
      -drive file=/dev/sda4,format=raw,if=none,id=meta -device virtio-blk-pci,drive=meta \
      -drive file=/dev/sda5,format=raw,if=none,id=data -device virtio-blk-pci,drive=data \
      -kernel "$KERNEL" \
      -nographic \
      -append "console=ttyS0 earlyprintk=serial,ttyS0,115200 loglevel=8 ignore_loglevel rdinit=/init"
else
    echo "=========================================================="
    echo " Starting gbOS86 in Graphical Window Mode"
    echo " A window will open on your desktop."
    echo " Press Ctrl+Alt+G to release your mouse cursor."
    echo " To see terminal output instead, run: ./run_vm.sh --terminal"
    echo "=========================================================="
    sudo qemu-system-x86_64 \
      -enable-kvm -cpu host -m 4096 -smp 4 \
      -drive file=/dev/sda3,format=raw,if=none,id=sys -device qemu-xhci -device usb-storage,drive=sys \
      -drive file=/dev/sda4,format=raw,if=none,id=meta -device virtio-blk-pci,drive=meta \
      -drive file=/dev/sda5,format=raw,if=none,id=data -device virtio-blk-pci,drive=data \
      -kernel "$KERNEL" \
      -vga std \
      -display gtk,gl=on \
      -append "console=tty0 loglevel=8 ignore_loglevel rdinit=/init"
fi
