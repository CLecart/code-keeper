FROM alpine:3.23

LABEL org.opencontainers.image.title="inventory-database" \
      org.opencontainers.image.description="PostgreSQL 17 database of the inventory service (movies table)" \
      org.opencontainers.image.authors="clecart"

ENV PGDATA=/var/lib/postgresql/data \
    LANG=C.UTF-8

# apk upgrade: take the security fixes released after the alpine:3.23 base image
# (the ECR scan flagged zlib 1.3.2-r0, CVE-2026-85091, fixed in 1.3.2-r1).
# PostgreSQL 17 (+ contrib extensions) and tini as PID 1 for signal handling.
# /run/postgresql holds the unix socket; the data directory is the mount point
# of the named volume and is created here so the volume inherits its ownership.
RUN apk upgrade --no-cache \
    && apk add --no-cache postgresql17 postgresql17-contrib tini \
    && mkdir -p "$PGDATA" /run/postgresql /docker-entrypoint-initdb.d \
    && chown -R postgres:postgres /var/lib/postgresql /run/postgresql \
    && chmod 700 "$PGDATA"

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/
COPY init/ /docker-entrypoint-initdb.d/

# Nothing runs as root at runtime: entrypoint, initdb and the server all run
# as the unprivileged postgres user (uid 70).
USER postgres

EXPOSE 5432

# SIGINT asks PostgreSQL for a "fast" shutdown (clean, no recovery on restart).
STOPSIGNAL SIGINT

# Shell form on purpose: POSTGRES_USER/POSTGRES_DB are only known at run time.
# hadolint ignore=DL3025
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
    CMD pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" -h 127.0.0.1 || exit 1

ENTRYPOINT ["/sbin/tini", "--", "docker-entrypoint.sh"]
CMD ["postgres"]
