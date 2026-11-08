#!/usr/bin/env bash
# publish-image.sh : publica a imagem final (partida em pedacos < 2 GB) na Release "solar-os"
set -euo pipefail
OUT=/tmp/img-out
ls -lh "$OUT"
gh release view solar-os >/dev/null 2>&1 || gh release create solar-os --title "Solar OS" --notes "Imagem de disco do Solar OS (qcow2). Junta os pedacos: cat solar-os.qcow2.part* > solar-os.qcow2"
gh release upload solar-os "$OUT"/* --clobber
