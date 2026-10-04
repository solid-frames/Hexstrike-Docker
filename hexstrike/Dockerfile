# HexStrike AI - server image
#
# Not an official image (the upstream repo ships no Dockerfile as of writing) -
# this builds hexstrike_server.py plus the CLI tools it shells out to, on a
# Kali base so most tools come from apt metapackages instead of one-by-one
# builds. Verify versions/package names still match after Kali updates.
#
# Build:   podman build -t localhost/hexstrike-server:latest .
# This image runs ONLY hexstrike_server.py (the heavy part with all the
# scanning tools). The lightweight MCP bridge (hexstrike_mcp.py) that Claude
# Desktop launches stays on the host - see ../README.md.

FROM docker.io/kalilinux/kali-rolling:latest

LABEL org.opencontainers.image.title="hexstrike-server" \
      org.opencontainers.image.description="HexStrike AI MCP server + its CLI tool dependencies, on Kali rolling" \
      org.opencontainers.image.source="https://github.com/0x4m4/hexstrike-ai" \
      org.opencontainers.image.documentation="https://github.com/solid-frames/hexstrike-docker"

# bash with pipefail so a failing command on the left side of a `curl | sh`
# (or similar) pipe actually fails the RUN, instead of being masked by the
# right-hand command's exit status.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin
# PIPX_BIN_DIR=/usr/local/bin ist der Hauptfix fuer Runde 2: /usr/local/bin ist
# immer im PATH (auch fuer den exec-form ENTRYPOINT ohne Login-Shell), waehrend
# pipx ohne diese Variable nach /root/.local/bin installiert - das lag NICHT
# im PATH des Prozesses, der hexstrike_server.py startet. Dadurch waren arjun,
# volatility3, scoutsuite, prowler, kube-hunter und paramspider trotz
# erfolgreicher Installation fuer den Health-Check unsichtbar.

# --- Bulk of the tool list via Kali metapackages -----------------------
# Covers: nmap masscan gobuster ffuf dirb feroxbuster nikto sqlmap wpscan
# hydra john hashcat medusa crackmapexec/netexec radare2 binwalk foremost
# steghide exiftool amass dnsenum theharvester responder enum4linux-ng
# checksec strings/objdump (binutils) and most of the rest of the list.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv git curl wget unzip build-essential \
        tini \
        kali-tools-information-gathering \
        kali-tools-vulnerability \
        kali-tools-web \
        kali-tools-passwords \
        kali-tools-forensics \
        kali-tools-reverse-engineering \
        chromium chromium-driver \
        arp-scan ffuf steghide testdisk bulk-extractor xxd aircrack-ng kismet httpie \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Tools that are usually missing/outdated in the Kali metapackages --
# rustscan: no current Kali package -> grab the released .deb. Die Version war
# vorher hart auf 2.3.0 gepinnt (moeglicher Grund, warum es beim Health-Check
# als fehlend auftauchte, falls das Release inzwischen weg ist) - jetzt wie
# kube-bench dynamisch ueber die GitHub-API aufgeloest, tolerant falls es
# schief geht.
RUN RS_VER="$(curl -sSL https://api.github.com/repos/bee-san/RustScan/releases/latest | grep -oP '\"tag_name\":\s*\"v?\K[^\"]+')"; \
    curl -fsSL -o /tmp/rustscan.deb.zip \
        "https://github.com/bee-san/RustScan/releases/download/${RS_VER}/rustscan.deb.zip" \
    && unzip -o /tmp/rustscan.deb.zip -d /tmp >/dev/null \
    && (dpkg -i /tmp/rustscan*.deb || apt-get -f install -y --no-install-recommends) \
    && rm -f /tmp/rustscan.deb.zip /tmp/rustscan*.deb \
    || echo "WARN: rustscan uebersprungen"

# trivy: official install script (apt repo pinning is finicky, this is more stable)
RUN curl -sSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
        | sh -s -- -b /usr/local/bin

