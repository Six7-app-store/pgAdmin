#!/usr/bin/env bash
# Richtet pgAdmin und die Beispieldatenbank beim ersten Start der Team-VM
# ein. cloud-init hat vorher abgelegt:
#
#   /opt/pgadmin/servers.json       Servereintrag für die Pagila-Datenbank
#   /etc/pgadmin-team/account       E-Mail und Passwort des Teamkontos
#
# Bricht das Skript ab, scheitert cloud-final.service, und der App Store
# meldet das Deployment als fehlgeschlagen (ADR 0011 im deployment-Repo).
set -euo pipefail

log() { echo "[pgadmin] $*"; }

ACCOUNT_FILE=/etc/pgadmin-team/account
PAGILA_URL=https://raw.githubusercontent.com/devrimgunduz/pagila/master

export DEBIAN_FRONTEND=noninteractive
export HOME=/root

# Beim ersten Boot hält oft apt-daily die dpkg-Sperre; warten statt scheitern.
apt_get() { apt-get -y -q -o DPkg::Lock::Timeout=600 "$@"; }

log "PostgreSQL installieren"
apt_get update
apt_get install --no-install-recommends ca-certificates curl gnupg lsb-release postgresql

log "pgAdmin aus dem Paketarchiv von pgadmin.org installieren"
curl -fsSL https://www.pgadmin.org/static/packages_pgadmin_org.pub \
  | gpg --batch --yes --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg
echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" \
  >/etc/apt/sources.list.d/pgadmin4.list
apt_get update
apt_get install pgadmin4-web

log "Beispieldatenbank Pagila laden"
systemctl enable --now postgresql
psql_postgres() { runuser -u postgres -- psql -v ON_ERROR_STOP=1 -q "$@"; }
psql_postgres -c "CREATE DATABASE pagila;"
psql_postgres -c "CREATE USER pagila_user WITH PASSWORD 'pagila';"
psql_postgres -c "GRANT ALL PRIVILEGES ON DATABASE pagila TO pagila_user;"

tmp=$(mktemp -d)
curl -fsSL --retry 3 "$PAGILA_URL/pagila-schema.sql" -o "$tmp/schema.sql"
curl -fsSL --retry 3 "$PAGILA_URL/pagila-data.sql" -o "$tmp/data.sql"
chmod 755 "$tmp"
chmod 644 "$tmp"/*.sql
psql_postgres -d pagila -f "$tmp/schema.sql" >/dev/null
psql_postgres -d pagila -f "$tmp/data.sql" >/dev/null
rm -rf "$tmp"

psql_postgres -d pagila -c "GRANT USAGE ON SCHEMA public TO pagila_user;"
psql_postgres -d pagila -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO pagila_user;"
psql_postgres -d pagila -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO pagila_user;"

log "pgAdmin im Webmodus einrichten"
{ read -r email; read -r password; } <"$ACCOUNT_FILE"
# setup-web.sh legt das erste Konto aus diesen Variablen an; das ist das
# Konto des Teams.
PGADMIN_SETUP_EMAIL="$email" PGADMIN_SETUP_PASSWORD="$password" \
  /usr/pgadmin4/bin/setup-web.sh --yes
rm -rf /etc/pgadmin-team

/usr/pgadmin4/venv/bin/python3 /usr/pgadmin4/web/setup.py \
  load-servers /opt/pgadmin/servers.json --user "$email"
# setup.py lief als root; Datenbank und Log müssen dem Webserver gehören
chown -R www-data:www-data /var/lib/pgadmin /var/log/pgadmin
systemctl restart apache2

# Erst fertig melden, wenn die Anmeldeseite antwortet
for _ in $(seq 1 60); do
  if curl -sf -o /dev/null http://localhost/pgadmin4/login; then
    log "pgAdmin erreichbar"
    exit 0
  fi
  sleep 5
done

log "pgAdmin antwortet nicht auf http://localhost/pgadmin4/login"
systemctl status apache2 --no-pager || true
exit 1
