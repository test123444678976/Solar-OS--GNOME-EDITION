#!/usr/bin/env bash
# fetch-stage.sh <N> : restaura o resultado da fase N em $LFS
set -euo pipefail
N="$1"; LFS="${LFS:-/mnt/lfs}"; IN=/tmp/in; rm -rf "$IN"; mkdir -p "$IN"
gh release download "stage-$N" -p "stage$N.tar.zst.part*" -D "$IN"
sudo mkdir -p "$LFS"
cat "$IN"/stage$N.tar.zst.part* | sudo tar --zstd -xpf - -C "$LFS"
rm -rf "$IN"