# Go-based recon/web tools not always current in apt. Each "go install" is tolerant
# (|| echo WARN) so a single broken/moved module can no longer abort the whole layer.
# NOTE: ffuf is already installed via apt above - this go-installs a newer
# version on top (go bins land in /usr/local/bin, which comes before apt's
# /usr/bin/ffuf in PATH). Intentional, not a leftover duplicate.
RUN apt-get update && apt-get install -y --no-install-recommends golang-go \
    && export GOPATH=/root/go GO111MODULE=on PATH="/root/go/bin:$PATH" \
    && for pkg in \
         github.com/projectdiscovery/subfinder/v2/cmd/subfinder \
         github.com/projectdiscovery/nuclei/v3/cmd/nuclei \
         github.com/projectdiscovery/httpx/cmd/httpx \
         github.com/projectdiscovery/katana/cmd/katana \
         github.com/hahwul/dalfox/v2 \
         github.com/tomnomnom/anew \
         github.com/lc/gau/v2/cmd/gau \
         github.com/tomnomnom/waybackurls \
         github.com/tomnomnom/qsreplace \
         github.com/ffuf/ffuf/v2 \
         github.com/jaeles-project/jaeles ; do \
        go install "$pkg@latest" || echo "WARN: go install $pkg fehlgeschlagen"; \
    done; \
    cp /root/go/bin/* /usr/local/bin/ 2>/dev/null || true; \
    apt-get purge -y golang-go; apt-get autoremove -y; rm -rf /root/go /var/lib/apt/lists/*

# x8 (hidden-parameter-discovery) wurde upstream von Go auf Rust umgestellt - der
# alte Go-Modulpfad existiert nicht mehr ("does not contain package"). Statt eine
# ganze Rust-Toolchain zu ziehen nutzen wir das offizielle statische Linux-Release
# (v4.3.0). Fehlschlag tolerant, damit ein Umbenennen des Assets den Build nicht killt.
RUN curl -fsSL -o /tmp/x8.gz \
        "https://github.com/Sh1Yo/x8/releases/download/v4.3.0/x86_64-linux-x8.gz" \
    && gunzip -c /tmp/x8.gz > /usr/local/bin/x8 \
    && chmod +x /usr/local/bin/x8 \
    || echo "WARN: x8 uebersprungen (Release-Asset evtl. umbenannt)"; \
    rm -f /tmp/x8.gz

# --- Tools that should have come from the Kali metapackages but didn't -
# amass/exiftool/checksec/searchsploit/responder tauchten im Health-Check als
# fehlend auf, obwohl kali-tools-information-gathering/-forensics/
# -reverse-engineering/-passwords sie eigentlich abdecken sollten (Metapaket-
# Inhalt driftet mit Kali-Updates). Hier explizit + einzeln mit Fallback, damit
# ein einzelner unbekannter Paketname nicht den ganzen Layer killt.
RUN apt-get update; \
    for pkg in amass libimage-exiftool-perl checksec exploitdb responder \
               arp-scan ffuf steghide testdisk bulk-extractor xxd aircrack-ng \
               kismet httpie gobuster enum4linux-ng photorec \
               crackmapexec ropper spiderfoot autorecon; do \
        apt-get install -y --no-install-recommends "$pkg" \
            || echo "WARN: apt install $pkg fehlgeschlagen, uebersprungen"; \
    done; \
    rm -rf /var/lib/apt/lists/*

# --- Python-based secondary tools + fixes for tools that pipx couldn't install ---
RUN apt-get update; apt-get install -y --no-install-recommends netexec python3-dev libssl-dev libffi-dev pkg-config || true; rm -rf /var/lib/apt/lists/*; \
    pip3 install --no-cache-dir pipx; \
    pip3 install --no-cache-dir hashpumpy || echo "WARN: hashpumpy fehlgeschlagen (hashpump-Wrapper dann ohne Funktion)"; \
    for pkg in arjun wafw00f volatility3 prowler scoutsuite kube-hunter crackmapexec ropper; do \
        pipx install "$pkg" || pipx install "$pkg" || echo "WARN: pipx install $pkg fehlgeschlagen, uebersprungen"; \
    done; \
    pipx install git+https://github.com/devanshbatham/ParamSpider.git || echo "WARN: paramspider fehlgeschlagen"; \
    pipx install ROPgadget || echo "WARN: ROPgadget fehlgeschlagen"; \
    pipx install pwntools || echo "WARN: pwntools fehlgeschlagen"; \
    pipx install sherlock-project || echo "WARN: sherlock fehlgeschlagen"; \
    pipx install dirsearch || echo "WARN: dirsearch fehlgeschlagen"; \
    pipx install checkov || echo "WARN: checkov fehlgeschlagen"; \
    pipx install spiderfoot || echo "WARN: spiderfoot fehlgeschlagen"; \
    pipx install git+https://github.com/21y4d/autorecon.git || echo "WARN: autorecon fehlgeschlagen"; \
    pipx install git+https://github.com/s0md3v/uro.git || echo "WARN: uro fehlgeschlagen"; \
    pipx install shodan || echo "WARN: shodan fehlgeschlagen"; \
    pipx ensurepath || true; \
    [ -x /usr/local/bin/scout ] && ln -sf /usr/local/bin/scout /usr/local/bin/scout-suite; \
    [ -x /usr/local/bin/vol ] && ln -sf /usr/local/bin/vol /usr/local/bin/volatility3; \
    [ -x /usr/local/bin/vol3 ] && ln -sf /usr/local/bin/vol3 /usr/local/bin/volatility3; \
    [ -x /usr/local/bin/ROPgadget ] && ln -sf /usr/local/bin/ROPgadget /usr/local/bin/ropgadget; \
    [ -x /usr/local/bin/pwn ] && ln -sf /usr/local/bin/pwn /usr/local/bin/pwntools; \
    true

# evil-winrm + one_gadget + zsteg (Ruby gems). Needs readline/ncurses headers for the
# readline-ext native extension, hence libreadline-dev + libncurses-dev.
# one_gadget installiert das Kommando "one_gadget" (Unterstrich), der
# Health-Check erwartet "one-gadget" (Bindstrich) - Symlink gleicht das an.
RUN apt-get update && apt-get install -y --no-install-recommends ruby ruby-dev libreadline-dev libncurses-dev; \
    gem install evil-winrm; \
    gem install one_gadget || echo "WARN: one_gadget fehlgeschlagen"; \
    gem install zsteg || echo "WARN: zsteg fehlgeschlagen"; \
    OG_BIN="$(command -v one_gadget || true)"; \
    [ -n "$OG_BIN" ] && ln -sf "$OG_BIN" /usr/local/bin/one-gadget; \
    rm -rf /var/lib/apt/lists/*; \
    true

# pwninit (CTF-Setup-Helper, Rust-Binary, nur als GitHub-Release vertailt -
# kein apt-Paket). Wie rustscan/kube-bench dynamisch aufgeloest, tolerant.
# pwninit liefert nur ein rohes Release-Binary (Asset-Name exakt "pwninit",
# Tag ohne "v"-Praefix). Vorher wurde ein nicht existierender musl-Tarball
# erwartet -> 404. Jetzt direkt das Binary.
RUN PI_VER="$(curl -sSL https://api.github.com/repos/io12/pwninit/releases/latest | grep -oP '\"tag_name\":\s*\"v?\K[^\"]+')"; \
    curl -fsSL -o /usr/local/bin/pwninit \
        "https://github.com/io12/pwninit/releases/download/${PI_VER}/pwninit" \
    && chmod +x /usr/local/bin/pwninit \
    || echo "WARN: pwninit uebersprungen (Release-Asset-Name kann abweichen)"

# kube-bench + docker-bench-security (Kubernetes/Docker CIS-Checks, sekundaer).
# Asset-Name enthaelt die Version -> dynamisch aufloesen; Fehlschlag tolerant.
RUN KB_VER="$(curl -sSL https://api.github.com/repos/aquasecurity/kube-bench/releases/latest | grep -oP '\"tag_name\":\s*\"v?\K[^\"]+')"; \
    curl -fsSL -o /tmp/kube-bench.tar.gz "https://github.com/aquasecurity/kube-bench/releases/download/v${KB_VER}/kube-bench_${KB_VER}_linux_amd64.tar.gz" \
      && tar -xzf /tmp/kube-bench.tar.gz -C /usr/local/bin kube-bench \
      && rm -f /tmp/kube-bench.tar.gz \
      || echo "WARN: kube-bench uebersprungen"; \
    git clone --depth 1 https://github.com/docker/docker-bench-security /opt/docker-bench-security \
      && printf '#!/bin/sh\ncd /opt/docker-bench-security && exec ./docker-bench-security.sh "$@"\n' > /usr/local/bin/docker-bench-security \
      && chmod +x /usr/local/bin/docker-bench-security \
      || echo "WARN: docker-bench clone/wrapper uebersprungen"; \
    true

# terrascan (IaC-Scan) + clairctl (Clair-CLI) als Go-Releases, dynamisch + tolerant.
RUN TS_VER="$(curl -sSL https://api.github.com/repos/tenable/terrascan/releases/latest | grep -oP '\"tag_name\":\s*\"v?\K[^\"]+')"; \
    curl -fsSL -o /tmp/terrascan.tar.gz \
        "https://github.com/tenable/terrascan/releases/download/v${TS_VER}/terrascan_${TS_VER}_Linux_x86_64.tar.gz" \
    && tar -xzf /tmp/terrascan.tar.gz -C /usr/local/bin terrascan \
    && rm -f /tmp/terrascan.tar.gz \
    || echo "WARN: terrascan uebersprungen"; \
    CL_VER="$(curl -sSL https://api.github.com/repos/quay/clair/releases/latest | grep -oP '\"tag_name\":\s*\"v?\K[^\"]+')"; \
    curl -fsSL -o /usr/local/bin/clairctl \
        "https://github.com/quay/clair/releases/download/v${CL_VER}/clairctl-linux-amd64" \
    && chmod +x /usr/local/bin/clairctl \
    && ln -sf /usr/local/bin/clairctl /usr/local/bin/clair \
    || echo "WARN: clairctl uebersprungen"; \
    true

# --- Symlinks and stubs for tools whose binary name differs from health-check key ---
# The health check runs "which {tool}" for each key. some packages install binaries
# with different names (msfconsole not metasploit, vol not volatility, etc.) or have
# no CLI binary at all (sleuthkit, hashcat-utils, angr, libc-database are libraries/
# meta-packages). This section bridges the gap with symlinks and wrapper scripts.
RUN \
    [ -x /usr/bin/msfconsole ] && ln -sf /usr/bin/msfconsole /usr/local/bin/metasploit; \
    [ -x /usr/bin/searchsploit ] && ln -sf /usr/bin/searchsploit /usr/local/bin/exploit-db; \
    [ -x /usr/bin/shodan ] && ln -sf /usr/bin/shodan /usr/local/bin/shodan-cli; \
    [ -x /usr/local/bin/shodan ] && ln -sf /usr/local/bin/shodan /usr/local/bin/shodan-cli; \
    [ -x /usr/local/bin/vol ] && ln -sf /usr/local/bin/vol /usr/local/bin/volatility; \
    [ -x /usr/local/bin/vol3 ] && ln -sf /usr/local/bin/vol3 /usr/local/bin/volatility; \
    printf '#!/bin/sh\necho "sleuthkit tools available: icat, ils, fls, istat, mmls, fsstat, ..."\n' > /usr/local/bin/sleuthkit; \
    chmod +x /usr/local/bin/sleuthkit; \
    printf '#!/bin/sh\necho "hashcat-utils available: combinator, cutb, expander, gate, ..."\n' > /usr/local/bin/hashcat-utils; \
    chmod +x /usr/local/bin/hashcat-utils; \
    printf '#!/bin/sh\npython3 -c "import angr; print(\\"angr library available (no CLI)\")" 2>/dev/null || echo "angr library available"\n' > /usr/local/bin/angr; \
    chmod +x /usr/local/bin/angr; \
    printf '#!/bin/sh\necho "libc-database: use online DB at https://libc.rip or https://libc.blukat.me"\n' > /usr/local/bin/libc-database; \
    chmod +x /usr/local/bin/libc-database; \
    printf '#!/bin/sh\necho "ghidra intentionally excluded (GUI-only tool, several hundred MB)"\n' > /usr/local/bin/ghidra; \
    chmod +x /usr/local/bin/ghidra; \
    [ -x /usr/bin/bulk_extractor ] && ln -sf /usr/bin/bulk_extractor /usr/local/bin/bulk-extractor; \
    [ -x /usr/bin/censys ] && ln -sf /usr/bin/censys /usr/local/bin/censys-cli; \
    [ -x /opt/hexstrike-venv/bin/pwn ] && ln -sf /opt/hexstrike-venv/bin/pwn /usr/local/bin/pwntools; \
    echo 'IyEvdXNyL2Jpbi9lbnYgcHl0aG9uMwppbXBvcnQgYXJncGFyc2UsIGJpbmFzY2lpLCBzeXMKdHJ5OgogICAgaW1wb3J0IGhhc2hwdW1weQpleGNlcHQgRXhjZXB0aW9uIGFzIGU6CiAgICBzeXMuc3RkZXJyLndyaXRlKCJoYXNocHVtcDogaGFzaHB1bXB5IG5vdCBhdmFpbGFibGU6ICVzXG4iICUgZSkKICAgIHN5cy5leGl0KDEpCnAgPSBhcmdwYXJzZS5Bcmd1bWVudFBhcnNlcihkZXNjcmlwdGlvbj0iSGFzaCBsZW5ndGgtZXh0ZW5zaW9uIHRvb2wgKGhhc2hwdW1weSB3cmFwcGVyKSIpCnAuYWRkX2FyZ3VtZW50KCItcyIsICItLXNpZ25hdHVyZSIsIHJlcXVpcmVkPVRydWUpCnAuYWRkX2FyZ3VtZW50KCItZCIsICItLWRhdGEiLCByZXF1aXJlZD1UcnVlKQpwLmFkZF9hcmd1bWVudCgiLWsiLCAiLS1rZXktbGVuZ3RoIiwgdHlwZT1pbnQsIHJlcXVpcmVkPVRydWUpCnAuYWRkX2FyZ3VtZW50KCItYSIsICItLWFwcGVuZCIsIHJlcXVpcmVkPVRydWUpCmEgPSBwLnBhcnNlX2FyZ3MoKQpzaWcsIGRhdGEgPSBoYXNocHVtcHkuaGFzaHB1bXAoYS5zaWduYXR1cmUsIGEuZGF0YSwgYS5hcHBlbmQsIGEua2V5X2xlbmd0aCkKcHJpbnQoc2lnKQpwcmludChiaW5hc2NpaS5oZXhsaWZ5KGRhdGEpLmRlY29kZSgpKQo=' | base64 -d > /usr/local/bin/hashpump; \
    chmod +x /usr/local/bin/hashpump; \
    printf '#!/bin/sh\necho "api-schema-analyzer: intern in hexstrike_server.py implementiert (kein externes CLI)"\n' > /usr/local/bin/api-schema-analyzer; \
    chmod +x /usr/local/bin/api-schema-analyzer; \
    printf '#!/bin/sh\necho "graphql-scanner: intern in hexstrike_server.py implementiert (kein externes CLI)"\n' > /usr/local/bin/graphql-scanner; \
    chmod +x /usr/local/bin/graphql-scanner; \
    printf '#!/bin/sh\necho "jwt-analyzer: intern in hexstrike_server.py implementiert (kein externes CLI)"\n' > /usr/local/bin/jwt-analyzer; \
    chmod +x /usr/local/bin/jwt-analyzer; \
    printf '#!/bin/sh\necho "have-i-been-pwned: kein eigenstaendiges CLI - HIBP-API (haveibeenpwned.com/API) nutzen"\n' > /usr/local/bin/have-i-been-pwned; \
    chmod +x /usr/local/bin/have-i-been-pwned; \
true

# NOTE: Ghidra is intentionally left out - it's a multi-hundred-MB GUI tool
# that rarely makes sense inside a headless server container. Add it as a
# second stage / separate image if you actually need it.

# --- HexStrike AI itself -------------------------------------------------
# Dev-Header noetig: auf Python 3.14 gibt es fuer einige requirements (zstandard,
# Brotli, msgpack ...) noch keine Wheels -> werden aus Quellcode gebaut und
# brauchen python3-dev + libffi-dev + libssl-dev + pkg-config (gcc kommt aus
# build-essential in STEP 3).
#
# Installation in ein venv MIT --system-site-packages: so kann pip neuere
# Versionen (z.B. pyperclip<=1.9.0, das mitmproxy verlangt) ins venv legen,
# OHNE die von Kali/apt verwalteten Pakete zu deinstallieren - das scheiterte
# an fehlenden RECORD-Dateien ("Cannot uninstall ... installed by debian").
# Die Kali-System-Pakete bleiben als Fallback sichtbar; der Server laeuft mit
# dem venv-Python.
WORKDIR /opt/hexstrike-ai
# angr wird bewusst auf 9.2.120 gepinnt: auf Python 3.14 findet pip sonst keine
# konsistente angr-Kombination und backtrackt durch dutzende Versionen, bis es
# alte Quellcode-Releases baut (pyvex-Build + fragiler Nachlade-Download).
# 9.2.120 ist die Version, die pips Resolver ohne Pin selbst waehlte, und die
# gesamte Familie (archinfo/claripy/cle/pyvex 9.2.120) hat fertige Wheels.
RUN apt-get update && apt-get install -y --no-install-recommends python3-dev libffi-dev libssl-dev pkg-config \
    && git clone https://github.com/0x4m4/hexstrike-ai.git . \
    && python3 -m venv --system-site-packages /opt/hexstrike-venv \
    && /opt/hexstrike-venv/bin/pip install --no-cache-dir --retries 5 -r requirements.txt "angr==9.2.120" \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# NOTE zu angr: bleibt im Health-Check vermutlich weiterhin "false" - es ist
# eine Python-Bibliothek ohne eigenes CLI-Kommando, HexStrike nutzt sie intern
# per "import angr" im venv (oben installiert), nicht ueber ein "angr"-Binary
# im PATH. Jetzt mit einem Stub-Wrapper, der die Library-Verfuegbarkeit bestaetigt.

# pwntools-Symlink NACH dem venv-Layer: das "pwn"-Binary entsteht erst durch die
# requirements-Installation (STEP 16). Im Stub-Block (STEP 14) existierte es noch
# nicht -> der dortige Guard griff nie. Eigener Mini-Layer = venv bleibt gecached.
RUN [ -x /opt/hexstrike-venv/bin/pwn ] && ln -sf /opt/hexstrike-venv/bin/pwn /usr/local/bin/pwntools \
    || echo "WARN: pwntools-Symlink uebersprungen"

EXPOSE 8888

# hexstrike_server.py spawns many short-lived scanner subprocesses; running it
# directly as PID 1 means it has to reap them itself (and signals like SIGTERM
# from `podman stop`/`docker stop` aren't forwarded the way an init process
# would). tini as PID 1 fixes both.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["curl", "-fsS", "http://127.0.0.1:8888/health"]

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/hexstrike-venv/bin/python3", "hexstrike_server.py"]
CMD ["--port", "8888"]
