# syntax=docker/dockerfile:1

ARG NODE_VERSION=20-alpine

# ---- base ----
FROM node:${NODE_VERSION} AS base
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1

# ---- deps (кешируем store) ----
FROM base AS deps
RUN apk add --no-cache libc6-compat python3 make g++
RUN corepack enable && corepack prepare pnpm@9.12.3 --activate
COPY package.json pnpm-lock.yaml* ./
RUN pnpm fetch --silent

# ---- builder (нужно devDeps!) ----
FROM base AS builder
# ВАЖНО: не production, чтобы ставились devDeps
ENV NODE_ENV=development
RUN apk add --no-cache libc6-compat \
  && corepack enable && corepack prepare pnpm@9.12.3 --activate

# перенесём кешированный store
COPY --from=deps /root/.local/share/pnpm/store /root/.local/share/pnpm/store
COPY package.json pnpm-lock.yaml* ./

# ставим все зависимости (включая dev)
RUN pnpm install --frozen-lockfile --offline --prod=false

# копируем исходники и билдим
COPY . .
# убедись, что в next.config.ts есть: export default { output: 'standalone' }
RUN pnpm run build

# ---- runner (минимальный рантайм) ----
FROM node:${NODE_VERSION} AS runner
WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000 \
    HOSTNAME=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1

# непривилегированный пользователь
RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -u 1001

# standalone + статика + public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]