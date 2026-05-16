#!/usr/bin/env bash
# Host backup: PostgreSQL dump + Odoo filestore (default for this template).
# Run from repo root on the VPS (cron-friendly).
#
# Usage:
#   ./scripts/backup.sh
#   BACKUP_ROOT=/var/backups/odoo RETENTION_DAYS=30 ./scripts/backup.sh
#
# Requires: running db + web containers, .env with ODOO_DB_NAME
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COMPOSE=(docker compose -f docker-compose.yml)

if [[ ! -f .env ]]; then
  echo "error: .env not found — run make setup first" >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a && source .env && set +a

: "${POSTGRES_USER:=odoo}"
: "${ODOO_DB_NAME:?ODOO_DB_NAME must be set in .env}"
BACKUP_ROOT="${BACKUP_ROOT:-${ROOT}/backups/host}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
STAMP="$(date -u +"%Y-%m-%d_%H%M%SZ")"
DEST="${BACKUP_ROOT}/${STAMP}"

if ! "${COMPOSE[@]}" ps --status running --services 2>/dev/null | grep -qx 'db'; then
  echo "error: db container is not running — start the stack first (make prod or make dev)" >&2
  exit 1
fi

if ! "${COMPOSE[@]}" ps --status running --services 2>/dev/null | grep -qx 'web'; then
  echo "error: web container is not running" >&2
  exit 1
fi

if ! mkdir -p "$DEST" 2>/dev/null; then
  echo "error: cannot create backup folder: $DEST" >&2
  echo "" >&2
  echo "  On your laptop, use a path you own in .env:" >&2
  echo "    BACKUP_ROOT=./backups/host" >&2
  echo "" >&2
  echo "  On a VPS, create the folder once:" >&2
  echo "    sudo mkdir -p $BACKUP_ROOT && sudo chown \$(whoami):\$(id -gn) $BACKUP_ROOT" >&2
  exit 1
fi

echo "==> Backup destination: $DEST"
echo "==> Database: $ODOO_DB_NAME"

echo "==> Dumping PostgreSQL (custom format, compressed)..."
"${COMPOSE[@]}" exec -T db pg_dump \
  -U "$POSTGRES_USER" \
  -Fc \
  --no-owner \
  --no-acl \
  "$ODOO_DB_NAME" > "${DEST}/db_${ODOO_DB_NAME}.dump"

FILESTORE_PATH="/var/lib/odoo/.local/share/Odoo/filestore/${ODOO_DB_NAME}"
echo "==> Archiving filestore: ${FILESTORE_PATH}"
if "${COMPOSE[@]}" exec -T web test -d "$FILESTORE_PATH"; then
  "${COMPOSE[@]}" exec -T web tar -czf - -C "/var/lib/odoo/.local/share/Odoo/filestore" "$ODOO_DB_NAME" \
    > "${DEST}/filestore_${ODOO_DB_NAME}.tar.gz"
else
  echo "warn: filestore path not found — skipping filestore archive (empty DB?)" >&2
  touch "${DEST}/filestore_${ODOO_DB_NAME}.MISSING"
fi

# Optional: Odoo config snapshot (no secrets from .env)
if [[ -f config/odoo.conf ]]; then
  cp config/odoo.conf "${DEST}/odoo.conf.snapshot"
fi

{
  echo "timestamp_utc=${STAMP}"
  echo "database=${ODOO_DB_NAME}"
  echo "postgres_user=${POSTGRES_USER}"
  echo "hostname=$(hostname)"
  echo "compose_project=$(basename "$ROOT")"
  ls -lh "${DEST}"
} > "${DEST}/manifest.txt"

echo "==> Pruning backups older than ${RETENTION_DAYS} days in ${BACKUP_ROOT}..."
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime "+${RETENTION_DAYS}" -print -exec rm -rf {} + 2>/dev/null || true

echo ""
echo "Done."
echo "  DB:        ${DEST}/db_${ODOO_DB_NAME}.dump"
echo "  Filestore: ${DEST}/filestore_${ODOO_DB_NAME}.tar.gz"
echo ""
echo "Copy this folder off-server (rsync, S3, another VPS). See docs/BACKUPS.md"
