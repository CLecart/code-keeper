#!/bin/sh
# Entrypoint of the inventory-database image (PostgreSQL 17 on Alpine).
#
# Runs as the unprivileged "postgres" user (see Dockerfile). The cluster is
# initialised only on the very first start, when $PGDATA holds no PG_VERSION
# file; later starts reuse the data of the named volume and go straight to
# the server. Any command other than "postgres" is executed as is.
set -eu

SERVICE=inventory-database
INITDB_DIR=/docker-entrypoint-initdb.d

log() { echo "[$SERVICE] $*"; }
die() { log "error: $*" >&2; exit 1; }

# The cluster is only usable once initdb *and* the SQL scripts have run, but
# initdb writes PG_VERSION as soon as it succeeds. A failure in between would
# leave a data directory that later starts consider initialised, and the
# service would restart forever on a missing schema. Wipe it instead, so the
# next start (restart: on-failure) retries a clean initialization.
initializing=0
cleanup_failed_init() {
  status=$?
  [ "$initializing" = 1 ] || return 0
  log "error: initialization failed (exit $status), removing the incomplete cluster" >&2
  pg_ctl -D "$PGDATA" -m immediate stop >/dev/null 2>&1 || true
  find "$PGDATA" -mindepth 1 -delete 2>/dev/null || true
}
trap cleanup_failed_init EXIT

# Create the cluster with POSTGRES_USER as superuser. The password is piped to
# initdb (--pwfile) so it never appears in the process list or on disk.
init_cluster() {
  log "initializing cluster in $PGDATA"
  printf '%s\n' "$POSTGRES_PASSWORD" | initdb --username="$POSTGRES_USER" \
    --pwfile=/dev/stdin --auth-local=trust --auth-host=scram-sha-256 \
    -E UTF8 --no-locale

  cat >> "$PGDATA/postgresql.conf" <<'EOF'

# Added by docker-entrypoint.sh: accept clients from the Docker network.
listen_addresses = '*'
password_encryption = scram-sha-256
EOF

  cat >> "$PGDATA/pg_hba.conf" <<'EOF'

# Added by docker-entrypoint.sh: every network client must use SCRAM-SHA-256.
host all all 0.0.0.0/0 scram-sha-256
host all all ::/0      scram-sha-256
EOF
}

# Create the application database and apply the SQL scripts through a temporary
# server that listens on the unix socket only, so nothing can connect before
# the schema is in place.
init_database() {
  pg_ctl -D "$PGDATA" -o "-c listen_addresses=''" -w start

  if [ "$POSTGRES_DB" != postgres ]; then
    log "creating database $POSTGRES_DB"
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
      -c "CREATE DATABASE \"$POSTGRES_DB\""
  fi

  for script in "$INITDB_DIR"/*.sql; do
    [ -f "$script" ] || continue
    log "applying $script"
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$script"
  done

  pg_ctl -D "$PGDATA" -m fast -w stop
}

if [ "${1:-}" = postgres ]; then
  [ -n "${POSTGRES_USER:-}" ]     || die "POSTGRES_USER must be set"
  [ -n "${POSTGRES_PASSWORD:-}" ] || die "POSTGRES_PASSWORD must be set"
  [ -n "${POSTGRES_DB:-}" ]       || die "POSTGRES_DB must be set"

  if [ -f "$PGDATA/PG_VERSION" ]; then
    log "existing cluster found in $PGDATA, skipping initialization"
  else
    initializing=1
    init_cluster
    init_database
    initializing=0
    log "initialization complete"
  fi
  log "starting PostgreSQL server"
fi

exec "$@"
