#!/usr/bin/env bash
# Fase 5 - GNOME via apt + imagem de disco arrancavel (GPT, BIOS+UEFI) em qcow2
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
source "$HERE/common.sh"; source "$HERE/ci/chroot.sh"
trap 'chroot_umount; umount -R /tmp/solar-img/root 2>/dev/null || true; [ -n "${LOOP:-}" ] && losetup -d "$LOOP" 2>/dev/null || true' EXIT

log "GNOME dentro do chroot"
chroot_mount
rm -f "$LFS/etc/resolv.conf"; cp -L /etc/resolv.conf "$LFS/etc/resolv.conf"
chroot_run stage5-chroot.sh
rm -f "$LFS/etc/resolv.conf"; ln -s ../run/systemd/resolve/stub-resolv.conf "$LFS/etc/resolv.conf"
chroot_umount
rm -rf "$LFS/solar"

log "Imagem de disco"
USED=$(du -sm --exclude=sources "$LFS" | cut -f1)
SIZE=$(( USED + 3000 )); [ "$SIZE" -lt 10000 ] && SIZE=10000
IMG=/tmp/solar-os.img; M=/tmp/solar-img/root
rm -rf /tmp/solar-img; mkdir -p "$M"; truncate -s "${SIZE}M" "$IMG"
LOOP="$(losetup -Pf --show "$IMG")"
parted -s "$LOOP" mklabel gpt \
  mkpart bios 1MiB 3MiB set 1 bios_grub on \
  mkpart esp fat32 3MiB 259MiB set 2 esp on \
  mkpart root ext4 259MiB 100%
partprobe "$LOOP"; sleep 2
mkfs.vfat -F32 -n SOLAR-ESP "${LOOP}p2"
mkfs.ext4 -q -L SOLAR-ROOT "${LOOP}p3"
mount "${LOOP}p3" "$M"; mkdir -p "$M/boot/efi"; mount "${LOOP}p2" "$M/boot/efi"
rsync -aHAX --exclude=/sources --exclude=/boot/efi/* "$LFS"/ "$M"/
mkdir -p "$M"/{dev,proc,sys,run,tmp}; chmod 1777 "$M/tmp"

RUUID="$(blkid -s UUID -o value "${LOOP}p3")"; RPART="$(blkid -s PARTUUID -o value "${LOOP}p3")"
EUUID="$(blkid -s UUID -o value "${LOOP}p2")"
cat > "$M/etc/fstab" <<X
UUID=$RUUID  /          ext4  defaults,noatime  0 1
UUID=$EUUID  /boot/efi  vfat  umask=0077        0 2
X
KERNEL="$(basename "$(ls "$M"/boot/vmlinuz-* | head -n1)")"
mkdir -p "$M/boot/grub"
cat > "$M/boot/grub/grub.cfg" <<X
set timeout=3
set default=0
menuentry "Solar OS" {
    search --no-floppy --fs-uuid --set=root $RUUID
    linux /boot/$KERNEL root=PARTUUID=$RPART rw quiet
}
menuentry "Solar OS (modo texto)" {
    search --no-floppy --fs-uuid --set=root $RUUID
    linux /boot/$KERNEL root=PARTUUID=$RPART rw systemd.unit=multi-user.target
}
X
grub-install --target=i386-pc --boot-directory="$M/boot" "$LOOP"
grub-install --target=x86_64-efi --efi-directory="$M/boot/efi" --boot-directory="$M/boot" --removable --no-nvram
sync; umount -R "$M"; losetup -d "$LOOP"; LOOP=

log "Converter para qcow2 comprimido"
rm -rf /tmp/img-out; mkdir -p /tmp/img-out
qemu-img convert -f raw -O qcow2 -c "$IMG" /tmp/solar-os.qcow2
split -b 1900M /tmp/solar-os.qcow2 /tmp/img-out/solar-os.qcow2.part
ls -lh /tmp/img-out
log "FASE 5 CONCLUIDA - imagem pronta"
