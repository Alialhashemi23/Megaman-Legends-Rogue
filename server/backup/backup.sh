#!/bin/sh
# Encrypted account-database backups: one now, then one a day.
#   PGHOST/PGUSER/PGPASSWORD/PGDATABASE  the database to dump
#   BACKUP_PASSPHRASE                    encryption passphrase (keep a copy OFF this machine)
#   BACKUP_DIR (default /backups)        point the volume at an off-machine/synced folder
# Keeps 7 daily and 4 weekly (Sunday) copies. `backup.sh --once` takes one and exits.
set -eu
DIR="${BACKUP_DIR:-/backups}"
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required}"
mkdir -p "$DIR/daily" "$DIR/weekly"

take() {
  stamp=$(date -u +%Y%m%d-%H%M%S)
  file="$DIR/daily/relic-$stamp.dump.enc"
  # Custom-format dump (includes the auth tables, sessions and roles), encrypted with AES-256.
  pg_dump --format=custom --no-owner | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass env:BACKUP_PASSPHRASE -out "$file.partial"
  mv "$file.partial" "$file"
  sha256sum "$file" | sed 's#  .*/#  #' > "$file.sha256"
  if [ "$(date -u +%u)" = "7" ]; then cp "$file" "$file.sha256" "$DIR/weekly/"; fi
  ls -1t "$DIR"/daily/*.dump.enc 2>/dev/null | tail -n +8 | while read -r old; do rm -f "$old" "$old.sha256"; done
  ls -1t "$DIR"/weekly/*.dump.enc 2>/dev/null | tail -n +5 | while read -r old; do rm -f "$old" "$old.sha256"; done
  echo "backup $(date -u +%FT%TZ): $file ($(wc -c < "$file") bytes)"
}

take
[ "${1:-}" = "--once" ] && exit 0
while sleep 86400; do take || echo "backup failed at $(date -u +%FT%TZ)" >&2; done
