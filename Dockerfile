
# Stage 1: Install dependencies
FROM node:22-bookworm-slim AS deps

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci


# Stage 2: Build Next.js application
FROM node:22-bookworm-slim AS builder

WORKDIR /app

ENV NEXT_TELEMETRY_DISABLED=1

COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN npm run build

# Defensive removal of any environment file copied into standalone
RUN rm -f .next/standalone/.env


# Stage 3: Production runtime
FROM node:22-bookworm-slim AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV HOSTNAME=0.0.0.0
ENV PORT=3000

# Copy standalone production server
COPY --from=builder --chown=node:node /app/.next/standalone ./

# Copy static assets
COPY --from=builder --chown=node:node /app/.next/static ./.next/static

# Copy public assets
COPY --from=builder --chown=node:node /app/public ./public

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:3000').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]
