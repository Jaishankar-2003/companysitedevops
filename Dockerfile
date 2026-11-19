
# # ==========================================
# # Stage 1: Dependencies
# # ==========================================
# FROM node:22-trixie-slim AS deps

# WORKDIR /app

# COPY package.json package-lock.json ./

# RUN npm ci


# # ==========================================
# # Stage 2: Build Application
# # ==========================================
# FROM node:22-trixie-slim AS builder

# WORKDIR /app

# ENV NEXT_TELEMETRY_DISABLED=1

# COPY --from=deps /app/node_modules ./node_modules
# COPY . .

# RUN npm run build

# # Remove environment files from standalone output
# RUN rm -f \
#     .next/standalone/.env \
#     .next/standalone/.env.local \
#     .next/standalone/.env.production


# # ==========================================
# # Stage 3: Production Runtime
# # ==========================================
# FROM node:22-trixie-slim AS runner

# WORKDIR /app

# # Runtime environment
# ENV NODE_ENV=production \
#     NEXT_TELEMETRY_DISABLED=1 \
#     HOSTNAME=0.0.0.0 \
#     PORT=3000

# # Update Debian packages to their latest available versions
# # Remove package managers not required at runtime
# RUN apt-get update \
#     && apt-get upgrade -y \
#     && apt-get clean \
#     && rm -rf /var/lib/apt/lists/* \
#     && rm -rf /usr/local/lib/node_modules/npm \
#     /usr/local/lib/node_modules/corepack \
#     && rm -f /usr/local/bin/npm \
#     /usr/local/bin/npx \
#     /usr/local/bin/corepack

# # Copy Next.js standalone server
# COPY --from=builder --chown=node:node /app/.next/standalone ./

# # Copy Next.js static assets
# COPY --from=builder --chown=node:node /app/.next/static ./.next/static

# # Copy public assets
# COPY --from=builder --chown=node:node /app/public ./public

# # Run application as non-root user
# USER node

# # Application port
# EXPOSE 3000

# # Container health check
# HEALTHCHECK --interval=30s \
#     --timeout=5s \
#     --start-period=10s \
#     --retries=3 \
#     CMD node -e "fetch('http://127.0.0.1:3000').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# # Start Next.js standalone server
# CMD ["node", "server.js"]





# ============================================================
# Stage 1: Dependencies
# ============================================================
FROM node:22-alpine AS deps

WORKDIR /app

RUN apk upgrade --no-cache \
    && apk add --no-cache libc6-compat

COPY package.json package-lock.json ./

RUN npm ci


# ============================================================
# Stage 2: Build
# ============================================================
FROM node:22-alpine AS builder

WORKDIR /app

ENV NEXT_TELEMETRY_DISABLED=1

RUN apk upgrade --no-cache \
    && apk add --no-cache libc6-compat

COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN npm run build \
    && rm -f \
    .next/standalone/.env \
    .next/standalone/.env.local \
    .next/standalone/.env.production


# ============================================================
# Stage 3: Production Runtime
# ============================================================
FROM node:22-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    HOSTNAME=0.0.0.0 \
    PORT=3000

RUN apk upgrade --no-cache \
    && apk add --no-cache libc6-compat \
    && rm -rf /usr/local/lib/node_modules/npm \
    /usr/local/lib/node_modules/corepack \
    /opt/yarn-v1.22.22 \
    && rm -f /usr/local/bin/npm \
    /usr/local/bin/npx \
    /usr/local/bin/corepack \
    /usr/local/bin/yarn \
    /usr/local/bin/yarnpkg

COPY --from=builder --chown=node:node /app/.next/standalone ./
COPY --from=builder --chown=node:node /app/.next/static ./.next/static
COPY --from=builder --chown=node:node /app/public ./public

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s \
    --timeout=5s \
    --start-period=10s \
    --retries=3 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:3000').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]

CMD ["node", "server.js"]
