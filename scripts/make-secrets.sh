#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
DOMAIN=${MAIL_DOMAIN:-corp.local}
DIR=secrets
mkdir -p "$DIR"
chmod 700 "$DIR"

random() { openssl rand -base64 18 | tr -d '/+=' | cut -c1-20; }

[ -s "$DIR/credentials.env" ] || {
  echo "ALICE_PASSWORD=$(random)"
  echo "BOB_PASSWORD=$(random)"
  echo "ADMIN_PASSWORD=$(random)"
} > "$DIR/credentials.env"
# shellcheck source=/dev/null
. "./$DIR/credentials.env"

[ -s "$DIR/dovecot_users" ] || for user in alice:"$ALICE_PASSWORD" bob:"$BOB_PASSWORD" postmaster:"$ADMIN_PASSWORD"; do
  name=${user%%:*}
  echo "$name@$DOMAIN:{SHA512-CRYPT}$(openssl passwd -6 "${user#*:}")::::::"
done > "$DIR/dovecot_users"

[ -s "$DIR/mariadb_root_password" ] || random | tr -d '\n' > "$DIR/mariadb_root_password"
[ -s "$DIR/roundcube_db_password" ] || random | tr -d '\n' > "$DIR/roundcube_db_password"
[ -s "$DIR/roundcube_des_key" ] || openssl rand -hex 12 | tr -d '\n' > "$DIR/roundcube_des_key"

hash=$(docker run --rm -q rspamd/rspamd:4.2.1 rspamadm pw -p "$ADMIN_PASSWORD")
printf 'password = "%s";\nenable_password = "%s";\nallow_file_and_shm_inputs = false;\n' "$hash" "$hash" > "$DIR/rspamd-worker-controller.inc"

echo "TRAEFIK_DASHBOARD_USERS='admin:$(openssl passwd -apr1 "$ADMIN_PASSWORD")'" > "$DIR/stack.env"

chmod 600 "$DIR"/*
echo "secrets written to $DIR/, user passwords in $DIR/credentials.env"
