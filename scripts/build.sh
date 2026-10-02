#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
REGISTRY=${REGISTRY:-registry:5000}
TAG=${TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}

for service in postfix dovecot; do
  docker build -t "$REGISTRY/corpmail-$service:$TAG" -t "$REGISTRY/corpmail-$service:latest" "$service"
  docker push -q "$REGISTRY/corpmail-$service:$TAG"
  docker push -q "$REGISTRY/corpmail-$service:latest"
done
echo "TAG=$TAG"
