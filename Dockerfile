FROM caddy:2-alpine

RUN apk add --no-cache ca-certificates

WORKDIR /app

COPY Caddyfile /etc/caddy/Caddyfile
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 7233

ENTRYPOINT ["/entrypoint.sh"]