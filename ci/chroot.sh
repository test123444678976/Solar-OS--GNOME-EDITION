# Funcoes de chroot (fazer "source" depois de common.sh). Corre como root.
chroot_mount() {
  mkdir -p "$LFS/dev" "$LFS/proc" "$LFS/sys" "$LFS/run"
  mountpoint -q "$LFS/dev"     || mount --bind /dev "$LFS/dev"
  mountpoint -q "$LFS/dev/pts" || mount -t devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
  mountpoint -q "$LFS/proc"    || mount -t proc proc "$LFS/proc"
  mountpoint -q "$LFS/sys"     || mount -t sysfs sysfs "$LFS/sys"
  mountpoint -q "$LFS/run"     || mount -t tmpfs tmpfs "$LFS/run"
  if [ -h "$LFS/dev/shm" ]; then install -d -m 1777 "$LFS$(realpath /dev/shm)"
  else mountpoint -q "$LFS/dev/shm" || mount -t tmpfs -o nosuid,nodev tmpfs "$LFS/dev/shm"; fi
}
chroot_umount() {
  cd /
  for m in dev/shm dev/pts dev run proc sys; do umount -lf "$LFS/$m" 2>/dev/null || true; done
}
# chroot_run <script em stages/> : copia o projeto para $LFS/solar e corre o script la dentro
chroot_run() {
  local here; here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  rm -rf "$LFS/solar"; mkdir -p "$LFS/solar"
  cp -r "$here/common.sh" "$here/stages" "$here/files" "$LFS/solar/"
  chroot "$LFS" /usr/bin/env -i HOME=/root TERM=xterm LFS= LFS_VER="$LFS_VER" \
    PATH=/usr/bin:/usr/sbin /bin/bash "/solar/stages/$1"
}
# chroot_stage <script> : fontes + mounts + chroot + limpeza
chroot_stage() { trap chroot_umount EXIT; fetch_sources; chroot_mount; chroot_run "$1"; }
