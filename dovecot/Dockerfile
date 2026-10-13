FROM alpine:3.21@sha256:ce64758a109eb420d874a118f87920e625e12d3634e03b4a5573fd9f6e5d3507

RUN apk add --no-cache dovecot dovecot-lmtpd openssl netcat-openbsd \
 && addgroup -S -g 5000 vmail \
 && adduser -S -D -H -u 5000 -G vmail -h /var/vmail vmail \
 && mkdir -p /var/vmail /etc/dovecot/tls \
 && chown vmail:vmail /var/vmail

COPY dovecot.conf /etc/dovecot/dovecot.conf
COPY entrypoint.sh /entrypoint.sh

VOLUME /var/vmail
EXPOSE 24 143 993 12345
HEALTHCHECK --interval=15s --timeout=5s --start-period=15s \
  CMD ["sh", "-c", "nc -z 127.0.0.1 143 && nc -z 127.0.0.1 24"]
ENTRYPOINT ["/entrypoint.sh"]
