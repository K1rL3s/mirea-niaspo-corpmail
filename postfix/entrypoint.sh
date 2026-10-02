#!/bin/sh
set -e

postconf -e "myhostname = ${MAIL_HOSTNAME:-mail.corp.local}" \
            "mydomain = ${MAIL_DOMAIN:-corp.local}" \
            "virtual_mailbox_domains = ${MAIL_DOMAIN:-corp.local}" \
            "mynetworks = 127.0.0.0/8 ${TRUSTED_NETWORKS:-}"

mkdir -p /etc/postfix/tls
if [ ! -s /etc/postfix/tls/cert.pem ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
    -subj "/CN=$(postconf -h myhostname)" \
    -keyout /etc/postfix/tls/key.pem -out /etc/postfix/tls/cert.pem 2>/dev/null
fi

newaliases
exec postfix start-fg
