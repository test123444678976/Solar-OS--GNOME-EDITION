#!/usr/bin/env bash
# Fase 4 - instala o apt (e dpkg) do Debian sobre o LFS.
# O apt do host (Ubuntu) resolve as dependencias e instala em $LFS via "dpkg --root".
# Os pacotes que o LFS ja compilou entram como "instalados" falsos (files/lfs-provides.txt).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
source "$HERE/common.sh"; source "$HERE/ci/chroot.sh"
trap chroot_umount EXIT
SUITE="${DEB_SUITE:-trixie}"
MIRROR="${DEB_MIRROR:-http://deb.debian.org/debian}"
A=/tmp/solar-apt
rm -rf "$A"; mkdir -p "$A/state/lists/partial" "$A/cache/archives/partial" "$A/keys"

log "Chaves do arquivo Debian"
for k in archive-key-13 archive-key-13-security release-13; do
  curl -fsSL "https://ftp-master.debian.org/keys/$k.asc" -o "$A/keys/$k.asc" \
    && gpg --dearmor < "$A/keys/$k.asc" >> "$A/debian.gpg" || echo "aviso: chave $k nao obtida"
done
[ -f /usr/share/keyrings/debian-archive-keyring.gpg ] && cat /usr/share/keyrings/debian-archive-keyring.gpg >> "$A/debian.gpg"
[ -s "$A/debian.gpg" ] || { echo "Sem chaves Debian"; exit 1; }

log "Configuracao do apt do host (isolada)"
SL="[arch=amd64 signed-by=$A/debian.gpg]"
cat > "$A/sources.list" <<X
deb $SL $MIRROR $SUITE main
deb $SL $MIRROR ${SUITE}-updates main
deb $SL http://security.debian.org/debian-security ${SUITE}-security main
X
cat > "$A/dpkg-solar" <<X
#!/bin/sh
exec dpkg --root="$LFS" --admindir="$LFS/var/lib/dpkg" --force-unsafe-io --force-confold \\
  --path-exclude='/usr/share/man/*' --path-exclude='/usr/share/doc/*' --path-include='/usr/share/doc/*/copyright' "\$@"
X
chmod +x "$A/dpkg-solar"
cat > "$A/apt.conf" <<X
Dir::Etc::main "/dev/null";
Dir::Etc::parts "/dev/null";
Dir::Etc::sourcelist "$A/sources.list";
Dir::Etc::sourceparts "/dev/null";
Dir::Etc::preferences "/dev/null";
Dir::Etc::preferencesparts "/dev/null";
Dir::State "$A/state/";
Dir::State::status "$LFS/var/lib/dpkg/status";
Dir::Cache "$A/cache/";
Dir::Bin::dpkg "$A/dpkg-solar";
APT::Architecture "amd64";
APT::Architectures { "amd64"; };
APT::Install-Recommends "false";
APT::Get::Assume-Yes "true";
Acquire::Languages "none";
Debug::NoLocking "true";
X
export APT_CONFIG="$A/apt.conf" DEBIAN_FRONTEND=noninteractive

log "Base de dados do dpkg em $LFS"
mkdir -p "$LFS/var/lib/dpkg"/{info,updates,triggers,alternatives} "$LFS/etc/dpkg" "$LFS/var/log" "$LFS/var/cache/apt/archives"
: > "$LFS/var/lib/dpkg/status"; : > "$LFS/var/lib/dpkg/available"
: > "$LFS/var/lib/dpkg/diversions"; : > "$LFS/var/lib/dpkg/statoverride"
apt-get update

log "Pacotes falsos (fornecidos pelo LFS)"
IDX=$(ls "$A"/state/lists/*security*_Packages "$A"/state/lists/*updates*_Packages "$A"/state/lists/*main*_Packages 2>/dev/null | awk '!s[$0]++')
python3 "$HERE/files/gen-status.py" "$HERE/files/lfs-provides.txt" $IDX > "$LFS/var/lib/dpkg/status"
# libc-bin falso: reage ao trigger "ldconfig" (para os pacotes Debian ficarem visiveis)
echo "interest-noawait ldconfig" > "$LFS/var/lib/dpkg/info/libc-bin.triggers"
printf '#!/bin/sh\ncase "$1" in triggered|configure) ldconfig ;; esac\nexit 0\n' > "$LFS/var/lib/dpkg/info/libc-bin.postinst"
chmod +x "$LFS/var/lib/dpkg/info/libc-bin.postinst"
for p in $(grep '^Package:' "$LFS/var/lib/dpkg/status" | cut -d' ' -f2); do : > "$LFS/var/lib/dpkg/info/$p.list"; done

chroot_mount
log "Instalar apt (resolucao e instalacao pelo host)"
apt-get install -y apt apt-utils ca-certificates debian-archive-keyring gpgv

log "Configuracao do apt dentro do Solar OS"
mkdir -p "$LFS/etc/apt/sources.list.d" "$LFS/etc/apt/apt.conf.d" "$LFS/etc/dpkg/dpkg.cfg.d"
cat > "$LFS/etc/apt/sources.list.d/debian.sources" <<X
Types: deb
URIs: $MIRROR
Suites: $SUITE ${SUITE}-updates
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: ${SUITE}-security
Components: main non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
X
cat > "$LFS/etc/dpkg/dpkg.cfg.d/solar" <<'X'
force-unsafe-io
path-exclude=/usr/share/man/*
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
X
echo 'APT::Install-Recommends "true";' > "$LFS/etc/apt/apt.conf.d/99solar"

log "Teste: apt nativo dentro do chroot"
cp -L /etc/resolv.conf "$LFS/etc/resolv.conf.host"
rm -f "$LFS/etc/resolv.conf"; cp "$LFS/etc/resolv.conf.host" "$LFS/etc/resolv.conf"
chroot "$LFS" /usr/bin/env -i HOME=/root PATH=/usr/bin:/usr/sbin /usr/bin/apt-get update
chroot "$LFS" /usr/bin/env -i HOME=/root PATH=/usr/bin:/usr/sbin /usr/bin/apt-get check
chroot "$LFS" /usr/bin/env -i HOME=/root PATH=/usr/bin:/usr/sbin /usr/bin/apt --version
rm -f "$LFS/etc/resolv.conf.host"
log "FASE 4 CONCLUIDA - apt a funcionar"
