# KI-OS Stack

Docker-Compose-Orchestrierung für **Bot + Dashboard + MCP** als ein Projekt.

Im Docker-UI erscheint das als ein Projekt **`ki-os`** mit 3 Containern:
- `ki-os-bot` (Telegram-Bot)
- `ki-os-dashboard` (Web-UI auf Port 5001 direct exposed)
- `ki-os-mcp` (Vault-MCP-Server, intern; extern via Edge-Proxy)

Alle 3 Container teilen sich den gleichen Vault.
Bot + MCP read-write, Dashboard read-only.

## Verwandte Repos

| Repo | Pfad auf VPS | Zweck |
|---|---|---|
| [`KI_WIKI_OS`](https://github.com/julasim/KI_WIKI_OS) | `/opt/bot/` | Telegram-Bot (Python) |
| [`KI_WIKI_Dashboard`](https://github.com/julasim/KI_WIKI_Dashboard) | `/opt/dashboard/` | Web-Dashboard (Next.js) |
| [`KI_WIKI_MCP`](https://github.com/julasim/KI_WIKI_MCP) | `/opt/mcp/` | MCP-Server (Vault-Tools für Claude Code) |
| [`Proxy`](https://github.com/julasim/Proxy) | `/opt/proxy/` | **Edge-Reverse-Proxy** (Caddy für ALLE Apps am VPS) |
| [`KI_WIKI_Stack`](https://github.com/julasim/KI_WIKI_Stack) ← du bist hier | `/opt/ki-os/` | Diese Compose-Orchestrierung |

## Architektur

```
Internet
   │
   ▼ 80/443
edge-caddy   (im /opt/proxy/-Stack — TLS, alle Domains zentral)
   │
   │  reverse_proxy via 'proxy' Docker-Netzwerk
   │
   ├─→ mcp.ki.wiki  →  ki-os-mcp:5002
   │
   ▼
ki-os-mcp ───┐
ki-os-bot ───┤── share /opt/vault/KI_WIKI_Vault/
ki-os-dashboard (direct exposed :5001 für Lokalzugriff)
```

## Erst-Installation (auf VPS, einmalig)

```bash
cd /opt

# 1. Alle 5 Repos klonen (Proxy ZUERST!)
git clone https://github.com/julasim/Proxy.git proxy
git clone https://github.com/julasim/KI_WIKI_OS.git bot
git clone https://github.com/julasim/KI_WIKI_Dashboard.git dashboard
git clone https://github.com/julasim/KI_WIKI_MCP.git mcp
git clone https://github.com/julasim/KI_WIKI_Stack.git ki-os

# 2. Bot-Konfig
cd /opt/bot
cp .env.example .env
nano .env

# 3. MCP-Konfig
cd /opt/mcp
cp .env.example .env
nano .env   # MCP_TOKEN setzen

# 4. Edge-Proxy ZUERST starten (legt 'proxy'-Netzwerk an)
cd /opt/proxy
bash install.sh

# 5. KI-OS-Stack starten
cd /opt/ki-os
bash install.sh
```

Dashboard ist danach erreichbar unter `http://<vps-ip>:5001`.
MCP-Server unter `https://<deine-domain>/mcp/` (DNS muss auf VPS-IP zeigen).

## Update

```bash
cd /opt/ki-os
bash update.sh
```

`update.sh` pulled bot/dashboard/mcp/stack und rebuildet wenn nötig.
Edge-Proxy hat eigenes update via `cd /opt/proxy && bash update.sh`.

## Layout

```
/opt/
├── proxy/                  Proxy Repo (Edge-Caddy)
│   ├── docker-compose.yml  ← startet edge-caddy
│   └── Caddyfile           ← ALLE Domains zentral
│
├── bot/                    KI_WIKI_OS Repo
├── dashboard/              KI_WIKI_Dashboard Repo
├── mcp/                    KI_WIKI_MCP Repo
│
├── ki-os/                  KI_WIKI_Stack Repo (DAS HIER)
│   ├── docker-compose.yml  ← bot + dashboard + mcp (KEIN Caddy mehr)
│   ├── install.sh
│   ├── update.sh
│   └── README.md
│
├── mcp-logs/               Persistent Audit-Log (vom MCP)
├── mcp-snapshots/          Persistent Backup-Snapshots (vom MCP)
└── vault/
    └── KI_WIKI_Vault/      Markdown-Vault
```

## Container-Details

### `ki-os-bot`
- Build: `../bot/Dockerfile`
- Volumes: `/opt/vault/KI_WIKI_Vault:/vault` (RW), whisper-cache, vault-backup
- Env: aus `/opt/bot/.env`
- Kein Port-Mapping (Telegram-Polling)

### `ki-os-dashboard`
- Build: `../dashboard/Dockerfile`
- Volumes: `/opt/vault/KI_WIKI_Vault:/vault:ro` (RO)
- Env: `PORT=5000`, `HOSTNAME=0.0.0.0`, `NODE_ENV=production`
- Port: `5001:5000` (direct exposed — kein Edge-Proxy für Dashboard)
- Wenn TLS gewünscht: ins proxy-Netzwerk hängen + Caddyfile-Block ergänzen

### `ki-os-mcp`
- Build: `../mcp/Dockerfile`
- Volumes:
  - `/opt/vault/KI_WIKI_Vault:/vault` (RW)
  - `/opt/mcp-logs:/var/log/mcp` (Audit-Log)
  - `/opt/mcp-snapshots:/snapshots` (Backup-Snapshots)
- Env: aus `/opt/mcp/.env`, `MCP_PORT=5002`
- Kein externer Port — externe Calls ausschließlich via Edge-Caddy
- Healthcheck: `http://localhost:5002/health`
- **Im `proxy`-Netzwerk** für edge-caddy Reverse-Proxy

## Edge-Proxy-Anbindung

MCP wird im `Caddyfile` des `/opt/proxy/`-Stacks referenziert:
```
mcp.ki.wiki {
    reverse_proxy ki-os-mcp:5002
    ...
}
```

Container-Hostname in Caddyfile = `ki-os-mcp` (= container_name aus
docker-compose.yml dieses Stacks).

## Migration vom alten Setup (Caddy war früher hier)

Falls du noch das alte Setup mit Caddy-im-ki-os-Stack hast:

```bash
# 1. Edge-Proxy klonen + starten
cd /opt && git clone https://github.com/julasim/Proxy.git proxy
cd /opt/proxy && bash install.sh
# (Caddy versucht 80/443 zu binden — kollidiert noch mit altem ki-os-caddy)

# 2. Alten ki-os-caddy stoppen
cd /opt/ki-os
docker compose stop caddy
docker compose rm -f caddy

# 3. Neuen ki-os-Stack pullen + rebuild (MCP joint proxy-Netzwerk)
git pull
docker compose up -d --build

# 4. Edge-Proxy startet jetzt sauber
cd /opt/proxy && docker compose up -d
docker compose logs -f caddy   # Cert-Issue zuschauen
```

## Logs

```bash
cd /opt/ki-os && docker compose logs -f bot
cd /opt/ki-os && docker compose logs -f dashboard
cd /opt/ki-os && docker compose logs -f mcp

# Edge-Proxy-Logs separat:
cd /opt/proxy && docker compose logs -f caddy
```

## Status

- ✅ Bot + Dashboard + MCP als ein Stack
- ✅ Edge-Proxy ausgelagert (`Proxy`)
- ✅ MCP via TLS-Domain `mcp.ki.wiki`
- ✅ Block 1 Hardening (Rate-Limit, Audit-Log, Snapshots, Multi-Token)
- ⏳ Dashboard-Auth (vorerst nur via VPS-IP)
