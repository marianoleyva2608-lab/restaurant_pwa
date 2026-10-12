# syntax=docker/dockerfile:1.7

# ─── ETAPA 1: Compilación de la app Flutter Web ────────────────────────
#
# Base: debian:stable-slim + Flutter clonado (shallow). Antes intentamos
# usar ghcr.io/cirruslabs/flutter:stable pero la imagen es ~10 GB extraídos
# e incluye el emulador de Android, cuyos pseudo-devices crasheaban el
# snapshotter de containerd con overlayfs (`failed to Lchown ...
# qemu-system-armel-headless`). Volvemos a clonar Flutter pero con
# `--depth=1 -b stable` (solo ~80 MB) y precargamos el SDK.
FROM debian:stable-slim AS build-env

RUN apt-get update && apt-get install -y \
    curl git wget unzip ca-certificates xz-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Clone shallow del branch stable (sin historia, sin otros branches).
RUN git clone --depth=1 -b stable https://github.com/flutter/flutter.git /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Marca el folder como safe para git (evita warnings de "dubious ownership"
# cuando flutter intenta leer git info dentro del SDK).
RUN git config --global --add safe.directory /usr/local/flutter

# Pre-cargar el Dart SDK de Flutter en este layer (queda cacheado).
# Sin esto, el primer `pub get` lo descarga y rompe el cache mount.
RUN flutter --version

WORKDIR /app

# ─── Capas optimizadas para cache de pub get ─────────────────────────────
#
# 1) Copiar SOLO los manifests primero. Si solo cambia código en lib/, el
#    layer de pub get se reusa (antes se invalidaba en cada commit y se
#    re-descargaban ~150 MB de paquetes).
COPY pubspec.yaml pubspec.lock ./

# 2) `pub get` con cache mount BuildKit para el pub-cache global.
RUN --mount=type=cache,target=/root/.pub-cache \
    flutter pub get

# 3) Ahora sí el resto del código.
COPY . .

# 4) Build web. La GOOGLE_MAPS_API_KEY se inyecta en runtime vía
#    env-config.js (ver docker-entrypoint.sh), no en build time, porque
#    EasyPanel solo pasa env vars al container al arrancar (no al
#    `docker build`).
RUN --mount=type=cache,target=/root/.pub-cache \
    flutter build web --release --no-tree-shake-icons --pwa-strategy=none

# ─── ETAPA 2: Servir con Nginx ─────────────────────────────────────────
FROM nginx:alpine

# Copia el resultado del build al directorio de Nginx
COPY --from=build-env /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Entrypoint genera /usr/share/nginx/html/env-config.js a partir de las
# env vars del container ANTES de iniciar nginx. Permite que EasyPanel
# inyecte GOOGLE_MAPS_API_KEY en runtime sin re-buildear.
COPY docker-entrypoint.sh /docker-entrypoint.sh
# Node para el mini servicio de estado de Tailscale (ts-status.js).
RUN apk add --no-cache nodejs
COPY ts-status.js /ts-status.js
RUN chmod +x /docker-entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
