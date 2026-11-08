#!/usr/bin/env bash
# Fase 3 - LFS cap. 8-10: sistema final, systemd, configuracao e kernel (tudo no chroot)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
source "$HERE/common.sh"; source "$HERE/ci/chroot.sh"
chroot_stage stage3-chroot.sh
log "FASE 3 CONCLUIDA"
