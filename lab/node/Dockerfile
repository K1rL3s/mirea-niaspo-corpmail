FROM docker:28-dind@sha256:2a232a42256f70d78e3cc5d2b5d6b3276710a0de0596c145f627ecfae90282ac AS dind

FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

ARG DOCKER_VERSION=5:28.5.2-1~debian.13~trixie

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl iptables procps glusterfs-server glusterfs-client \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends "docker-ce=$DOCKER_VERSION" "docker-ce-cli=$DOCKER_VERSION" containerd.io \
 && rm -rf /var/lib/apt/lists/*

COPY --from=dind /usr/local/bin/dind /usr/local/bin/dind
COPY entrypoint.sh /entrypoint.sh

VOLUME /var/lib/docker
EXPOSE 2375
ENTRYPOINT ["/entrypoint.sh"]
