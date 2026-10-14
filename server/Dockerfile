# Relic Diver web host + co-op lobby relay. Build from the repository root:
#   docker build -f server/Dockerfile -t relic-diver .
FROM node:22.22-alpine
WORKDIR /app
COPY server/package.json server/package-lock.json ./server/
RUN cd server && npm ci --omit=dev
COPY server/*.js ./server/
COPY server/accounts ./server/accounts
# The tracked web bundle (tools/package-web.*) is unpacked into the web root.
COPY build/RelicDiver-Web.zip /tmp/web.zip
RUN mkdir -p /app/web && unzip -q /tmp/web.zip -d /app/web && rm /tmp/web.zip
ENV PORT=8080 WEB_ROOT=/app/web NODE_ENV=production
EXPOSE 8080
USER node
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
CMD ["node", "server/server.js"]
