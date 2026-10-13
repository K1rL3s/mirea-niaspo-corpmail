#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
mkdir -p secrets
chmod 700 secrets
cd secrets

random() { openssl rand -base64 18 | tr -d '/+=' | cut -c1-20; }

[ -s credentials.env ] || {
  echo "ALICE_PASSWORD=$(random)"
  echo "BOB_PASSWORD=$(random)"
  echo "ADMIN_PASSWORD=$(random)"
} > credentials.env
# shellcheck source=/dev/null
. ./credentials.env

[ -s dovecot_users ] || for user in alice:"$ALICE_PASSWORD" bob:"$BOB_PASSWORD" postmaster:"$ADMIN_PASSWORD"; do
  echo "${user%%:*}@${MAIL_DOMAIN:-corp.local}:{SHA512-CRYPT}$(openssl passwd -6 "${user#*:}")::::::"
done > dovecot_users

[ -s mariadb_root_password ] || random | tr -d '\n' > mariadb_root_password
[ -s roundcube_db_password ] || random | tr -d '\n' > roundcube_db_password
[ -s roundcube_des_key ] || openssl rand -hex 12 | tr -d '\n' > roundcube_des_key

hash=$(docker run --rm -q rspamd/rspamd:4.2.1@sha256:dfb8176e560c178faa4e18ebf9c9b43d0d60c2d2fa03f748c34a27e5c3418dc4 rspamadm pw -p "$ADMIN_PASSWORD")
printf 'password = "%s";\nenable_password = "%s";\nallow_file_and_shm_inputs = false;\n' "$hash" "$hash" > rspamd-worker-controller.inc

echo "TRAEFIK_DASHBOARD_USERS='admin:$(openssl passwd -apr1 "$ADMIN_PASSWORD")'" > stack.env

chmod 600 ./*
echo "secrets written to secrets/, user passwords in secrets/credentials.env"
