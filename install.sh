#!/usr/bin/env bash
# install.sh — KI-OS Stack Erst-Installation
# Annahme: läuft in /opt/ki-os/ als root oder sudo
# Vorbedingung: bot + dashboard wurden schon nach /opt/bot bzw. /opt/dashboard
# geklont, /opt/bot/.env ist konfiguriert.
#
# Verwendung:
#   cd /opt
#   git clone https://github.com/julasim/Proxy.git proxy       # ZUERST!
#   git clone https://github.com/julasim/KI_WIKI_OS.git bot
#   git clone https://github.com/julasim/KI_WIKI_Dashboard.git dashboard
#   git clone https://github.com/julasim/KI_WIKI_MCP.git mcp
#   git clone https://github.com/julasim/KI_WIKI_Stack.git ki-os
#   cd /opt/bot && cp .env.example .env && nano .env  # Token + User-ID
#   cd /opt/mcp && cp .env.example .env && nano .env  # MCP_TOKEN setzen!
#   cd /opt/proxy && bash install.sh                  # Edge-Proxy starten (legt 'proxy'-Netz an)
#   cd /opt/ki-os && bash install.sh                  # Bot + Dashboard + MCP starten

set -euo pipefail
cd "$(dirname "$0")"

echo "═══════════════════════════════════════════════"
echo "   KI-OS Stack — Erst-Installation"
echo "═══════════════════════════════════════════════"
echo

# ── Pre-Checks ──
[ -d ../bot ]       || { echo "❌ /opt/bot fehlt"; exit 1; }
[ -d ../dashboard ] || { echo "❌ /opt/dashboard fehlt"; exit 1; }
[ -d ../mcp ]       || { echo "❌ /opt/mcp fehlt"; exit 1; }
[ -f ../bot/.env ]       || { echo "❌ /opt/bot/.env fehlt — bitte konfigurieren"; exit 1; }
[ -f ../mcp/.env ]       || { echo "❌ /opt/mcp/.env fehlt — siehe /opt/mcp/.env.example"; exit 1; }
[ -f ../dashboard/.env ] || { echo "❌ /opt/dashboard/.env fehlt — siehe /opt/dashboard/.env.example (NEXTAUTH_SECRET, DASHBOARD_USER_*)"; exit 1; }

# Externes proxy-Netzwerk muss existieren (vom Edge-Proxy-Stack erstellt)
if ! docker network inspect proxy >/dev/null 2>&1; then
    echo "❌ Docker-Netzwerk 'proxy' fehlt."
    echo "   Bitte zuerst Edge-Proxy installieren:"
    echo "     cd /opt && git clone https://github.com/julasim/Proxy.git proxy"
    echo "     cd /opt/proxy && bash install.sh"
    exit 1
fi
echo "✓ proxy-Netzwerk vorhanden"

# Vault-Pfad-Check
VAULT_PATH="/opt/vault/KI_WIKI_Vault"
if [ ! -d "$VAULT_PATH" ]; then
    echo "⚠️  Vault unter $VAULT_PATH nicht gefunden."
    echo "   Bot wird ihn beim ersten Start anlegen wenn das Volume gemountet wird."
    echo "   Trotzdem fortfahren? [y/N]"
    read -r ans
    [[ "${ans,,}" == "y" ]] || exit 1
fi

# Docker-Check
command -v docker >/dev/null 2>&1 || { echo "❌ Docker fehlt"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "❌ docker compose plugin fehlt"; exit 1; }

# ── Container bauen + starten ──
echo "──── Container bauen (kann 2-5 Min dauern) ────"
docker compose build

echo
echo "──── Starten ────"
docker compose up -d

echo
echo "──── Status ────"
docker compose ps

IP=$(hostname -I | awk '{print $1}')
echo
echo "✓ KI-OS Stack installiert."
echo "  Bot:       läuft im Hintergrund, antwortet auf Telegram"
echo "  Dashboard: http://$IP:5001"
echo "  MCP:       https://<your-domain>/mcp/   (über Caddy)"
echo "             health: https://<your-domain>/health"
echo
echo "Update später mit: cd /opt/ki-os && bash update.sh"
