# KI-OS Stack

Docker-Compose-Orchestrierung für **Bot + Dashboard** als ein Projekt.

Im Docker-UI (Coolify/Portainer/etc.) erscheint das als ein Projekt **`ki-os`** mit 2 Containern:
- `ki-os-bot` (Telegram-Bot)
- `ki-os-dashboard` (Web-UI auf Port 5001)

Beide Container sharen den gleichen Vault — Bot read-write, Dashboard read-only.

## Verwandte Repos

| Repo | Pfad auf VPS | Zweck |
|---|---|---|
| [`KI_WIKI_OS`](https://github.com/julasim/KI_WIKI_OS) | `/opt/bot/` | Telegram-Bot (Python) |
| [`KI_WIKI_Dashboard`](https://github.com/julasim/KI_WIKI_Dashboard) | `/opt/dashboard/` | Web-Dashboard (Next.js) |
| [`KI_WIKI_MCP`](https://github.com/julasim/KI_WIKI_MCP) | `/opt/mcp/` | MCP-Server (Python, Vault-Tools für Claude Code) |
| [`KI_WIKI_Stack`](https://github.com/julasim/KI_WIKI_Stack) ← du bist hier | `/opt/ki-os/` | Docker-Compose-Orchestrierung |

## Erst-Installation (auf VPS, einmalig)

```bash
cd /opt

# 1. Alle 4 Repos klonen
git clone https://github.com/julasim/KI_WIKI_OS.git bot
git clone https://github.com/julasim/KI_WIKI_Dashboard.git dashboard
git clone https://github.com/julasim/KI_WIKI_MCP.git mcp
git clone https://github.com/julasim/KI_WIKI_Stack.git ki-os

# 2. Bot-Konfig (.env)
cd /opt/bot
cp .env.example .env
nano .env   # TG_TOKEN, ALLOWED_USER_ID, LLM_API_KEY etc. eintragen

# 3. MCP-Konfig (.env mit Bearer-Token)
cd /opt/mcp
cp .env.example .env
nano .env   # MCP_TOKEN setzen — generieren mit: python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# 4. Stack starten
cd /opt/ki-os
bash install.sh
```

Dashboard ist danach erreichbar unter `http://<vps-ip>:5001`.

## Update

```bash
cd /opt/ki-os
bash update.sh
```

`update.sh` macht automatisch:
1. Verifiziert dass alle 4 Repos die richtigen Git-Origins haben (Schutz gegen versehentlichen Cross-Mount)
2. Pullt Bot, Dashboard, MCP, Stack — meldet was sich geändert hat
3. Wenn nichts neu: nichts tun
4. Wenn neu: `docker compose up -d --build` mit Status-Output

## Layout

```
/opt/
├── bot/                    KI_WIKI_OS Repo
│   ├── ki_wiki_bot.py
│   ├── Dockerfile
│   ├── docker-compose.yml  ← obsolete im Stack-Setup, dient als Solo-Fallback
│   └── .env                ← USER konfiguriert
│
├── dashboard/              KI_WIKI_Dashboard Repo
│   ├── app/                Next.js-App
│   ├── Dockerfile
│   └── docker-compose.yml  ← obsolete im Stack-Setup
│
├── mcp/                    KI_WIKI_MCP Repo
│   ├── ki_os_mcp/          MCP-Server (Streamable HTTP)
│   ├── Dockerfile
│   └── .env                ← USER konfiguriert (MCP_TOKEN)
│
├── ki-os/                  KI_WIKI_Stack Repo (DAS HIER)
│   ├── docker-compose.yml  ← orchestriert alles
│   ├── install.sh
│   ├── update.sh
│   └── README.md
│
└── vault/
    └── KI_WIKI_Vault/      Markdown-Vault (read-write von Bot+MCP, read-only vom Dashboard)
```

## Container-Details

### `ki-os-bot`
- Build: `../bot/Dockerfile`
- Volumes:
  - `/opt/vault/KI_WIKI_Vault:/vault` (read-write)
  - `whisper-cache:/root/.cache/huggingface` (Whisper-Modell, persistent)
  - `vault-backup:/vault-backup` (Git-Backup-Repo)
- Env: aus `/opt/bot/.env`
- Kein Port-Mapping (Telegram-Polling, kein HTTP)

### `ki-os-dashboard`
- Build: `../dashboard/Dockerfile`
- Volumes:
  - `/opt/vault/KI_WIKI_Vault:/vault:ro` (READ-ONLY)
- Env: `VAULT_PATH=/vault`, `NODE_ENV=production`, `PORT=5000`
- Port: `5001:5000`

### `ki-os-mcp`
- Build: `../mcp/Dockerfile`
- Volumes:
  - `/opt/vault/KI_WIKI_Vault:/vault` (read-write)
  - `/opt/mcp-logs:/var/log/mcp` (audit log)
  - `/opt/mcp-snapshots:/snapshots` (backup snapshots)
- Env: aus `/opt/mcp/.env` (`MCP_TOKEN`, `MCP_PORT=5002`)
- Kein externer Port (nur intern via Caddy reverse-proxy)
- Healthcheck: `/health`

### `ki-os-caddy`
- Image: `caddy:2-alpine`
- Container-intern: HTTP `5080`, HTTPS `5443` (Projekt-Konvention 5xxx)
- Host-exposed: `80` + `443` (Standard-Web-Ports für TLS-Issuance + saubere URLs)
- Holt automatisch Let's-Encrypt-Cert je Domain
- Volumes: `caddy-data` (Certs), `caddy-config`

## Migration vom alten Setup

Wenn du vorher Bot via `cd /opt/bot && bash update.sh` separat laufen hattest:

```bash
# Alten Bot-Container stoppen
cd /opt/bot && docker compose down

# Stack starten — übernimmt ab jetzt
cd /opt/ki-os && bash install.sh
```

Die alten `docker-compose.yml`-Files in `/opt/bot/` und `/opt/dashboard/` bleiben als Solo-Fallback liegen, werden aber nicht mehr aktiv genutzt.

## Logs anschauen

```bash
cd /opt/ki-os

# Live-Logs beider Container
docker compose logs -f

# Nur Bot
docker compose logs -f bot

# Nur Dashboard
docker compose logs -f dashboard

# Nur MCP
docker compose logs -f mcp
```

## Status

✅ Stack-Compose mit Bot + Dashboard + MCP
✅ install.sh + update.sh mit Repo-Verifikation
✅ MCP mit Bearer-Auth (Token aus /opt/mcp/.env)
⏳ Caddy-Reverse-Proxy + HTTPS (vorerst nicht — direkter Port-Zugriff)
⏳ Dashboard-Auth (vorerst keine)
