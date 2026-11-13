#!/usr/bin/env bash
# Fase 1 - LFS cap. 4-5: estrutura em $LFS + cross-toolchain (binutils, gcc, headers, glibc, libstdc++)
set -euo pipefail
source "$(dirname "$0")/../common.sh"

log "Estrutura de diretorios (cap. 4)"
mkdir -pv "$LFS/etc" "$LFS/var" "$LFS/usr/bin" "$LFS/usr/lib" "$LFS/usr/sbin" "$LFS/tools"
for i in bin lib sbin; do ln -sfv usr/$i "$LFS/$i"; done
mkdir -pv "$LFS/lib64"

log "Fontes oficiais LFS $LFS_VER"
fetch_sources

log "Binutils - passo 1"
unpack binutils
mkdir build && cd build
../configure --prefix="$LFS/tools" --with-sysroot="$LFS" --target="$LFS_TGT" \
  --disable-nls --enable-gprofng=no --disable-werror --enable-new-dtags --enable-default-hash-style=gnu
make && make install
cleanup

log "GCC - passo 1"
GLIBC_VER="$(pkgver glibc)"
unpack gcc
for p in mpfr gmp mpc; do tar -xf "$(ls "$SRC"/$p-[0-9]*.tar.* | head -n1)"; mv -v $p-[0-9]* $p; done
sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
mkdir build && cd build
../configure --target="$LFS_TGT" --prefix="$LFS/tools" --with-glibc-version="$GLIBC_VER" \
  --with-sysroot="$LFS" --with-newlib --without-headers --enable-default-pie --enable-default-ssp \
  --disable-nls --disable-shared --disable-multilib --disable-threads --disable-libatomic \
  --disable-libgomp --disable-libquadmath --disable-libssp --disable-libvtv --disable-libstdcxx \
  --enable-languages=c,c++
make && make install
cd ..
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  "$(dirname "$("$LFS_TGT-gcc" -print-libgcc-file-name)")/include/limits.h"
cleanup

log "Headers da API do Linux"
unpack linux
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include "$LFS/usr"
cleanup

log "Glibc"
ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-linux-x86-64.so.2"
ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
unpack glibc
patch -Np1 -i "$(ls "$SRC"/glibc-*fhs-1.patch | head -n1)"
mkdir build && cd build
echo "rootsbindir=/usr/sbin" > configparms
../configure --prefix=/usr --host="$LFS_TGT" --build="$(../scripts/config.guess)" \
  --disable-nscd libc_cv_slibdir=/usr/lib --enable-kernel=5.4
make && make DESTDIR="$LFS" install
sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"
cleanup

log "Teste do toolchain"
cd /tmp
echo 'int main(){}' | "$LFS_TGT-gcc" -xc -
readelf -l a.out | grep -q 'ld-linux-x86-64.so.2' || { echo "TOOLCHAIN COM PROBLEMAS"; exit 1; }
rm -f a.out
"$LFS"/tools/libexec/gcc/"$LFS_TGT"/*/install-tools/mkheaders || true

log "Libstdc++ (do GCC)"
GCC_VER="$(pkgver gcc)"
unpack gcc
mkdir build && cd build
../libstdc++-v3/configure --host="$LFS_TGT" --build="$(../config.guess)" --prefix=/usr \
  --disable-multilib --disable-nls --disable-libstdcxx-pch \
  --with-gxx-include-dir="/tools/$LFS_TGT/include/c++/$GCC_VER"
make && make DESTDIR="$LFS" install
rm -v "$LFS"/usr/lib/lib{stdc++,stdc++exp,stdc++fs,supc++}.la
cleanup

log "FASE 1 CONCLUIDA"
