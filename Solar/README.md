# Solar OS - LFS 13.0 (systemd) + apt do Debian + GNOME

Sistema compilado no GitHub Actions, em 5 fases (cada job < 6 h). Cada fase guarda o resultado numa
Release (`stage-N`) e a seguinte retoma de la. A fase 5 publica a imagem final na Release `solar-os`.

| Fase | O que faz | Duracao estimada |
|------|-----------|------------------|
| 1 | cap. 4-5: cross-toolchain (binutils, gcc, headers, glibc, libstdc++) | ~1 h |
| 2 | cap. 6-7: ferramentas temporarias + chroot (perl, python, util-linux) | ~1,5 h |
| 3 | cap. 8-10: sistema final, systemd, dbus, kernel 6.18 (DRM/KMS), configuracao | ~3 h |
| 4 | **apt** + dpkg do Debian instalados sobre o LFS | ~10 min |
| 5 | **GNOME** (`gnome-core`) com o apt + imagem de disco (GPT, BIOS+UEFI) em qcow2 | ~1 h |

## Como correr
1. Cria um repositorio no GitHub e envia esta pasta (inclui `.github/`).
2. Actions -> **Solar OS (LFS)** -> Run workflow -> `stage` = 1. Quando ficar verde, corre 2, 3, 4 e 5.
3. No fim, a Release **solar-os** tem a imagem em pedacos. Junta-os e arranca:

Windows (PowerShell, com `scoop install qemu`):

    cmd /c copy /b solar-os.qcow2.part* solar-os.qcow2
    qemu-system-x86_64 -drive file=solar-os.qcow2,if=virtio -m 4G -smp 2 -device virtio-vga -display gtk -device qemu-xhci -device usb-tablet -accel whpx

Entrar: utilizador `solar`, palavra-passe `solar` (root tambem `solar`). Muda-as.
Para VirtualBox/VMware: `qemu-img convert -O vdi solar-os.qcow2 solar-os.vdi` (ou `vmdk`), ativa EFI ou BIOS e 3D desligado.

## O que e "puro" e o que vem do Debian
- Compilado do codigo-fonte pelo livro LFS: toolchain, glibc, coreutils, bash, systemd, dbus, util-linux, kernel, ...
- Do Debian (trixie) via apt: o proprio apt/dpkg e todo o GNOME. O LFS fornece os pacotes base
  (`files/lfs-provides.txt`) registados no dpkg como "instalados" para o apt nao os substituir.
- O GRUB e instalado pelo host do CI ao criar a imagem (nao e compilado no LFS).

## Se alguma fase falhar (esperado: nada disto foi testado)
Abre o log do passo vermelho no Actions e procura o primeiro erro. Pontos mais provaveis:
- Fases 1-3: um tarball/versao diferente do esperado (a lista vem do livro), flags de configure que mudaram.
- Fase 4: nomes de pacotes em `files/lfs-provides.txt` (o aviso "nao existe no indice" aparece no log),
  ou conflitos de dependencias do apt.
- Fase 5: dependencias do GNOME contra os pacotes falsos; drivers graficos (usa `virtio-vga` no QEMU).
Corrige/edita o script e volta a correr SO a fase que falhou (as anteriores ficam guardadas nas Releases).
