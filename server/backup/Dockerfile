# Encrypted PostgreSQL backups for Relic Diver accounts (docker-compose.accounts.yml).
FROM postgres:17.11-alpine
RUN apk add --no-cache openssl
COPY server/backup/backup.sh server/backup/restore.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/restore.sh
ENTRYPOINT ["/usr/local/bin/backup.sh"]
