#!/usr/bin/env bash
# update.sh — KI-OS Stack komplett aktualisieren
# Pullt KI_WIKI_OS + KI_WIKI_Dashboard + KI_WIKI_MCP + Stack, baut Container neu, startet.
#
# Verwendung auf VPS:
#   cd /opt/KI_WIKI_Stack && bash update.sh

set -euo pipefail
cd "$(dirname "$0")"

echo "═══════════════════════════════════════════════"
echo "   KI-OS Stack — Update"
echo "═══════════════════════════════════════════════"
echo

# ── Repo-Layout-Check ──
[ -d ../KI_WIKI_OS ]        || { echo "❌ ../KI_WIKI_OS fehlt — git clone julasim/KI_WIKI_OS dorthin"; exit 1; }
[ -d ../KI_WIKI_Dashboard ] || { echo "❌ ../KI_WIKI_Dashboard fehlt — git clone julasim/KI_WIKI_Dashboard dorthin"; exit 1; }
[ -d ../KI_WIKI_MCP ]       || { echo "❌ ../KI_WIKI_MCP fehlt — git clone julasim/KI_WIKI_MCP dorthin"; exit 1; }
[ -f ../KI_WIKI_OS/.env ]   || { echo "❌ ../KI_WIKI_OS/.env fehlt — Bot-Setup unvollständig"; exit 1; }
[ -f ../KI_WIKI_MCP/.env ]  || { echo "❌ ../KI_WIKI_MCP/.env fehlt — MCP-Setup unvollständig (siehe .env.example)"; exit 1; }

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
verify_repo ../KI_WIKI_OS        "KI_WIKI_OS"
verify_repo ../KI_WIKI_Dashboard "KI_WIKI_Dashboard"
verify_repo ../KI_WIKI_MCP       "KI_WIKI_MCP"
verify_repo .                    "KI_WIKI_Stack"

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

pull_repo "Bot"       ../KI_WIKI_OS
pull_repo "Dashboard" ../KI_WIKI_Dashboard
pull_repo "MCP"       ../KI_WIKI_MCP
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
echo "  Dashboard: http://$IP:5001"
echo "  MCP:       https://<your-domain>/mcp/   (über Caddy)"
echo "             health: https://<your-domain>/health"
