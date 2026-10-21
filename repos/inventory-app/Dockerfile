# ---- Stage 1: install production dependencies from the lockfile ----------------
FROM alpine:3.23 AS deps

RUN apk add --no-cache nodejs npm
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ---- Stage 2: minimal runtime image (no npm, non-root, tini as PID 1) -----------
FROM alpine:3.23

LABEL org.opencontainers.image.title="inventory-app" \
      org.opencontainers.image.description="Inventory microservice: REST API for movies backed by PostgreSQL" \
      org.opencontainers.image.authors="clecart"

# apk upgrade: take the security fixes released after the alpine:3.23 base image
# (the ECR scan flagged zlib 1.3.2-r0, CVE-2026-85091, fixed in 1.3.2-r1).
RUN apk upgrade --no-cache \
 && apk add --no-cache nodejs tini \
 && addgroup -S -g 1001 app \
 && adduser -S -D -H -u 1001 -G app -h /app -s /sbin/nologin app

WORKDIR /app
COPY --from=deps --chown=app:app /app/node_modules ./node_modules
COPY --chown=app:app package.json ./
COPY --chown=app:app src ./src

ENV NODE_ENV=production
USER app
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=5 \
  CMD ["wget", "-qO-", "http://127.0.0.1:8080/health"]

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "src/index.js"]
