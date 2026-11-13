#!/usr/bin/env bash
# Fase 5 (dentro do chroot) - instala o GNOME com o apt e prepara o sistema
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LANG=C LC_ALL=C

# impede que os postinst tentem arrancar servicos dentro do chroot
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d

apt-get update
apt-get install -y --install-recommends \
  gnome-core gdm3 network-manager network-manager-gnome sudo nano ca-certificates \
  libgl1-mesa-dri libegl-mesa0 libgbm1 xwayland pipewire pipewire-pulse wireplumber \
  xdg-user-dirs xdg-desktop-portal-gnome fonts-noto-core fonts-dejavu firefox-esr \
  qemu-guest-agent spice-vdagent

rm -f /usr/sbin/policy-rc.d

# utilizador e grupos
for g in sudo audio video input users netdev plugdev render; do getent group "$g" >/dev/null || groupadd "$g"; done
id solar >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,audio,video,input,users,netdev,plugdev,render solar
echo 'solar:solar' | chpasswd

# servicos
systemctl set-default graphical.target
systemctl enable gdm3 NetworkManager systemd-resolved || true
systemctl disable systemd-networkd systemd-networkd-wait-online || true
rm -f /etc/systemd/network/10-eth-dhcp.network

# idioma e teclado
echo 'LANG=pt_PT.UTF-8' > /etc/locale.conf
mkdir -p /etc/default; echo 'LANG=pt_PT.UTF-8' > /etc/default/locale
printf 'XKBMODEL="pc105"\nXKBLAYOUT="pt"\n' > /etc/default/keyboard

# limpeza
apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
: > /etc/machine-id
echo "FASE 5 (chroot) OK"
