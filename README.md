# Odoo Docker Production

A **minimal, production-ready** Docker Compose template for **Odoo 18** — from **local dev** on your laptop to **HTTPS production** on a VPS.

Built for **Odoo developers, implementers, freelancers, and small teams**.

**Video & tutorials:** [Risolto Limited on YouTube](https://www.youtube.com/@RisoltoLimited)

**Repo:** `git@github.com:moe1047/Odoo-Docker-Production.git`

---

## Table of contents

1. [What this stack does](#1-what-this-stack-does)
2. [What goes in Git vs on the server](#2-what-goes-in-git-vs-on-the-server)
3. [Prerequisites](#3-prerequisites)
4. [Phase 1 — Local development (your laptop)](#4-phase-1--local-development-your-laptop)
5. [Phase 2 — Test before production](#5-phase-2--test-before-production)
6. [Phase 3 — Deploy to production (VPS)](#6-phase-3--deploy-to-production-vps)
7. [Phase 4 — Updates after go-live](#7-phase-4--updates-after-go-live)
8. [Command reference](#8-command-reference)
9. [Sizing: workers & VPS](#9-sizing-workers--vps)
10. [Production go-live checklist](#10-production-go-live-checklist)
11. [Troubleshooting](#11-troubleshooting)
12. [Project layout](#12-project-layout)
13. [Backups](docs/BACKUPS.md)

---

## 1. What this stack does

```text
                    PRODUCTION                         LOCAL DEV
                    ----------                         ---------

User ──HTTPS──► Apache ──► Odoo (workers) ──► PostgreSQL    You ──HTTP──► Odoo (1 process) ──► PostgreSQL
         │              :8069      :5432                              :8069
         └── WebSocket /websocket                                   (no Apache)
```

| Service | Role |
|---------|------|
| **db** | PostgreSQL 15 — data lives in a Docker volume |
| **web** | Odoo 18 + your addons (`addons/`, `ent/`) |
| **apache** | HTTPS reverse proxy (production only, `make prod`) |

**Included by default:** multi-worker production config, `proxy_mode`, `dbfilter` lock-down, Postgres on `127.0.0.1` only, healthchecks, log rotation, WebSocket proxy, Ghostscript in the image, secrets via `.env` (not in compose).

| Mode | Command | URL |
|------|---------|-----|
| **Local dev** | `make dev` | http://127.0.0.1:8069 |
| **Production** | `make prod` | https://your-domain.com |

Dev runs in the **foreground** (logs in your terminal, **Ctrl+C** to stop). Production runs **detached** in the background.

**Ports:** `make dev` → open **:8069** directly. `make prod` → **:80 / :443** (Apache) → Odoo **:8069** inside Docker (not on the host). No certs yet: `cp apache/vhosts/odoo.http-only.conf.example apache/vhosts/odoo.conf`

---

## 2. What goes in Git vs on the server

| **Commit to GitHub** | **Never commit — server / secrets only** |
|----------------------|------------------------------------------|
| `docker-compose.yml`, `Dockerfile`, `Makefile` | `.env` (DB passwords) |
| `apache/`, `config/*.example` | `config/odoo.conf`, `config/odoo.dev.conf` |
| `scripts/setup.sh` | `certs/*.pem`, `certs/*.key` |
| | `.setup-secrets` (one-time password file) |
| | Docker volumes (database + filestore) |
| | Client addons (often a **separate private repo**) |

**Workflow:** push infra to Git → on VPS `git pull` → `make prod`. Passwords and data stay on the server.

---

## 3. Prerequisites

**On your laptop (local dev)**

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Mac/Windows) or Docker Engine (Linux)
- [Git](https://git-scm.com/)
- `make` (optional; you can use `./dev` and `./prod` instead)

**On the production VPS**

- Ubuntu 22.04 / 24.04 (or similar Linux), **4+ GB RAM** recommended for small teams
- Docker + Docker Compose plugin
- SSH access (keys, not passwords)
- A domain pointed to the server (or Cloudflare in front of it)
- Your Odoo addons (copy or `git clone` into `addons/`)

**Check VPS specs (on the server):**

```bash
nproc && free -h && df -h /
```

---

## 4. Phase 1 — Local development (your laptop)

Goal: run Odoo on **http://127.0.0.1:8069**, install modules, debug — **no HTTPS, no Apache**.

### Step 1.1 — Clone the repo

```bash
git clone git@github.com:moe1047/Odoo-Docker-Production.git
cd Odoo-Docker-Production
chmod +x dev prod scripts/setup.sh
```

### Step 1.2 — Generate config and passwords

```bash
make setup
```

This creates:

| File | Purpose |
|------|---------|
| `.env` | Postgres + Odoo DB connection passwords |
| `config/odoo.dev.conf` | Dev Odoo (`workers = 0`, `list_db = True`) |
| `config/odoo.conf` | Production Odoo (used later on VPS) |
| `.setup-secrets` | **Copy passwords to your password manager, then `rm .setup-secrets`** |

Edit `.env` if you want a different database name (default `ODOO_DB_NAME=mycompany`).

### Step 1.3 — Add your addons

```bash
cp -r /path/to/your/custom_addons/* ./addons/

# Enterprise (if licensed) — do not commit to public git
cp -r /path/to/enterprise/* ./ent/
```

Optional Python deps: uncomment `requirements.txt` lines in `Dockerfile`, then rebuild on next `make dev`.

### Step 1.4 — Start dev stack

```bash
make dev
```

- Logs appear in the terminal (Postgres + Odoo).
- Open **http://127.0.0.1:8069**
- Use the **database manager** to create a database (e.g. `mycompany`).
- Install **base**, then your custom modules from **Apps**.

### Step 1.5 — Stop dev

- Press **Ctrl+C** in the terminal running `make dev`.
- If containers are still up: `make down-dev`

### Step 1.6 — Day-to-day local work

| Task | Command |
|------|---------|
| Start | `make dev` |
| Stop | Ctrl+C, then `make down-dev` |
| Restart Odoo only | `./dev restart web` |
| Shell inside container | `docker compose exec web bash` |

---

## 5. Phase 2 — Test before production

Goal: confirm everything works **before** you point a real domain at a live server.

### Option A — Test on your laptop (production-like)

Simulate HTTPS + Apache locally:

1. Generate a self-signed cert (see `certs/README.md`).
2. Edit `apache/vhosts/odoo.conf` → `ServerName localhost`.
3. Ensure `config/odoo.conf` has `workers = 4` (or `2` on a small laptop).
4. Run:

```bash
make prod
```

Open **https://localhost** (accept browser warning for self-signed cert).

Stop: `make down`

### Option B — Staging VPS (recommended for client go-lives)

Use a **cheap second VPS** or a subdomain (`staging.client.com`):

1. Same steps as [Phase 3](#6-phase-3--deploy-to-production-vps) below.
2. Restore a **copy** of production DB + filestore if migrating an existing client.
3. Run through:

- [ ] Login, create/edit records  
- [ ] Your critical custom flows (payments, reports, prints)  
- [ ] Long report (balance sheet, PDF) — no 502 timeout  
- [ ] Notifications / bus (websocket)  
- [ ] Backup restore drill on staging  

### What to verify

| Area | Pass? |
|------|-------|
| Custom modules install without errors | |
| Accounting / operational flows | |
| File uploads (PDFs, attachments) | |
| Email (if configured) | |
| Performance acceptable with expected user count | |

Only then proceed to production DNS cutover.

---

## 6. Phase 3 — Deploy to production (VPS)

Goal: HTTPS site on a real server, data persistent, secrets safe.

### Step 3.1 — Prepare the VPS

```bash
# On the VPS (as root or sudo) — install Docker (Ubuntu example)
apt update && apt install -y docker.io docker-compose-plugin git make
usermod -aG docker $USER   # log out and back in
```

- Open firewall: **22** (SSH), **80**, **443** — not **5432** to the world.
- Point DNS: `odoo.yourclient.com` → VPS IP (or proxied through Cloudflare).

### Step 3.2 — Clone on the server (do not upload ZIPs by hand)

```bash
sudo mkdir -p /opt/odoo && sudo chown $USER:$USER /opt/odoo
cd /opt/odoo
git clone git@github.com:moe1047/Odoo-Docker-Production.git .
chmod +x dev prod scripts/setup.sh
```

Clone your **addons** (separate repo or copy):

```bash
git clone git@github.com:you/client-addons.git addons
# ent/ — copy enterprise addons securely if licensed
```

### Step 3.3 — Config and passwords on the server

```bash
make setup
```

Edit on the server:

| File | What to set |
|------|-------------|
| `.env` | `ODOO_DB_NAME=real_db_name` |
| `config/odoo.conf` | `dbfilter = ^real_db_name$` (must match `.env`) |
| `apache/vhosts/odoo.conf` | `ServerName odoo.yourclient.com` |

Copy passwords from `.setup-secrets` to your password manager, then:

```bash
rm .setup-secrets
```

### Step 3.4 — TLS / HTTPS (pick one path)

#### Path A — Cloudflare (no Certbot on VPS) — common today

1. Add site to Cloudflare, **proxy** the DNS record (orange cloud).
2. SSL/TLS → **Full (strict)** (not “Flexible”).
3. Cloudflare → **SSL** → **Origin Server** → create certificate.
4. Save to the VPS:

```bash
# fullchain.pem = origin cert + chain
# privkey.pem   = origin private key
cp origin.pem certs/fullchain.pem
cp origin.key certs/privkey.pem
chmod 600 certs/privkey.pem
```

5. `make prod`

Do **not** use Flexible SSL (HTTP to origin) for production ERP data.

#### Path B — Let’s Encrypt with Certbot on the VPS

See `certs/README.md`:

```bash
certbot certonly --standalone -d odoo.yourclient.com
cp /etc/letsencrypt/live/odoo.yourclient.com/fullchain.pem certs/
cp /etc/letsencrypt/live/odoo.yourclient.com/privkey.pem certs/
chmod 600 certs/privkey.pem
```

Renewal: cron + `docker compose restart apache` (or use certbot hooks).

#### Path C — Namecheap / other CDN

Same idea as Cloudflare: edge HTTPS for users, **Full (strict)** or origin certificate to the VPS — avoid HTTP-only origin for sensitive data.

### Step 3.5 — Tune production Odoo (on the VPS)

Edit `config/odoo.conf`:

```ini
workers = 4          # see §9 — scale to CPU/RAM
db_maxconn = 8
list_db = False
dbfilter = ^your_db_name$
```

Check VPS RAM before raising `workers`:

```bash
free -h && nproc
```

### Step 3.6 — Start production stack

```bash
make prod
```

Check containers:

```bash
make ps
make logs
```

### Step 3.7 — Create or restore the database

**New empty server:**

```bash
docker compose exec web odoo -d your_db_name -i base --stop-after-init
```

Then open `https://your-domain.com`, install your modules from Apps.

**Migrating from an old server:**

1. `pg_dump` from old Postgres → restore into new `db` container/volume.  
2. Copy **filestore** into Odoo’s volume (`/var/lib/odoo` inside `web`).  
3. Match `dbfilter` and `ODOO_DB_NAME` to the restored DB name.  

(Test restore on staging first.)

### Step 3.8 — Go-live checklist

See [§10 Production go-live checklist](#10-production-go-live-checklist).

### Step 3.9 — Backups (required)

Default: **host script** (no Odoo module).

```bash
make backup
# → backups/host/<timestamp>/db_<name>.dump + filestore_<name>.tar.gz
```

Schedule daily cron on the VPS and **copy `backups/host/` off-server** (rsync, S3, etc.).

Full guide (cron, restore drill, optional Odoo backup module): **[docs/BACKUPS.md](docs/BACKUPS.md)**

---

## 7. Phase 4 — Updates after go-live

### Infrastructure (compose, Dockerfile, Apache)

```bash
cd /opt/odoo
git pull
docker compose build web    # if Dockerfile changed
make prod
```

### Addon code only

```bash
cd /opt/odoo/addons && git pull
cd /opt/odoo && make restart
# Upgrade modules in Odoo: Apps → Upgrade
```

### Module upgrade (XML / data changes)

```bash
docker compose exec web odoo -d your_db_name -u your_module --stop-after-init
make restart
```

**Never** overwrite server `.env` or `config/odoo.conf` with `git pull` — they are gitignored and live only on the server.

---

## 8. Command reference

| Command | Description |
|---------|-------------|
| `make setup` | First-time: `.env`, passwords, odoo configs |
| `make dev` | Local dev (foreground, port 8069) |
| `make prod` | Production (detached, Apache + HTTPS) |
| `make down-dev` | Stop dev stack |
| `make down` | Stop production stack |
| `make logs` | Follow production Odoo logs |
| `make logs-dev` | Follow dev logs (if running detached) |
| `make restart` | Restart production Odoo |
| `make ps` | Container status |
| `make shell` | Bash inside production Odoo container |
| `make backup` | DB dump + filestore → `backups/host/` |

Shortcuts: `./dev`, `./prod` (same as above; `./dev down`, etc.)

---

## 9. Sizing: workers & VPS

> How many people click Odoo **at the same time** during peak hour?

| Peak concurrent users | `workers` (4–8 vCPU VPS) |
|----------------------|--------------------------|
| 1–10 | 2–4 |
| 10–40 | 4–6 |
| 40+ | 6–8 (watch RAM) |

**Rule of thumb:** `workers ≈ (CPU cores × 2) + 1`, capped by RAM.

**Memory:** `workers × limit_memory_hard + ~3 GB` (Postgres + OS) must fit in VPS RAM.

**Connections:** `db_maxconn = 8` — keep `(workers + crons) × db_maxconn` below Postgres `max_connections` (100).

**Local dev:** always `workers = 0` in `config/odoo.dev.conf` — never on public production.

---

## 10. Production go-live checklist

### Performance
- [ ] `workers > 0` in `config/odoo.conf`
- [ ] `db_maxconn = 8` (or adjusted for your worker count)
- [ ] VPS RAM headroom (~30% free under normal load)

### Security
- [ ] Strong passwords (`make setup`), `.setup-secrets` deleted
- [ ] `list_db = False`, `dbfilter` set
- [ ] Postgres not public (compose uses `127.0.0.1:5432`)
- [ ] HTTPS Full (strict) or valid origin certs
- [ ] SSH keys only on VPS

### Recovery
- [ ] `make backup` scheduled daily (see [docs/BACKUPS.md](docs/BACKUPS.md))
- [ ] Backup copies stored off-server
- [ ] Restore tested on staging

### Functional
- [ ] Critical flows tested on staging
- [ ] WebSocket / notifications work behind CDN (if used)

---

## 11. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `env file .env not found` | Run `make setup` |
| `could not translate host name "db"` | `make down-dev && make dev` (network fix); ensure both services on `odoo` network |
| 502 on long reports | Increase Apache `ProxyTimeout` / CDN timeout |
| `remaining connection slots` | Lower `db_maxconn` or raise Postgres `max_connections` |
| Slow with many users | `workers = 0` on production — fix `odoo.conf` |
| Redirects to `http://` | `proxy_mode = True` + `X-Forwarded-Proto` in Apache |
| Bus / chat not working | WebSocket proxy + CDN WebSocket support |

```bash
make ps
make logs
curl -k https://localhost/web/health   # on server
```

---

## 12. Project layout

```text
.
├── Makefile
├── dev / prod                 # shortcuts
├── docker-compose.yml         # db + web + apache (profile: production)
├── docker-compose.dev.yml     # dev: port 8069, odoo.dev.conf
├── Dockerfile
├── .env.example
├── config/
│   ├── odoo.conf.example      → odoo.conf (gitignored)
│   └── odoo.dev.conf.example  → odoo.dev.conf (gitignored)
├── apache/
├── certs/                     # TLS (gitignored keys)
├── addons/                    # your modules
├── ent/                       # enterprise (gitignored)
├── postgres/postgresql.conf.example
├── docs/BACKUPS.md           # host backup + restore
└── scripts/
    ├── setup.sh
    └── backup.sh             # make backup
```

---

## What this template skips (on purpose)

- Kubernetes / Swarm  
- Odoo UI backup module (use `docs/BACKUPS.md` host script instead; module optional)  
- Multi-tenant / multi-database hosting  
- Nginx (Apache works; Nginx swap is optional)  

---

## License

MIT — use freely in client projects.

**Subscribe:** [Risolto Limited on YouTube](https://www.youtube.com/@RisoltoLimited)

**Star the repo** if it saved you a weekend.
