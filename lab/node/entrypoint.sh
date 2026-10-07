#!/bin/sh
set -eu

mkdir -p /mnt/gluster /data/brick
rm -rf /var/run/docker /var/run/docker.pid /var/run/glusterd.pid
glusterd

if gluster volume info corpmail >/dev/null 2>&1; then
  i=0
  until mountpoint -q /mnt/gluster || [ "$i" -ge 30 ]; do
    mount -t glusterfs localhost:/corpmail /mnt/gluster 2>/dev/null || sleep 2
    i=$((i + 1))
  done
fi

exec dind dockerd "$@"
