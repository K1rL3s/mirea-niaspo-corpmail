#!/bin/sh
set -eu

STACK=${STACK:-corpmail}
VOLUME=${VOLUME:-corpmail}

healed() {
  gluster volume heal "$VOLUME" info | awk '/^Number of entries:/ { s += $4 } END { exit (s > 0) }'
}

single() {
  echo "single: the other nodes must be powered off, otherwise the copies of the data diverge (split-brain)"
  addr=$(docker info --format '{{.Swarm.NodeAddr}}')
  docker swarm init --force-new-cluster --advertise-addr "$addr" >/dev/null
  gluster --mode=script volume set "$VOLUME" cluster.quorum-type none >/dev/null
  restart dovecot mariadb redis
  docker exec "$(docker ps -q -f "name=${STACK}_postfix" | head -1)" postqueue -f
  echo "on each returning node: sh -s join $addr $(docker swarm join-token -q manager) < scripts/recover.sh"
}

join() {
  docker swarm leave --force >/dev/null 2>&1 || true
  docker swarm join --token "$2" "$1:2377"
}

finish() {
  until healed; do sleep 5; done
  gluster --mode=script volume set "$VOLUME" cluster.quorum-type auto >/dev/null
  for id in $(docker node ls --format '{{.ID}} {{.Status}} {{.ManagerStatus}}' | awk '!($2 == "Ready" && ($3 == "Leader" || $3 == "Reachable")) { print $1 }'); do
    docker node demote "$id" >/dev/null 2>&1 || true
    docker node rm --force "$id" >/dev/null
  done
  restart roundcube rspamd
  docker node ls
}

restart() {
  for s in "$@"; do docker service update --force --detach=false "${STACK}_$s" >/dev/null; done
}

case "${1:-}" in
  single) single ;;
  join) join "$2" "$3" ;;
  finish) finish ;;
  *) echo "usage: recover.sh single | join <manager-address> <token> | finish"; exit 2 ;;
esac
