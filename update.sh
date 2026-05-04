#!/usr/bin/env bash
# update.sh — KI-OS Stack komplett aktualisieren
# Pullt bot + dashboard + stack, baut Container neu, startet.
#
# Verwendung auf VPS:
#   cd /opt/ki-os && bash update.sh

set -euo pipefail
cd "$(dirname "$0")"

echo "═══════════════════════════════════════════════"
echo "   KI-OS Stack — Update"
echo "═══════════════════════════════════════════════"
echo

# ── Repo-Layout-Check ──
[ -d ../bot ]       || { echo "❌ /opt/bot fehlt — git clone julasim/KI_WIKI_OS dorthin"; exit 1; }
[ -d ../dashboard ] || { echo "❌ /opt/dashboard fehlt — git clone julasim/KI_WIKI_Dashboard dorthin"; exit 1; }
[ -d ../mcp ]       || { echo "❌ /opt/mcp fehlt — git clone julasim/KI_WIKI_MCP dorthin"; exit 1; }
[ -f ../bot/.env ]  || { echo "❌ /opt/bot/.env fehlt — Bot-Setup unvollständig"; exit 1; }
[ -f ../mcp/.env ]  || { echo "❌ /opt/mcp/.env fehlt — MCP-Setup unvollständig (siehe .env.example)"; exit 1; }

# ── Repo-Identität verifizieren (gegen versehentlichen Cross-Mount) ──
verify_repo() {
    local dir="$1"
    local expected="$2"
    local actual
    actual=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "")
    if [[ "$actual" != *"$expected"* ]]; then
        echo "❌ FALSCHES REPO in $dir."
        echo "   Erwarte: julasim/$expected"
        echo "   Origin:  $actual"
        exit 1
    fi
}
verify_repo ../bot       "KI_WIKI_OS"
verify_repo ../dashboard "KI_WIKI_Dashboard"
verify_repo ../mcp       "KI_WIKI_MCP"
verify_repo .            "KI_WIKI_Stack"

# ── Pull alle 3 Repos ──
ANY_CHANGED=0

pull_repo() {
    local name="$1"
    local dir="$2"
    echo "──── Pull $name ────"
    local before after
    before=$(git -C "$dir" rev-parse HEAD)
    git -C "$dir" pull
    after=$(git -C "$dir" rev-parse HEAD)
    if [ "$before" != "$after" ]; then
        echo "✓ $name aktualisiert: $before → $after"
        git -C "$dir" log --oneline "$before..$after"
        ANY_CHANGED=1
    else
        echo "= $name unverändert"
    fi
    echo
}

pull_repo "Bot"       ../bot
pull_repo "Dashboard" ../dashboard
pull_repo "MCP"       ../mcp
pull_repo "Stack"     .

if [ "$ANY_CHANGED" = "0" ]; then
    echo "✓ Nichts zu tun — alle Repos auf neuestem Stand."
    echo
    echo "──── Aktueller Status ────"
    docker compose ps
    exit 0
fi

# ── Container neu bauen + starten ──
echo "──── docker compose up -d --build ────"
docker compose up -d --build

echo
echo "──── Status ────"
docker compose ps

IP=$(hostname -I | awk '{print $1}')
echo
echo "✓ KI-OS Stack läuft."
echo "  Bot:       (Telegram, kein HTTP)"
echo "  Dashboard: http://$IP:3001"
echo "  MCP:       http://$IP:3002/mcp  (health: /health)"
