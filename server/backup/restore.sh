#!/bin/sh
# Restore an encrypted backup into a database (which should be EMPTY):
#   restore.sh /backups/daily/relic-YYYYMMDD-HHMMSS.dump.enc
# Uses PGHOST/PGUSER/PGPASSWORD/PGDATABASE for the target and BACKUP_PASSPHRASE to decrypt.
set -eu
file="${1:?usage: restore.sh <backup file>}"
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE is required}"
if [ -f "$file.sha256" ]; then
  (cd "$(dirname "$file")" && sha256sum -c "$(basename "$file").sha256") || { echo "checksum mismatch: $file" >&2; exit 1; }
fi
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSPHRASE -in "$file" | pg_restore --no-owner --exit-on-error --dbname="$PGDATABASE"
echo "restored $file into $PGDATABASE"
