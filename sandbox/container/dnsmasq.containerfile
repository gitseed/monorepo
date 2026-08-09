# syntax=docker/dockerfile:1

FROM docker.io/library/alpine:3.20
RUN apk add --no-cache dnsmasq
# -d: run in foreground (daemon mode would exit the container)
ENTRYPOINT ["dnsmasq", "-d", "--no-hosts", "--log-queries"]
