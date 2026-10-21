# ---- Stage 1: install production dependencies only ----
FROM alpine:3.23 AS deps
RUN apk add --no-cache nodejs npm
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ---- Stage 2: minimal runtime image (no npm, non-root user) ----
FROM alpine:3.23
LABEL org.opencontainers.image.title="api-gateway-app" \
      org.opencontainers.image.description="API gateway: proxies /api/movies to inventory-app and publishes /api/billing orders to RabbitMQ" \
      org.opencontainers.image.authors="clecart"

# apk upgrade: take the security fixes released after the alpine:3.23 base image
# (the ECR scan flagged zlib 1.3.2-r0, CVE-2026-85091, fixed in 1.3.2-r1).
# tini reaps zombies and forwards signals to node for a clean shutdown.
# The log directory is created here so the named volume inherits app:app ownership on first mount.
RUN apk upgrade --no-cache \
    && apk add --no-cache nodejs tini \
    && addgroup -S -g 1001 app \
    && adduser -S -D -H -u 1001 -G app -h /app -s /sbin/nologin app \
    && mkdir -p /var/logs/api-gateway \
    && chown app:app /var/logs/api-gateway

WORKDIR /app
COPY --from=deps --chown=app:app /app/node_modules ./node_modules
COPY --chown=app:app package.json ./
COPY --chown=app:app src ./src

ENV NODE_ENV=production
USER app
EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=5 \
  CMD ["wget", "-qO-", "http://127.0.0.1:3000/health"]

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "src/index.js"]
