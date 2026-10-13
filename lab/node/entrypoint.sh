#!/bin/sh
set -eu

mkdir -p /mnt/gluster /data/brick
rm -rf /var/run/docker /var/run/docker.pid /var/run/glusterd.pid
glusterd

if gluster volume info corpmail >/dev/null 2>&1; then
  for _ in $(seq 30); do
    mountpoint -q /mnt/gluster && break
    mount -t glusterfs localhost:/corpmail /mnt/gluster 2>/dev/null || sleep 2
  done
fi

exec dind dockerd "$@"
