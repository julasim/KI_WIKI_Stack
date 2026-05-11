# KI_WIKI_Stack — Docker-Compose-Orchestrator

Bündelt Bot + MCP + Dashboard als ein Compose-Projekt (`name: ki-os`). Keine eigenen Services — nur Build-Refs auf die drei Geschwister-Repos.

## Schlüssel-Dateien

| Datei | Was |
|---|---|
| `docker-compose.yml` | 3 Services (`bot`, `dashboard`, `mcp`), 2 Networks (`default` intern, `proxy` extern via Edge-Caddy) |
| `install.sh` | Erst-Installation: Pre-Checks (Repos + .env vorhanden), `docker compose build && up -d` |
| `update.sh` | `verify_repo` (Origin-URL-Match) + `git pull` für alle 4 Repos + rebuild |
| `README.md` | Setup-Anleitung, Architektur-Diagramm, Layout-Doku |

## Erwartetes VPS-Layout

```
/opt/
├── Proxy/                  (separater Stack — bitte zuerst!)
├── KI_WIKI_OS/             ../KI_WIKI_OS in docker-compose.yml
├── KI_WIKI_Dashboard/      ../KI_WIKI_Dashboard
├── KI_WIKI_MCP/            ../KI_WIKI_MCP
└── KI_WIKI_Stack/          ← du bist hier
```

Compose-Build-Paths sind relativ (`../KI_WIKI_OS` etc.) — Repos müssen Geschwister sein, sonst bricht der Build.

## Container-Setup

| Service | Container-Name | Networks | Ports | Vault-Access |
|---|---|---|---|---|
| `bot` | `ki-os-bot` | `default` | (keine — Telegram-Polling outbound) | RW |
| `dashboard` | `ki-os-dashboard` | `default`, `proxy` | `5001:5000` (direct), via Caddy mit TLS | RO |
| `mcp` | `ki-os-mcp` | `default`, `proxy` | (keine — externe nur via Caddy) | RW |

Externes `proxy`-Netzwerk wird vom Edge-Proxy-Stack (`/opt/Proxy/`) erstellt — **Proxy MUSS zuerst laufen**, sonst startet der MCP-Container nicht (Network-Dependency).

## Volume-Mounts (host:container)

- `/opt/vault/KI_WIKI_Vault:/vault` — Markdown-Vault, gemeinsam für alle 3
- `/opt/mcp-logs:/var/log/mcp` — Audit-Log-Persistenz
- `/opt/mcp-snapshots:/snapshots` — Pre-destruktiver-Op-Backup
- `/opt/mcp-oauth:/var/lib/mcp-oauth` — OAuth-SQLite-DB
- `whisper-cache` (named) — Whisper-Modell-Cache, persistent über Rebuilds
- `vault-backup` (named) — Restic-Backup-Workspace im Bot-Container

## Erst-Installation (Reihenfolge wichtig!)

```bash
cd /opt
# 1. Repos klonen (Proxy ZUERST — Network anlegen)
git clone https://github.com/julasim/Proxy.git Proxy
git clone https://github.com/julasim/KI_WIKI_OS.git KI_WIKI_OS
git clone https://github.com/julasim/KI_WIKI_Dashboard.git KI_WIKI_Dashboard
git clone https://github.com/julasim/KI_WIKI_MCP.git KI_WIKI_MCP
git clone https://github.com/julasim/KI_WIKI_Stack.git KI_WIKI_Stack

# 2. .env-Files konfigurieren
cd /opt/KI_WIKI_OS && cp .env.example .env && nano .env
cd /opt/KI_WIKI_MCP && cp .env.example .env && nano .env
cd /opt/KI_WIKI_Dashboard && cp .env.example .env && nano .env

# 3. Edge-Proxy starten (legt `proxy`-Network an)
cd /opt/Proxy && bash install.sh

# 4. Stack starten
cd /opt/KI_WIKI_Stack && bash install.sh
```

## Update-Flow

```bash
cd /opt/KI_WIKI_Stack && bash update.sh
```

Was `update.sh` macht:
1. Pre-Checks: alle 4 Repos vorhanden, .env-Files da
2. `verify_repo` pro Folder: Origin-URL muss `julasim/<Name>` enthalten — verhindert Cross-Mount-Unfälle wenn jemand das falsche Repo in den Ordner geklont hat
3. `git pull` in Bot, Dashboard, MCP, Stack — tracked welche Repos was Neues haben
4. Wenn irgendwas Neues: `docker compose up -d --build` (Docker-Cache rebuildet nur tatsächlich Geändertes)
5. `docker compose ps` Status-Output

Edge-Proxy ist eigener Stack, eigenes Update:
```bash
cd /opt/Proxy && git pull && bash update.sh
```

## Häufige Fallen

- **`docker compose restart` lädt `env_file` NICHT neu** — für ENV-Changes IMMER `up -d --force-recreate <service>`
- **Build-Paths sind relativ** — alle 4 Repos müssen als Geschwister unter demselben Parent liegen, sonst bricht der Build
- **`network: proxy` ist `external: true`** — Compose erstellt es nicht. Muss vom Proxy-Stack vorher existieren
- **Container-Names sind hardcoded** (`ki-os-bot` etc.) — Edge-Caddy referenziert die im `Caddyfile`, nicht umbenennen
- **Migration-Section im README** beschreibt eine HISTORISCHE Migration (Caddy aus Stack rausgezogen) — Pfadnamen dort sind das alte Layout, nicht relevant für neue Setups

## Was NICHT hier reingehört

- Service-spezifischer Code (Python/TS) — gehört in `KI_WIKI_OS/`, `KI_WIKI_MCP/`, `KI_WIKI_Dashboard/`
- Caddy-Config — gehört in `/opt/Proxy/Caddyfile` (separates Repo)
- Service-spezifische .env-Werte — gehören in das jeweilige Repo
