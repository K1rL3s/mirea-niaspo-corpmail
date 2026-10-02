FROM alpine:3.21

RUN apk add --no-cache postfix ca-certificates openssl netcat-openbsd

COPY main.cf master.cf /etc/postfix/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && postconf -e "mail_spool_directory = /var/mail"

EXPOSE 25 587
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD ["sh", "-c", "nc -z 127.0.0.1 25 && nc -z 127.0.0.1 587"]
ENTRYPOINT ["/entrypoint.sh"]
