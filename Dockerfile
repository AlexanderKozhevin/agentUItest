# syntax=docker/dockerfile:1

ARG NODE_VERSION=20-alpine

# Базовый слой
FROM node:${NODE_VERSION} AS base
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1

# ---- deps: установка зависимостей (кешируем store pnpm) ----
FROM base AS deps
# libc6-compat — частая зависимость бинарных пакетов; toolchain — на случай нативных модулей
RUN apk add --no-cache libc6-compat python3 make g++
# pnpm через corepack (не тянем глобально npm i -g)
RUN corepack enable && corepack prepare pnpm@9.12.3 --activate
COPY package.json pnpm-lock.yaml* ./
# Загружаем зависимости в кеш pnpm store без установки в node_modules
RUN pnpm fetch --silent

# ---- builder: сборка Next.js ----
FROM base AS builder
RUN apk add --no-cache libc6-compat \
 && corepack enable && corepack prepare pnpm@9.12.3 --activate

# Переносим кешированный store для оффлайн-установки
COPY --from=deps /root/.local/share/pnpm/store /root/.local/share/pnpm/store
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile --offline

# Копируем код и билдим
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm run build

# ---- runner: минимальный образ для запуска ----
FROM node:${NODE_VERSION} AS runner
WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000 \
    HOSTNAME=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1

# Непривилегированный пользователь
RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -u 1001

# Копируем standalone-артефакты
# .next/standalone содержит server.js и минимальные node_modules для рантайма
COPY --from=builder /app/.next/standalone ./
# статика и public ресурсы
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

USER nextjs
EXPOSE 3000

# next start нам не нужен — standalone кладёт server.js
CMD ["node", "server.js"]