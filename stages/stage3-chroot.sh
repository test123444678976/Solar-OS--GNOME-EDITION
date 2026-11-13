#!/usr/bin/env bash
# Fase 3 (dentro do chroot) - LFS cap. 8 (sistema final), 9 (configuracao) e 10 (kernel)
# Sem suites de testes (para caber no tempo do CI). O GRUB e instalado pelo host ao criar a imagem.
set -euo pipefail
source "$(dirname "$0")/../common.sh"

# b <pkg> [args] : configure --prefix=/usr + make + make install
b() { local p=$1; shift; unpack "$p"; [ -n "${PRE:-}" ] && eval "$PRE"; ./configure --prefix=/usr "$@"; make; make install; cleanup; }
# m <pkg> [args] : meson + ninja
m() { local p=$1; shift; unpack "$p"; [ -n "${PRE:-}" ] && eval "$PRE"; mkdir -p build; cd build
      meson setup .. --prefix=/usr --buildtype=release "$@"; ninja; ninja install; cleanup; }
# pipw <pkg> : constroi e instala um pacote Python offline
pipw() { unpack "$1"; pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
         pip3 install --no-index --no-cache-dir --find-links dist "$1"; cleanup; }

log "iana-etc"
unpack iana-etc; cp -v services protocols /etc; cleanup

log "Glibc (final)"
unpack glibc
patch -Np1 -i "$(ls "$SRC"/glibc-*fhs-1.patch | head -n1)"
mkdir build && cd build
echo "rootsbindir=/usr/sbin" > configparms
../configure --prefix=/usr --disable-werror --disable-nscd libc_cv_slibdir=/usr/lib \
  --enable-stack-protector=strong --enable-kernel=5.4
make
touch /etc/ld.so.conf
sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
make install
sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd
mkdir -pv /usr/lib/locale
localedef -i C -f UTF-8 C.UTF-8
localedef -i en_US -f UTF-8 en_US.UTF-8
localedef -i pt_PT -f UTF-8 pt_PT.UTF-8
cat > /etc/nsswitch.conf <<'X'
passwd: files systemd
group: files systemd
shadow: files systemd
hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
networks: files
protocols: files
services: files
ethers: files
rpc: files
X
# fuso horario
mkdir tz && cd tz && tar -xf "$(ls "$SRC"/tzdata*.tar.* | head -n1)"
ZI=/usr/share/zoneinfo; mkdir -pv $ZI/{posix,right}
for tz in etcetera southamerica northamerica europe africa antarctica asia australasia backward; do
  zic -L /dev/null -d $ZI "$tz"; zic -L /dev/null -d $ZI/posix "$tz"; zic -L leapseconds -d $ZI/right "$tz"
