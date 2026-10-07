#!/bin/sh
set -eu

NET=corpmail-lab
IMAGE=corpmail-lab-node
NODES="node-01 node-02 node-03"

on() { n=$1; shift; docker exec "$n" docker "$@"; }
gl() { n=$1; shift; docker exec "$n" gluster --mode=script "$@"; }

ports() {
  i=$1
  echo "-p 127.0.0.1:$((2375 + i)):2375 -p 127.0.0.1:$((8080 + i)):80 -p 127.0.0.1:$((8443 + i)):443 -p 127.0.0.1:$((2525 + i)):25 -p 127.0.0.1:$((5587 + i)):587 -p 127.0.0.1:$((1143 + i)):143 -p 127.0.0.1:$((1993 + i)):993"
}

up() {
  docker build -q -t "$IMAGE" "$(dirname "$0")/node" >/dev/null
  docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
  docker run -d --name registry --network "$NET" --restart unless-stopped registry:2@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373 >/dev/null
  i=0
  for n in $NODES; do
    # shellcheck disable=SC2046
    docker run -d --privileged --name "$n" --hostname "$n" --network "$NET" $(ports "$i") \
      -v "$n-data:/var/lib/docker" -v "$n-brick:/data/brick" \
      "$IMAGE" --insecure-registry registry:5000 --host tcp://0.0.0.0:2375 --host unix:///var/run/docker.sock --tls=false >/dev/null
    i=$((i + 1))
  done
  for n in $NODES; do
    until docker exec "$n" docker info >/dev/null 2>&1; do sleep 1; done
  done
  addr=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" node-01)
  on node-01 swarm init --advertise-addr "$addr" >/dev/null
  token=$(on node-01 swarm join-token -q manager)
  for n in node-02 node-03; do
    on "$n" swarm join --token "$token" "$addr:2377" >/dev/null
  done
  for n in node-02 node-03; do
    gl node-01 peer probe "$n" >/dev/null
  done
  until [ "$(gl node-01 pool list | grep -c Connected)" -eq 3 ]; do sleep 1; done
  gl node-01 volume create corpmail replica 3 \
    node-01:/data/brick/corpmail node-02:/data/brick/corpmail node-03:/data/brick/corpmail force >/dev/null
  gl node-01 volume start corpmail >/dev/null
  for n in $NODES; do
    docker exec "$n" mount -t glusterfs localhost:/corpmail /mnt/gluster
  done
  docker exec node-01 mkdir -p /mnt/gluster/vmail /mnt/gluster/redis /mnt/gluster/mariadb
  on node-01 node ls
  gl node-01 volume info corpmail
}

down() {
  docker rm -f $NODES registry >/dev/null 2>&1 || true
  for n in $NODES; do docker volume rm -f "$n-data" "$n-brick" >/dev/null 2>&1 || true; done
  docker network rm "$NET" >/dev/null 2>&1 || true
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  *) echo "usage: $0 up|down"; exit 2 ;;
esac
