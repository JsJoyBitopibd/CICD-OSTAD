# ---------------------------------------------------------------
# Dockerfile for the CICD-OSTAD Node.js + Express application
# Author : Joyanta Sarker Joy (Mastering DevOps - Batch 13)
# ---------------------------------------------------------------

# 1. Base image: small, official Node.js 20 image built on Alpine Linux (~50 MB)
FROM node:20-alpine

# 2. Every command below runs inside /app inside the container
WORKDIR /app

# 3. Copy ONLY the dependency files first.
#    Docker caches this layer, so "npm ci" re-runs only when
#    package.json / package-lock.json actually change.
COPY package*.json ./

# 4. Install production dependencies exactly as locked in package-lock.json.
#    --omit=dev skips mocha/chai, which are only needed for testing.
RUN npm ci --omit=dev

# 5. Now copy the application source code.
COPY src ./src

# 6. Runtime settings
ENV NODE_ENV=production
ENV PORT=4000

# 7. Document that the app listens on port 4000 inside the container
EXPOSE 4000

# 8. Security: do not run as root. The node image already has a "node" user.
USER node

# 9. Docker's own health check (Kubernetes uses its own probes instead)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:4000/api || exit 1

# 10. The command that starts the application
CMD ["node", "src/server.js"]
