#!/usr/bin/env python3
"""gen-status.py <lista.txt> <Packages>... > status
Cria entradas "instaladas" falsas no estado do dpkg para os pacotes que o LFS ja fornece.
A versao copiada e a do indice Debian (o 1.o ficheiro onde o pacote aparece ganha), para que
dependencias do tipo (>= x) e (= x) fiquem satisfeitas."""
import sys

def parse(path):
    pkgs, cur, last = {}, {}, None
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if not line.strip():
            if "Package" in cur:
                pkgs.setdefault(cur["Package"], cur)
            cur, last = {}, None
        elif line[0] in " \t":
            if last:
                cur[last] += "\n" + line
        elif ":" in line:
            k, v = line.split(":", 1)
            cur[k], last = v.strip(), k
    if "Package" in cur:
        pkgs.setdefault(cur["Package"], cur)
    return pkgs

wanted = [l.strip() for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")]
index = {}
for f in sys.argv[2:]:                      # ordem = prioridade (security primeiro)
    for k, v in parse(f).items():
        index.setdefault(k, v)

out = []
for name in wanted:
    p = index.get(name)
    if not p:
        sys.stderr.write(f"AVISO: {name} nao existe no indice Debian (ignorado)\n")
        continue
    st = [f"Package: {name}", "Status: install ok installed",
          f"Priority: {p.get('Priority', 'optional')}", f"Section: {p.get('Section', 'libs')}",
          "Installed-Size: 1", "Maintainer: Solar OS <root@localhost>",
          f"Architecture: {p.get('Architecture', 'amd64')}"]
    if "Multi-Arch" in p:
        st.append(f"Multi-Arch: {p['Multi-Arch']}")
    st.append(f"Version: {p['Version']}")
    if "Provides" in p:
        st.append(f"Provides: {p['Provides']}")
    st.append("Description: Fornecido pelo Solar OS (LFS)")
    out.append("\n".join(st))
sys.stdout.write("\n\n".join(out) + "\n\n")
sys.stderr.write(f"{len(out)} pacotes falsos gerados\n")
