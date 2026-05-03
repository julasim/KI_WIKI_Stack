# KI-OS Stack

Docker-Compose-Orchestrierung für **Bot + Dashboard** als ein Projekt.

Im Docker-UI (Coolify/Portainer/etc.) erscheint das als ein Projekt **`ki-os`** mit 2 Containern:
- `ki-os-bot` (Telegram-Bot)
- `ki-os-dashboard` (Web-UI auf Port 3001)

Beide Container sharen den gleichen Vault — Bot read-write, Dashboard read-only.

## Verwandte Repos

| Repo | Pfad auf VPS | Zweck |
|---|---|---|
| [`KI_WIKI_OS`](https://github.com/julasim/KI_WIKI_OS) | `/opt/bot/` | Telegram-Bot (Python) |
| [`KI_WIKI_Dashboard`](https://github.com/julasim/KI_WIKI_Dashboard) | `/opt/dashboard/` | Web-Dashboard (Next.js) |
| [`KI_OS_Stack`](https://github.com/julasim/KI_OS_Stack) ← du bist hier | `/opt/ki-os/` | Docker-Compose-Orchestrierung |

## Erst-Installation (auf VPS, einmalig)

```bash
cd /opt

# 1. Alle 3 Repos klonen
git clone https://github.com/julasim/KI_WIKI_OS.git bot
git clone https://github.com/julasim/KI_WIKI_Dashboard.git dashboard
git clone https://github.com/julasim/KI_OS_Stack.git ki-os

# 2. Bot-Konfig (.env)
cd /opt/bot
cp .env.example .env
nano .env   # TG_TOKEN, ALLOWED_USER_ID, LLM_API_KEY etc. eintragen

# 3. Stack starten
cd /opt/ki-os
bash install.sh
```

Dashboard ist danach erreichbar unter `http://<vps-ip>:3001`.

## Update

```bash
cd /opt/ki-os
bash update.sh
```

`update.sh` macht automatisch:
1. Verifiziert dass alle 3 Repos die richtigen Git-Origins haben (Schutz gegen versehentlichen Cross-Mount)
2. Pullt Bot, Dashboard, Stack — meldet was sich geändert hat
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
├── ki-os/                  KI_OS_Stack Repo (DAS HIER)
│   ├── docker-compose.yml  ← orchestriert alles
│   ├── install.sh
│   ├── update.sh
│   └── README.md
│
└── vault/
    └── KI_WIKI_Vault/      Markdown-Vault (read-write von Bot, read-only vom Dashboard)
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
- Env: `VAULT_PATH=/vault`, `NODE_ENV=production`
- Port: `3001:3000`

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
```

## Status

✅ Stack-Compose mit Bot + Dashboard
✅ install.sh + update.sh mit Repo-Verifikation
⏳ Caddy-Reverse-Proxy + HTTPS (vorerst nicht — direkter Port-Zugriff)
⏳ Auth (vorerst keine)
