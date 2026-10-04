# Hexstrike-Docker

Containerized setup for running [HexStrike AI](https://github.com/0x4m4/hexstrike-ai) — an MCP (Model Context Protocol) server that exposes a large collection of offensive-security / pentesting CLI tools to an AI assistant (e.g. Claude Desktop) — in a rootless Podman container on Fedora/Silverblue.

## Why a container?

HexStrike AI's server component (`hexstrike_server.py`) shells out to dozens of security tools (nmap, sqlmap, nuclei, metasploit, volatility3, etc.). Rather than installing all of that on the host, this repo builds a Kali-based image that bundles the server and its tool dependencies, while the small MCP *bridge* script (`hexstrike_mcp.py`, launched directly by Claude Desktop) stays on the host and only talks HTTP to the container.

```
Claude Desktop ──(stdio/MCP)── hexstrike_mcp.py (host, venv)
                                      │
                                      │ HTTP
                                      ▼
                        hexstrike-server container (127.0.0.1:8888)
                        Kali rolling + nmap/sqlmap/nuclei/metasploit/...
```

The container port is published to `127.0.0.1` only — HexStrike can run active scans and exploits, so it must never be reachable from the LAN, only from the same machine running Claude Desktop's MCP bridge.

## ⚠️ Scope and intended use

This stack gives an AI agent the ability to run real offensive-security tooling (port scanners, exploit frameworks, password crackers, etc.). Only point it at systems you own or are explicitly authorized to test. The tool list included here is broad on purpose (recon, web, passwords, forensics, reverse engineering, cloud/IaC scanning) — treat the resulting image as a pentesting workstation, not a general-purpose container.

## Contents

| File | Purpose |
|---|---|
| `hexstrike/Dockerfile` | Builds the `hexstrike-server` image on `kalilinux/kali-rolling`: installs the bulk of the tool list via Kali metapackages, patches in tools that are missing/outdated in those metapackages (rustscan, trivy, Go-based recon tools, x8, pwninit, kube-bench, terrascan, …), adds symlinks/stub scripts so HexStrike's health check finds binaries under the names it expects, then installs HexStrike AI itself into a venv. |
| `hexstrike/hexstrike-server.container` | Podman Quadlet unit for running the built image as a systemd user service on Fedora/Silverblue (binds to `127.0.0.1:8888` only). |
| `hexstrike/setup-bridge.sh` | Sets up the host-side MCP bridge: clones `hexstrike-ai` (for `hexstrike_mcp.py`) and creates a dedicated virtualenv for it, separate from the container's tool-heavy environment. |
| `hexstrike/Claude-desktop-config.snippet` | `mcpServers` JSON snippet for `claude_desktop_config.json` (native install). |
| `hexstrike/Claude-desktop-config.flatpak.snippet` | Same, but via `flatpak-spawn --host` for a flatpak-installed Claude Desktop. |

## Setup

### 1. Build and run the server container

```bash
cd hexstrike
podman build -t localhost/hexstrike-server:latest .

# Quadlet (systemd) install:
mkdir -p ~/.config/containers/systemd
cp hexstrike-server.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user enable --now hexstrike-server.service
```

The container exposes port `8888`, bound to `127.0.0.1` only, and persists data under `~/.local/share/hexstrike-data`.

### 2. Set up the host-side MCP bridge

```bash
cd hexstrike
./setup-bridge.sh
```

This clones `hexstrike-ai` into `~/.local/share/hexstrike-ai` (for `hexstrike_mcp.py`) and creates a dedicated venv at `~/.local/share/hexstrike-bridge-venv`.

### 3. Point Claude Desktop at the bridge

Merge the relevant snippet into your `claude_desktop_config.json`:

- Native install → `Claude-desktop-config.snippet`
- Flatpak install → `Claude-desktop-config.flatpak.snippet` (replace `<DEIN_USERNAME>` with your username)

## Notes

- Ghidra is intentionally excluded from the image (GUI-only, several hundred MB) — add it as a separate stage/image if needed.
- Several tool installs in the `Dockerfile` resolve the latest GitHub release dynamically and are tolerant of failure (`|| echo "WARN: ..."`), so a single moved/renamed upstream asset doesn't break the whole build; check the build log for `WARN:` lines after an image rebuild.
