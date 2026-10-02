#!/bin/sh
set -eu

NET=corpmail-lab
IMAGE=docker:28-dind
NODES="manager-01 worker-01 worker-02"

on() { n=$1; shift; docker exec "$n" docker "$@"; }

up() {
  docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
  docker run -d --name registry --network "$NET" --restart unless-stopped registry:2 >/dev/null
  for n in $NODES; do
    ports=""
    if [ "$n" = manager-01 ]; then
      ports="-p 127.0.0.1:2375:2375 -p 127.0.0.1:8080:80 -p 127.0.0.1:8443:443 -p 127.0.0.1:2525:25 -p 127.0.0.1:5587:587 -p 127.0.0.1:1143:143 -p 127.0.0.1:1993:993"
    fi
    docker run -d --privileged --name "$n" --hostname "$n" --network "$NET" \
      -e DOCKER_TLS_CERTDIR= $ports -v "$n-data:/var/lib/docker" \
      "$IMAGE" --insecure-registry registry:5000 --host tcp://0.0.0.0:2375 --host unix:///var/run/docker.sock --tls=false >/dev/null
  done
  for n in $NODES; do
    until docker exec "$n" docker info >/dev/null 2>&1; do sleep 1; done
  done
  addr=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" manager-01)
  on manager-01 swarm init --advertise-addr "$addr" >/dev/null
  token=$(on manager-01 swarm join-token -q worker)
  for n in worker-01 worker-02; do
    on "$n" swarm join --token "$token" "$addr:2377" >/dev/null
  done
  on manager-01 node update --label-add db=true manager-01 >/dev/null
  on manager-01 node update --label-add mail=true worker-01 >/dev/null
  on manager-01 node ls
}

down() {
  docker rm -f $NODES registry >/dev/null 2>&1 || true
  for n in $NODES; do docker volume rm -f "$n-data" >/dev/null 2>&1 || true; done
  docker network rm "$NET" >/dev/null 2>&1 || true
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  *) echo "usage: $0 up|down"; exit 2 ;;
esac