done
cp -v zone.tab zone1970.tab iso3166.tab $ZI
ln -sfv /usr/share/zoneinfo/Europe/Lisbon /etc/localtime
cat > /etc/ld.so.conf <<'X'
/usr/local/lib
/opt/lib
/lib/x86_64-linux-gnu
/usr/lib/x86_64-linux-gnu
include /etc/ld.so.conf.d/*.conf
X
mkdir -pv /etc/ld.so.conf.d
cleanup
ldconfig

log "Zlib, Bzip2, Xz, Lz4, Zstd, File"
b zlib; rm -fv /usr/lib/libz.a
unpack bzip2
patch -Np1 -i "$(ls "$SRC"/bzip2-*-install_docs-1.patch | head -n1)" || true
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
make -f Makefile-libbz2_so; make clean; make; make PREFIX=/usr install
cp -av libbz2.so.* /usr/lib
ln -sfv "$(basename "$(ls /usr/lib/libbz2.so.1.0.* | head -n1)")" /usr/lib/libbz2.so
cp -v bzip2-shared /usr/bin/bzip2
for i in /usr/bin/{bzcat,bunzip2}; do ln -sfv bzip2 $i; done
rm -fv /usr/lib/libbz2.a; cleanup
b xz --disable-static
unpack lz4; make BUILD_STATIC=no PREFIX=/usr; make BUILD_STATIC=no PREFIX=/usr install; cleanup
unpack zstd; make prefix=/usr; make prefix=/usr install; rm -fv /usr/lib/libzstd.a; cleanup
b file

log "Readline, Pcre2, M4, Bc, Flex, Pkgconf"
unpack readline
sed -i '/MV.*old/d' Makefile.in; sed -i '/{OLDSUFF}/c:' support/shlib-install
sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
./configure --prefix=/usr --disable-static --with-curses
make SHLIB_LIBS="-lncursesw"; make install; cleanup
b pcre2 --enable-unicode --enable-jit --enable-pcre2-16 --enable-pcre2-32 --enable-pcre2grep-libz \
  --enable-pcre2grep-libbz2 --enable-pcre2test-libreadline --disable-static
b m4
unpack bc; CC=gcc ./configure --prefix=/usr -G -O3 -r; make; make install; cleanup
b flex --disable-static; ln -sfv flex /usr/bin/lex
unpack pkgconf; ./configure --prefix=/usr --disable-static; make; make install
ln -sfv pkgconf /usr/bin/pkg-config; cleanup

log "Binutils (final)"
unpack binutils; mkdir build && cd build
../configure --prefix=/usr --sysconfdir=/etc --enable-ld=default --enable-plugins --enable-shared \
  --disable-werror --enable-64-bit-bfd --enable-new-dtags --enable-default-hash-style=gnu
make tooldir=/usr; make tooldir=/usr install
rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a /usr/share/doc/gprofng/
cleanup

log "Gmp, Mpfr, Mpc, Attr, Acl, Libcap, Libxcrypt"
b gmp --enable-cxx --disable-static
b mpfr --disable-static --enable-thread-safe
b mpc --disable-static
b attr --disable-static --sysconfdir=/etc
b acl --disable-static
unpack libcap; sed -i '/install -m.*STA/d' libcap/Makefile
make prefix=/usr lib=lib; make prefix=/usr lib=lib install; cleanup
b libxcrypt --enable-hashes=strong,glibc --enable-obsolete-api=no --disable-static --disable-failure-tokens

log "Shadow"
unpack shadow
sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /' {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /' {} \;
sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' -e 's:/var/spool/mail:/var/mail:' \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}' -i etc/login.defs
touch /usr/bin/passwd
./configure --sysconfdir=/etc --disable-static --with-bcrypt --with-yescrypt --without-libbsd \
  --with-group-name-max-length=32
make; make exec_prefix=/usr install; make -C man install-man || true
pwconv; grpconv
mkdir -p /etc/default; useradd -D --gid 999; sed -i '/MAIL/s/yes/no/' /etc/default/useradd
echo 'root:solar' | chpasswd
cleanup

log "GCC (final) - demora"
GV="$(pkgver gcc)"
unpack gcc
sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
mkdir build && cd build
../configure --prefix=/usr LD=ld --enable-languages=c,c++ --enable-default-pie --enable-default-ssp \
  --enable-host-pie --disable-multilib --disable-bootstrap --disable-fixincludes --with-system-zlib
make && make install
ln -svr /usr/bin/cpp /usr/lib
ln -sfv gcc.1 /usr/share/man/man1/cc.1 || true
mkdir -pv /usr/lib/bfd-plugins
ln -sfv ../../libexec/gcc/"$(gcc -dumpmachine)"/"$GV"/liblto_plugin.so /usr/lib/bfd-plugins/
mkdir -pv /usr/share/gdb/auto-load/usr/lib
mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib || true
echo 'int main(){}' > /tmp/dummy.c; cc /tmp/dummy.c -o /tmp/a.out
readelf -l /tmp/a.out | grep -q ': /lib64/ld-linux-x86-64.so.2' || { echo "GCC FINAL COM PROBLEMAS"; exit 1; }
cleanup; ldconfig

log "Ncurses (final)"
unpack ncurses
./configure --prefix=/usr --mandir=/usr/share/man --with-shared --without-debug --without-normal \
  --with-cxx-shared --enable-pc-files --with-pkg-config-libdir=/usr/lib/pkgconfig
make; make DESTDIR="$PWD/dest" install
install -vm755 dest/usr/lib/libncursesw.so.* /usr/lib
rm -v dest/usr/lib/libncursesw.so.*
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i dest/usr/include/curses.h
cp -av dest/* /
for lib in ncurses form panel menu; do
  ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so; ln -sfv ${lib}w.pc /usr/lib/pkgconfig/${lib}.pc
done
ln -sfv libncursesw.so /usr/lib/libcurses.so
cleanup

log "Sed, Psmisc, Gettext, Bison, Grep, Bash, Libtool, Gdbm, Gperf, Expat, Less"
b sed; b psmisc
b gettext --disable-static; chmod -v 0755 /usr/lib/preloadable_libintl.so || true
b bison
PRE='sed -i "s/echo/#echo/" src/egrep.sh' b grep
b bash --without-bash-malloc --with-installed-readline
b libtool; rm -fv /usr/lib/libltdl.a
b gdbm --disable-static --enable-libgdbm-compat
b gperf
b expat --disable-static
b less --sysconfdir=/etc

log "Perl (final)"
PV="$(pkgver perl)"; PM="${PV%.*}"
unpack perl
export BUILD_ZLIB=False BUILD_BZIP2=0
sh Configure -des -D prefix=/usr -D vendorprefix=/usr -D privlib=/usr/lib/perl5/$PM/core_perl \
  -D archlib=/usr/lib/perl5/$PM/core_perl -D sitelib=/usr/lib/perl5/$PM/site_perl \
  -D sitearch=/usr/lib/perl5/$PM/site_perl -D vendorlib=/usr/lib/perl5/$PM/vendor_perl \
  -D vendorarch=/usr/lib/perl5/$PM/vendor_perl -D man1dir=/usr/share/man/man1 \
  -D man3dir=/usr/share/man/man3 -D pager="/usr/bin/less -isR" -D useshrplib -D usethreads
make && make install; unset BUILD_ZLIB BUILD_BZIP2; cleanup

log "OpenSSL, Libelf, Libffi, Python"
unpack openssl
./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
make; sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile; make MANSUFFIX=ssl install; cleanup
unpack elfutils
./configure --prefix=/usr --disable-debuginfod --enable-libdebuginfod=dummy
make; make -C libelf install; install -vm644 config/libelf.pc /usr/lib/pkgconfig; rm -fv /usr/lib/libelf.a; cleanup
b libffi --disable-static --with-gcc-arch=x86-64
unpack python
./configure --prefix=/usr --enable-shared --with-system-expat
make; make install; cleanup
ldconfig
pipw flit_core; pipw packaging; pipw wheel; pipw setuptools
unpack ninja; python3 configure.py --bootstrap; install -vm755 ninja /usr/bin/; cleanup
pipw meson
pipw MarkupSafe; pipw Jinja2

log "Kmod, Coreutils, Diffutils, Gawk, Findutils, Groff, Gzip"
m kmod -D manpages=false
b coreutils --enable-no-install-program=kill,uptime
mv -v /usr/bin/chroot /usr/sbin; mkdir -pv /usr/share/man/man8
mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8 2>/dev/null || true
b diffutils
unpack gawk; sed -i 's/extras//' Makefile.in; ./configure --prefix=/usr; make; make install; cleanup
b findutils --localstatedir=/var/lib/locate
unpack groff; PAGE=A4 ./configure --prefix=/usr; make; make install; cleanup
b gzip

log "Iproute2, Kbd, Libpipeline, Make, Patch, Tar, Texinfo, Vim"
unpack iproute2
sed -i /ARPD/d Makefile; rm -fv man/man8/arpd.8
make NETNS_RUN_DIR=/run/netns; make SBINDIR=/usr/sbin install; cleanup
unpack kbd
patch -Np1 -i "$(ls "$SRC"/kbd-*-backspace-1.patch | head -n1)" || true
sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure; sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
./configure --prefix=/usr --disable-vlock; make; make install; cleanup
b libpipeline; b make; b patch
unpack tar; FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr; make; make install; cleanup
b texinfo
unpack vim; echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
./configure --prefix=/usr; make; make install; ln -sfv vim /usr/bin/vi; cleanup

log "Systemd"
unpack systemd
sed -i -e 's/GROUP="render"/GROUP="video"/' -e 's/GROUP="sgx", //' rules.d/50-udev-default.rules.in
mkdir -p build && cd build
meson setup .. --prefix=/usr --buildtype=release -D default-dnssec=no -D firstboot=false \
  -D install-tests=false -D ldconfig=false -D sysusers=false -D rpmmacrosdir=no -D homed=disabled \
  -D userdb=false -D man=disabled -D mode=release -D pamconfdir=no -D dev-kvm-mode=0660 \
  -D nobody-group=nogroup -D sysupdate=disabled -D ukify=disabled
ninja; ninja install
systemd-machine-id-setup; systemctl preset-all || true
cleanup; ldconfig

log "D-Bus, Man-db, Procps-ng, Util-linux, E2fsprogs"
m dbus --wrap-mode=nofallback; ln -sfv /etc/machine-id /var/lib/dbus
b man-db --sysconfdir=/etc --disable-setuid --enable-cache-owner=bin
b procps-ng --disable-static --disable-kill --enable-watch8bit --with-systemd
unpack util-linux
./configure --bindir=/usr/bin --libdir=/usr/lib --runstatedir=/run --sbindir=/usr/sbin \
  --disable-chfn-chsh --disable-login --disable-nologin --disable-su --disable-setpriv \
  --disable-runuser --disable-pylibmount --disable-liblastlog2 --disable-static --without-python \
  ADJTIME_PATH=/var/lib/hwclock/adjtime
make; make install; cleanup
unpack e2fsprogs; mkdir build && cd build
../configure --prefix=/usr --sysconfdir=/etc --enable-elf-shlibs --disable-libblkid --disable-libuuid \
  --disable-uuidd --disable-fsck
make; make install; rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a; cleanup
ldconfig

log "Configuracao do sistema (cap. 9)"
echo solar > /etc/hostname
cat > /etc/hosts <<'X'
127.0.0.1 localhost
127.0.1.1 solar
::1       localhost
X
mkdir -pv /etc/systemd/network
cat > /etc/systemd/network/10-eth-dhcp.network <<'X'
[Match]
Name=en* eth*
[Network]
DHCP=ipv4
X
ln -sfv ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
echo 'LANG=pt_PT.UTF-8' > /etc/locale.conf
printf 'KEYMAP=pt-latin1\n' > /etc/vconsole.conf
cat > /etc/os-release <<'X'
NAME="Solar OS"
PRETTY_NAME="Solar OS (LFS 13.0 + Debian apt)"
ID=solar
ID_LIKE=debian
VERSION_ID="1.0"
HOME_URL="https://github.com/"
X
echo "Solar OS \\r (\\l)" > /etc/issue
echo "13.0" > /etc/debian_version
cat > /etc/shells <<'X'
/bin/sh
/bin/bash
X
cat > /etc/profile <<'X'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
export LANG=pt_PT.UTF-8
[ -r /etc/bash.bashrc ] && . /etc/bash.bashrc
X
echo '[ "$PS1" ] && PS1="\u@\h:\w\\$ "' > /etc/bash.bashrc

log "Kernel Linux (cap. 10)"
unpack linux
make mrproper
make defconfig
scripts/config \
  -e DEVTMPFS -e DEVTMPFS_MOUNT -e TMPFS -e TMPFS_POSIX_ACL -e TMPFS_XATTR -e CGROUPS -e MEMCG \
  -e FHANDLE -e AUTOFS_FS -e SECCOMP -e SECCOMP_FILTER -e USER_NS -e INOTIFY_USER -e SIGNALFD \
  -e TIMERFD -e EPOLL -e UNIX -e DMIID -e PSI -d UEVENT_HELPER -d SYSFS_DEPRECATED -d DEBUG_INFO_BTF \
  -e EXT4_FS -e VFAT_FS -e FAT_FS -e NLS_CODEPAGE_437 -e NLS_ISO8859_1 -e EFI -e EFI_STUB \
  -e SATA_AHCI -e ATA_PIIX -e BLK_DEV_NVME -e SCSI -e BLK_DEV_SD -e VIRTIO_PCI -e VIRTIO_BLK \
  -e VIRTIO_NET -e VIRTIO_INPUT -e E1000 -e E1000E -e R8169 -e USB_SUPPORT -e USB -e USB_XHCI_HCD \
  -e USB_XHCI_PCI -e USB_EHCI_HCD -e USB_EHCI_PCI -e USB_STORAGE -e HID_GENERIC -e USB_HID \
  -e INPUT_EVDEV -e INPUT_MOUSEDEV -e DRM -e DRM_FBDEV_EMULATION -e DRM_SIMPLEDRM -e DRM_VIRTIO_GPU \
  -e DRM_BOCHS -e DRM_QXL -e DRM_VMWGFX -m DRM_I915 -m DRM_AMDGPU -m DRM_NOUVEAU -m DRM_RADEON \
  -e FB -e FB_EFI -e FRAMEBUFFER_CONSOLE -e VT -e VT_CONSOLE -e SOUND -e SND -e SND_HDA_INTEL \
  -e SND_HDA_CODEC_REALTEK -e SND_HDA_CODEC_HDMI -e SND_INTEL8X0 -e SND_USB_AUDIO \
  -e BT -e CFG80211 -e MAC80211 -e RFKILL
make olddefconfig
make
KV="$(make -s kernelrelease)"
make INSTALL_MOD_STRIP=1 modules_install
cp -iv arch/x86/boot/bzImage "/boot/vmlinuz-$KV"
cp -iv System.map "/boot/System.map-$KV"
cp -iv .config "/boot/config-$KV"
cleanup

log "Limpeza final"
rm -rf /tmp/* /usr/share/info/* /usr/share/doc/*
find /usr/lib /usr/libexec -name \*.la -delete
find /usr -depth -name "$(uname -m)-lfs-linux-gnu*" -exec rm -rf {} + 2>/dev/null || true
: > /etc/machine-id
log "FASE 3 (chroot) OK - kernel $KV"
