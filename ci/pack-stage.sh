#!/usr/bin/env bash
# pack-stage.sh <N> : empacota $LFS (sem fontes) e publica na Release "stage-N"
set -euo pipefail
N="$1"; LFS="${LFS:-/mnt/lfs}"; OUT=/tmp/out; rm -rf "$OUT"; mkdir -p "$OUT"
sudo rm -rf "$LFS/solar"
sudo tar --zstd -cpf - -C "$LFS" --one-file-system --exclude=./sources . | split -b 1900M - "$OUT/stage$N.tar.zst.part"
ls -lh "$OUT"
gh release view "stage-$N" >/dev/null 2>&1 || gh release create "stage-$N" --title "Solar LFS fase $N" --notes "Artefacto intermedio da fase $N" --prerelease
gh release upload "stage-$N" "$OUT"/* --clobber
