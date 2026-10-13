#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
REGISTRY=${REGISTRY:-registry:5000}
TAG=${TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}

for service in postfix dovecot; do
  image=$REGISTRY/corpmail-$service
  docker build -t "$image:$TAG" -t "$image:latest" "$service"
  docker push -q "$image:$TAG"
  docker push -q "$image:latest"
done
echo "TAG=$TAG"
