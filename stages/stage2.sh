#!/usr/bin/env bash
# Fase 2 - LFS cap. 6 (ferramentas temporarias, cross-compiladas) + cap. 7 (chroot)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
source "$HERE/common.sh"; source "$HERE/ci/chroot.sh"
trap chroot_umount EXIT
fetch_sources

guess() { sh "$(find . -maxdepth 2 -name config.guess | sed -n 1p)"; }
# cross <pkg> [args...] : configure/make/install cruzado para $LFS. PRE="cmd" corre apos extrair.
cross() {
  local p=$1; shift; unpack "$p"
  [ -n "${PRE:-}" ] && eval "$PRE"
  ./configure --prefix=/usr --host="$LFS_TGT" --build="$(guess)" "$@"
  make && make DESTDIR="$LFS" install
  cleanup
}

log "M4";        cross m4
log "Ncurses"
unpack ncurses
mkdir build; ( cd build; ../configure AWK=gawk; make -C include; make -C progs tic )
./configure --prefix=/usr --host="$LFS_TGT" --build="$(./config.guess)" --mandir=/usr/share/man \
  --with-manpage-format=normal --with-shared --without-normal --with-cxx-shared --without-debug \
  --without-ada --disable-stripping AWK=gawk
make && make DESTDIR="$LFS" TIC_PATH="$PWD/build/progs/tic" install
ln -sfv libncursesw.so "$LFS/usr/lib/libncurses.so"
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$LFS/usr/include/curses.h"
cleanup

log "Bash";      cross bash --without-bash-malloc; ln -sfv bash "$LFS/bin/sh"
log "Coreutils"; cross coreutils --enable-install-program=hostname --enable-no-install-program=kill,uptime
mv -v "$LFS/usr/bin/chroot" "$LFS/usr/sbin"
mkdir -pv "$LFS/usr/share/man/man8"
mv -v "$LFS/usr/share/man/man1/chroot.1" "$LFS/usr/share/man/man8/chroot.8"
sed -i 's/"1"/"8"/' "$LFS/usr/share/man/man8/chroot.8"
log "Diffutils"; cross diffutils

log "File"
unpack file
mkdir build; ( cd build; ../configure --disable-bzlib --disable-libseccomp --disable-xzlib --disable-zlib; make )
./configure --prefix=/usr --host="$LFS_TGT" --build="$(./config.guess)"
make FILE_COMPILE="$PWD/build/src/file" && make DESTDIR="$LFS" install
rm -fv "$LFS/usr/lib/libmagic.la"
cleanup

log "Findutils"; cross findutils --localstatedir=/var/lib/locate
log "Gawk";      PRE="sed -i 's/extras//' Makefile.in" cross gawk
log "Grep";      cross grep
log "Gzip";      cross gzip
log "Make";      cross make --without-guile
log "Patch";     cross patch
log "Sed";       cross sed
log "Tar";       cross tar
log "Xz";        cross xz --disable-static; rm -fv "$LFS/usr/lib/liblzma.la"

log "Binutils - passo 2"
unpack binutils
# corrige libtool (linha 6009 no livro; procura-se de forma tolerante)
if sed -n '6009p' ltmain.sh | grep -q '\$add_dir'; then sed -i '6009s/$add_dir//' ltmain.sh
else echo "AVISO: ltmain.sh mudou, correcao do libtool nao aplicada"; fi
mkdir build && cd build
../configure --prefix=/usr --build="$(../config.guess)" --host="$LFS_TGT" --disable-nls --enable-shared \
  --enable-gprofng=no --disable-werror --enable-64-bit-bfd --enable-new-dtags --enable-default-hash-style=gnu
make && make DESTDIR="$LFS" install
rm -fv "$LFS"/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
cleanup

log "GCC - passo 2"
unpack gcc
for p in mpfr gmp mpc; do tar -xf "$(find_src $p)"; mv -v $p-[0-9]* $p; done
sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
sed '/thread_header =/s/@.*@/gthr-posix.h/' -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
mkdir build && cd build
../configure --build="$(../config.guess)" --host="$LFS_TGT" --target="$LFS_TGT" \
  LDFLAGS_FOR_TARGET="-L$PWD/$LFS_TGT/libgcc" --prefix=/usr --with-build-sysroot="$LFS" \
  --enable-default-pie --enable-default-ssp --disable-nls --disable-multilib --disable-libatomic \
  --disable-libgomp --disable-libquadmath --disable-libsanitizer --disable-libssp --disable-libvtv \
  --enable-languages=c,c++
make && make DESTDIR="$LFS" install
ln -sfv gcc "$LFS/usr/bin/cc"
cleanup

log "Cap. 7: entrar em chroot"
chroot_mount
chroot_run stage2-chroot.sh
log "FASE 2 CONCLUIDA"
