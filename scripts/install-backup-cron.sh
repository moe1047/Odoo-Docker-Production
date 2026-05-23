#!/usr/bin/env bash
# Install or remove a daily cron job that runs scripts/backup.sh.
# Usage (from repo root):
#   ./scripts/install-backup-cron.sh          # install (default 02:15 daily)
#   ./scripts/install-backup-cron.sh --remove
#   BACKUP_CRON_SCHEDULE='0 3 * * *' ./scripts/install-backup-cron.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MARKER="odoo-host-backup"
SCHEDULE="${BACKUP_CRON_SCHEDULE:-15 2 * * *}"
REMOVE=false

for arg in "$@"; do
  case "$arg" in
    --remove|-r) REMOVE=true ;;
    -h|--help)
      echo "Usage: $0 [--remove]"
      echo "  BACKUP_CRON_SCHEDULE='15 2 * * *'  (default: 02:15 daily)"
      echo "  BACKUP_CRON_LOG=/path/to/log        (default: see script)"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$REMOVE" == true ]]; then
  if crontab -l 2>/dev/null | grep -q "$MARKER"; then
    crontab -l 2>/dev/null | grep -v "$MARKER" | crontab -
    echo "Removed backup cron job."
  else
    echo "No backup cron job found (marker: $MARKER)."
  fi
  exit 0
fi

if [[ ! -f .env ]]; then
  echo "error: .env not found — run make setup first" >&2
  exit 1
fi

if [[ "$(uname -s)" == Darwin ]]; then
  LOG="${BACKUP_CRON_LOG:-${HOME}/Library/Logs/odoo-backup.log}"
  echo "note: macOS detected — cron works, but auto-backup is usually for the production VPS."
else
  LOG="${BACKUP_CRON_LOG:-/var/log/odoo-backup.log}"
fi

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
touch "$LOG" 2>/dev/null || {
  echo "error: cannot write log file: $LOG" >&2
  echo "  Set BACKUP_CRON_LOG to a path you own, e.g. ${ROOT}/backups/backup.log" >&2
  exit 1
}

JOB="${SCHEDULE} cd ${ROOT} && ./scripts/backup.sh >> ${LOG} 2>&1 # ${MARKER}"

EXISTING="$(crontab -l 2>/dev/null || true)"
if echo "$EXISTING" | grep -q "$MARKER"; then
  UPDATED="$(echo "$EXISTING" | grep -v "$MARKER"; echo "$JOB")"
  echo "$UPDATED" | crontab -
  echo "Updated backup cron job."
else
  { echo "$EXISTING"; echo "$JOB"; } | crontab -
  echo "Installed backup cron job."
fi

echo "  Schedule:  ${SCHEDULE}"
echo "  Log:       ${LOG}"
echo "  Repo:      ${ROOT}"
echo ""
echo "Ensure .env has BACKUP_ROOT (VPS: /var/backups/odoo) and stack runs via make prod."
echo "List jobs:   crontab -l"
echo "Remove:      ./scripts/install-backup-cron.sh --remove"
