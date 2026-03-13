# ---- Stage 1: Dependencies ----
FROM node:20-alpine AS deps

WORKDIR /app

COPY package.json package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

# ---- Stage 2: Builder ----
FROM node:20-alpine AS builder

WORKDIR /app

# Copy installed dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# BACKEND_INTERNAL_URL must be set at BUILD time because Next.js standalone
# output bakes rewrites into the server bundle. Changing it at runtime has no effect.
ENV BACKEND_INTERNAL_URL=http://backend:8000

# Ensure public dir exists (may be empty in scaffold)
RUN mkdir -p public

RUN npm run build

# ---- Stage 3: Runner ----
FROM node:20-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copy standalone output + static assets + public directory
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

CMD ["node", "server.js"]
