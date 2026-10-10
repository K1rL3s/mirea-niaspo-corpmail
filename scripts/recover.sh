#!/bin/sh
set -eu

STACK=${STACK:-corpmail}
VOLUME=${VOLUME:-corpmail}

heal_entries() {
  gluster volume heal "$VOLUME" info | awk '/^Number of entries:/ { if ($4 ~ /^[0-9]+$/) s += $4 } END { print s + 0 }'
}

single() {
  echo "single: the other nodes must be powered off, otherwise the copies of the data diverge (split-brain)"
  addr=$(docker info --format '{{.Swarm.NodeAddr}}')
  docker swarm init --force-new-cluster --advertise-addr "$addr" >/dev/null
  gluster --mode=script volume set "$VOLUME" cluster.quorum-type none >/dev/null
  for s in dovecot mariadb redis; do
    docker service update --force --detach=false "${STACK}_$s" >/dev/null
  done
  docker exec "$(docker ps -q -f "name=${STACK}_postfix" | head -1)" postqueue -f
  echo "on each returning node: sh -s join $addr $(docker swarm join-token -q manager) < scripts/recover.sh"
}

join() {
  docker swarm leave --force >/dev/null 2>&1 || true
  docker swarm join --token "$2" "$1:2377"
}

finish() {
  until [ "$(heal_entries)" -eq 0 ]; do sleep 5; done
  gluster --mode=script volume set "$VOLUME" cluster.quorum-type auto >/dev/null
  for id in $(docker node ls --format '{{.ID}} {{.Status}}' | awk '$2 == "Down" { print $1 }'); do
    docker node demote "$id" >/dev/null 2>&1 || true
    docker node rm --force "$id" >/dev/null
  done
  for s in roundcube rspamd; do
    docker service update --force --detach=false "${STACK}_$s" >/dev/null
  done
  docker node ls
}

case "${1:-}" in
  single) single ;;
  join) join "$2" "$3" ;;
  finish) finish ;;
  *) echo "usage: recover.sh single | join <manager-address> <token> | finish"; exit 2 ;;
esac
