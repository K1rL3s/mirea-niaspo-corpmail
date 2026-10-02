#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
STACK=${STACK:-corpmail}
TIMEOUT=${TIMEOUT:-600}

[ -s secrets/dovecot_users ] || ./scripts/make-secrets.sh

set -a
# shellcheck source=/dev/null
. ./secrets/stack.env
set +a
export CONFIG_VERSION SECRETS_VERSION
CONFIG_VERSION=$(cat roundcube/tls.php rspamd/* secrets/rspamd-worker-controller.inc | cksum | cut -d' ' -f1)
SECRETS_VERSION=$(cat secrets/dovecot_users secrets/mariadb_root_password secrets/roundcube_db_password secrets/roundcube_des_key | cksum | cut -d' ' -f1)

docker stack deploy --with-registry-auth --prune --detach=true -c stack.yml "$STACK"

echo "waiting for all services of $STACK to converge"
deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  pending=$(docker stack services "$STACK" --format '{{.Name}} {{.Replicas}}' \
    | awk '{ split($2, r, "/"); if (r[1] != r[2]) print $1 " " $2 }')
  for service in $(docker stack services "$STACK" --format '{{.Name}}'); do
    state=$(docker service inspect "$service" --format '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{end}}')
    case "$state" in updating|rollback_started) pending="$pending $service:$state" ;; esac
  done
  [ -z "$(echo "$pending" | tr -d ' ')" ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "timeout, not converged:"; echo "$pending"
    docker stack ps "$STACK" --no-trunc --filter desired-state=running | head -40
    exit 1
  fi
  sleep 5
done
docker stack services "$STACK"
