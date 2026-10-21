#!/bin/sh
# Generates /etc/rabbitmq/rabbitmq.conf from the environment at container start,
# then hands over to the broker so it becomes the process tini supervises.
#
# The credentials are not written here: the broker reads RABBITMQ_DEFAULT_USER
# and RABBITMQ_DEFAULT_PASS from its environment (they take precedence over the
# configuration file), so no password ever reaches the disk.
set -eu

: "${RABBITMQ_DEFAULT_USER:?must be set (compose injects RABBITMQ_USER from .env)}"
: "${RABBITMQ_DEFAULT_PASS:?must be set (compose injects RABBITMQ_PASSWORD from .env)}"

cat > /etc/rabbitmq/rabbitmq.conf <<'CONF'
listeners.tcp.default = 5672
loopback_users = none
log.console = true
log.console.level = info
log.console.use_colors = off
log.file = false
CONF

exec "$@"
