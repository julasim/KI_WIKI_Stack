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
| [`KI_WIKI_OS`](https://github.com/julasim/KI_WIKI_OS) | `/opt/KI_WIKI_OS/` | Telegram-Bot (Python) |
| [`KI_WIKI_Dashboard`](https://github.com/julasim/KI_WIKI_Dashboard) | `/opt/KI_WIKI_Dashboard/` | Web-Dashboard (Next.js) |
| [`KI_WIKI_MCP`](https://github.com/julasim/KI_WIKI_MCP) | `/opt/KI_WIKI_MCP/` | MCP-Server (Vault-Tools für Claude Code) |
| [`Proxy`](https://github.com/julasim/Proxy) | `/opt/Proxy/` | **Edge-Reverse-Proxy** (Caddy für ALLE Apps am VPS) |
| [`KI_WIKI_Stack`](https://github.com/julasim/KI_WIKI_Stack) ← du bist hier | `/opt/KI_WIKI_Stack/` | Diese Compose-Orchestrierung |

## Architektur

```
Internet
   │
   ▼ 80/443
edge-caddy   (im /opt/Proxy/-Stack — TLS, alle Domains zentral)
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
git clone https://github.com/julasim/Proxy.git Proxy
git clone https://github.com/julasim/KI_WIKI_OS.git KI_WIKI_OS
git clone https://github.com/julasim/KI_WIKI_Dashboard.git KI_WIKI_Dashboard
git clone https://github.com/julasim/KI_WIKI_MCP.git KI_WIKI_MCP
git clone https://github.com/julasim/KI_WIKI_Stack.git KI_WIKI_Stack

# 2. Bot-Konfig
cd /opt/KI_WIKI_OS
cp .env.example .env
nano .env

# 3. MCP-Konfig
cd /opt/KI_WIKI_MCP
cp .env.example .env
nano .env   # MCP_TOKEN setzen

# 4. Edge-Proxy ZUERST starten (legt 'proxy'-Netzwerk an)
cd /opt/Proxy
bash install.sh

# 5. KI-OS-Stack starten
cd /opt/KI_WIKI_Stack
bash install.sh
```

Dashboard ist danach erreichbar unter `http://<vps-ip>:5001`.
MCP-Server unter `https://<deine-domain>/mcp/` (DNS muss auf VPS-IP zeigen).

## Update

```bash
cd /opt/KI_WIKI_Stack
bash update.sh
```

`update.sh` pulled KI_WIKI_OS/KI_WIKI_Dashboard/KI_WIKI_MCP/Stack und rebuildet wenn nötig.
Edge-Proxy hat eigenes update via `cd /opt/Proxy && bash update.sh`.

## Layout

```
/opt/
├── Proxy/                  Proxy Repo (Edge-Caddy)
│   ├── docker-compose.yml  ← startet edge-caddy
│   └── Caddyfile           ← ALLE Domains zentral
│
├── KI_WIKI_OS/             KI_WIKI_OS Repo (Bot)
├── KI_WIKI_Dashboard/      KI_WIKI_Dashboard Repo
├── KI_WIKI_MCP/            KI_WIKI_MCP Repo
│
├── KI_WIKI_Stack/          KI_WIKI_Stack Repo (DAS HIER)
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
- Build: `../KI_WIKI_OS/Dockerfile`
- Volumes: `/opt/vault/KI_WIKI_Vault:/vault` (RW), whisper-cache, vault-backup
- Env: aus `../KI_WIKI_OS/.env`
- Kein Port-Mapping (Telegram-Polling)

### `ki-os-dashboard`
- Build: `../KI_WIKI_Dashboard/Dockerfile`
- Volumes: `/opt/vault/KI_WIKI_Vault:/vault:ro` (RO)
- Env: `PORT=5000`, `HOSTNAME=0.0.0.0`, `NODE_ENV=production`
- Port: `5001:5000` (direct exposed — kein Edge-Proxy für Dashboard)
- Wenn TLS gewünscht: ins proxy-Netzwerk hängen + Caddyfile-Block ergänzen

### `ki-os-mcp`
- Build: `../KI_WIKI_MCP/Dockerfile`
- Volumes:
  - `/opt/vault/KI_WIKI_Vault:/vault` (RW)
  - `/opt/mcp-logs:/var/log/mcp` (Audit-Log)
  - `/opt/mcp-snapshots:/snapshots` (Backup-Snapshots)
- Env: aus `../KI_WIKI_MCP/.env`, `MCP_PORT=5002`
- Kein externer Port — externe Calls ausschließlich via Edge-Caddy
- Healthcheck: `http://localhost:5002/health`
- **Im `proxy`-Netzwerk** für edge-caddy Reverse-Proxy

## Edge-Proxy-Anbindung

MCP wird im `Caddyfile` des `/opt/Proxy/`-Stacks referenziert:
```
mcp.ki.wiki {
    reverse_proxy ki-os-mcp:5002
    ...
}
```

Container-Hostname in Caddyfile = `ki-os-mcp` (= container_name aus
docker-compose.yml dieses Stacks).

## Bot ↔ MCP: Interner Container-Hostname (nicht Public-URL)

Bot und Dashboard sollen MCP **direkt** via Container-Hostname erreichen,
**nicht** über die oeffentliche TLS-URL (Hairpin durch Caddy zurueck zum
eigenen VPS). Hairpin-NAT funktioniert auf Docker-Bridge-Networks oft
nicht — Connection-Refused beim Connect zur eigenen Public-IP.

In `KI_WIKI_OS/.env` und `KI_WIKI_Dashboard/.env`:
```
MCP_URL=http://ki-os-mcp:5002/mcp/        # Bot
MCP_BASE_URL=http://ki-os-mcp:5002/mcp/   # Dashboard
```

(Beide Container sind auf dem `default`-Netz und erreichen `ki-os-mcp`
direkt — kein TLS, kein Caddy-Hop, schneller.)

MCP's DNS-Rebinding-Protection-Whitelist enthaelt `ki-os-mcp` und
`ki-os-mcp:5002` als Defaults (siehe `_DEFAULT_ALLOWED_HOSTS` in
`KI_WIKI_MCP/ki_os_mcp/server.py`). Wenn du `MCP_ALLOWED_HOSTS`
overrid'st: nicht vergessen diese mitzunehmen, sonst `421 Misdirected
Request` von MCP.

Externe Clients (Claude Desktop/Web, anderer Host) gehen weiterhin
ueber `https://wiki-mcp.sima.business/mcp/` via Edge-Proxy.

## Migration vom alten Setup (Caddy war früher hier)

> **Historischer Kontext:** Beschreibt die ursprüngliche Migration als Caddy aus dem Stack ausgelagert wurde. Pfadnamen unten reflektieren das damalige Layout (`/opt/ki-os/`, `/opt/proxy/`) — nicht das aktuelle (`/opt/KI_WIKI_Stack/`, `/opt/Proxy/`). Nur relevant wenn du wirklich noch das pre-Rename Setup laufen hast.

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
cd /opt/KI_WIKI_Stack && docker compose logs -f bot
cd /opt/KI_WIKI_Stack && docker compose logs -f dashboard
cd /opt/KI_WIKI_Stack && docker compose logs -f mcp

# Edge-Proxy-Logs separat:
cd /opt/Proxy && docker compose logs -f caddy
```

## Status

- ✅ Bot + Dashboard + MCP als ein Stack
- ✅ Edge-Proxy ausgelagert (`Proxy`)
- ✅ MCP via TLS-Domain `mcp.ki.wiki`
- ✅ Block 1 Hardening (Rate-Limit, Audit-Log, Snapshots, Multi-Token)
- ⏳ Dashboard-Auth (vorerst nur via VPS-IP)
