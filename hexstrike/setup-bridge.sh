#!/usr/bin/env bash
# Sets up the lightweight MCP bridge (hexstrike_mcp.py) that Claude Desktop
# launches directly on the host. It only talks HTTP to the container - it
# does NOT need any of the pentesting tools, so it's fine to run natively
# on Silverblue without touching the base image.
set -euo pipefail

INSTALL_DIR="$HOME/.local/share/hexstrike-ai"
VENV_DIR="$HOME/.local/share/hexstrike-bridge-venv"

echo "==> Cloning hexstrike-ai (for hexstrike_mcp.py) into $INSTALL_DIR"
if [ -d "$INSTALL_DIR" ]; then
  git -C "$INSTALL_DIR" pull
else
  git clone https://github.com/0x4m4/hexstrike-ai.git "$INSTALL_DIR"
fi

echo "==> Creating bridge-only virtualenv at $VENV_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# The bridge script only needs an MCP client lib + an HTTP client, but since
# hexstrike doesn't ship a separate "bridge-only" requirements file, installing
# the repo's requirements.txt here is the safe option (it's small deps like
# requests/mcp, not the heavy scanning tools, which live in the container).
pip install --upgrade pip
pip install -r "$INSTALL_DIR/requirements.txt"

echo
echo "==> Done. Bridge python interpreter:"
echo "    $VENV_DIR/bin/python3"
echo
echo "Use this path (and $INSTALL_DIR/hexstrike_mcp.py) in claude_desktop_config.json"
echo "- see Claude-desktop-config.snippet (or Claude-desktop-config.flatpak.snippet) in this folder."
