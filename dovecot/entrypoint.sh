#!/bin/sh
set -e

if [ ! -s /etc/dovecot/tls/cert.pem ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
    -subj "/CN=${MAIL_HOSTNAME:-mail.corp.local}" \
    -keyout /etc/dovecot/tls/key.pem -out /etc/dovecot/tls/cert.pem 2>/dev/null
fi

chown vmail:vmail /var/vmail
exec dovecot -F
