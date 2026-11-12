# Solar OS (LFS) - ambiente comum a todas as fases. Fazer "source" a partir dos stages.
# Dentro do chroot o LFS fica vazio (LFS=) e os caminhos passam a ser /sources, /tools, ...
export LFS="${LFS-/mnt/lfs}"
export LFS_VER="${LFS_VER:-13.0-systemd}"
export LC_ALL=POSIX
export LFS_TGT="$(uname -m)-lfs-linux-gnu"
export PATH="$LFS/tools/bin:/usr/bin:/usr/sbin"
export CONFIG_SITE="$LFS/usr/share/config.site"
export MAKEFLAGS="-j$(nproc)"
umask 022

SRC="$LFS/sources"
WORK="$LFS/sources/build"

log() { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }

# Descarrega e verifica os fontes oficiais do livro LFS
fetch_sources() {
  mkdir -p "$SRC"; cd "$SRC"
  [ -f .fetched ] && return 0
  local b1="https://www.linuxfromscratch.org/lfs/view/$LFS_VER"
  local b2="https://www.linuxfromscratch.org/lfs/downloads/$LFS_VER"
  for b in "$b1" "$b2"; do
    for f in wget-list-systemd wget-list; do
      wget -q "$b/$f" -O wget-list && [ -s wget-list ] && break 2
    done
  done
  for b in "$b1" "$b2"; do wget -q "$b/md5sums" -O md5sums && [ -s md5sums ] && break; done
  [ -s wget-list ] && [ -s md5sums ] || { echo "Nao consegui obter wget-list/md5sums"; exit 1; }
  wget --input-file=wget-list --continue --tries=5 --waitretry=5 --directory-prefix="$SRC" || true
  md5sum -c md5sums
  touch .fetched
}

# find_src <nome> : tarball <nome>-<versao>.tar.* (sem distinguir maiusculas, sem docs)
find_src() { find "$SRC" -maxdepth 1 -iname "$1-[0-9]*.tar.*" ! -iname '*docs*' | sort | sed -n 1p; }
# pkgver <nome> : versao do tarball
pkgver() { basename "$(find_src "$1")" | sed -E 's/^.*-([0-9][^-]*)\.tar\..*$/\1/'; }
# unpack <nome> : extrai para $WORK e entra na pasta ($DIR)
unpack() {
  local t; t="$(find_src "$1")"
  [ -n "$t" ] || { echo "tarball '$1' nao encontrado em $SRC"; exit 1; }
  mkdir -p "$WORK"
  DIR="$WORK/$(tar -tf "$t" | awk -F/ 'NR==1{print $1}')"
  rm -rf "$DIR"; tar -xf "$t" -C "$WORK"
  cd "$DIR"
}
cleanup() { cd "$WORK"; rm -rf "$DIR"; }
