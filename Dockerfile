# ==============================================================================
# Multi-stage Dockerfile for Next.js 15 (Standalone Mode with pnpm)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Base stage
# ------------------------------------------------------------------------------
FROM node:20-alpine AS base
WORKDIR /app

# Install libc6-compat for Alpine compatibility with some native Node modules
RUN apk add --no-cache libc6-compat

# Install pnpm matching packageManager in package.json
RUN npm install -g pnpm@10.15.1

# ------------------------------------------------------------------------------
# 2. Dependencies stage
# ------------------------------------------------------------------------------
FROM base AS deps
WORKDIR /app

# Copy dependency definition files
COPY package.json pnpm-lock.yaml ./

# Install dependencies strictly according to lockfile
RUN pnpm install --frozen-lockfile

# ------------------------------------------------------------------------------
# 3. Builder stage
# ------------------------------------------------------------------------------
FROM base AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Disable Next.js telemetry during build
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

# Build standalone Next.js bundle
RUN pnpm run build

# ------------------------------------------------------------------------------
# 4. Production Runner stage
# ------------------------------------------------------------------------------
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Create a secure, non-root user to run the container
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copy static assets and standalone server output
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Set permissions
USER nextjs

EXPOSE 3000

# Start Next.js standalone server
CMD ["node", "server.js"]
