# Backups

Host script (no Odoo module). Backs up **database** + **filestore** (attachments/PDFs).  
Output: `backups/host/<timestamp>/` — **copy off the VPS** (local copies alone are not disaster recovery).

---

## Run a backup

From the repo root (stack must be running):

```bash
make backup
```

Creates:

```text
backups/host/2026-05-16_120000Z/
  db_mycompany.dump              # Postgres
  filestore_mycompany.tar.gz     # attachments
  manifest.txt
```

**Settings** (pick one place):

| Where | Example |
|-------|---------|
| **`.env`** (easiest) | See below — path depends on laptop vs VPS |
| **One-off command** | `RETENTION_DAYS=30 make backup` |
| **Cron line** | `RETENTION_DAYS=30 cd /opt/odoo && ./scripts/backup.sh` |

| Variable | Default |
|----------|---------|
| `BACKUP_ROOT` | `./backups/host` |
| `RETENTION_DAYS` | `14` |

**Laptop (local dev):** use a folder inside the repo — you cannot write to `/var/backups` without sudo:

```bash
BACKUP_ROOT=./backups/host
```

**Production VPS:** use a system path and create it once:

```bash
sudo mkdir -p /var/backups/odoo
sudo chown $USER:$USER /var/backups/odoo
```

Then in `.env`: `BACKUP_ROOT=/var/backups/odoo`

---

## Daily cron (VPS)

```cron
15 2 * * * cd /opt/odoo && ./scripts/backup.sh >> /var/log/odoo-backup.log 2>&1
```

Then sync elsewhere, e.g.:

```bash
rsync -avz /opt/odoo/backups/host/ user@backup-server:/backups/odoo/
```

---

## Restore (staging only)

Pick a folder: `BACKUP_DIR=backups/host/2026-05-16_120000Z`

```bash
source .env

# 1. Database
docker compose up -d db
docker compose exec -T db dropdb -U "$POSTGRES_USER" --if-exists "$ODOO_DB_NAME"
docker compose exec -T db createdb -U "$POSTGRES_USER" "$ODOO_DB_NAME"
docker compose exec -T db pg_restore -U "$POSTGRES_USER" -d "$ODOO_DB_NAME" \
  --no-owner --role="$POSTGRES_USER" < "$BACKUP_DIR/db_${ODOO_DB_NAME}.dump"

# 2. Filestore
docker compose up -d web
docker compose exec -T web rm -rf "/var/lib/odoo/.local/share/Odoo/filestore/${ODOO_DB_NAME}"
cat "$BACKUP_DIR/filestore_${ODOO_DB_NAME}.tar.gz" | \
  docker compose exec -T web tar -xzf - -C "/var/lib/odoo/.local/share/Odoo/filestore"

# 3. Start
make prod
```

Test login + open a PDF attachment. Do a restore drill **once per quarter**.

---

## Optional: Odoo backup apps

You can add a module like `auto_database_backup` for UI + Google Drive/SFTP. Not included here. If you use one: prefer small **dump** backups often, **zip** (DB+filestore) rarely, and store copies **off-server**.

---

## Problems

| Issue | Fix |
|-------|-----|
| Containers not running | `make prod` or `make dev` first |
| `ODOO_DB_NAME` missing | Set in `.env` (same name as `dbfilter`) |
| No filestore file | Normal on a new DB with no uploads yet |

See also: [README.md](../README.md) — Phase 3.9
