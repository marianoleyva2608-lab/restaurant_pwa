# ETAPA 1: Compilación de la aplicación
FROM debian:stable-slim AS build-env

# Instalar dependencias esenciales
RUN apt-get update && apt-get install -y \
    curl \
    git \
    wget \
    unzip \
    ca-certificates \
    && apt-get clean

# Descargar Flutter SDK
RUN git clone https://github.com/flutter/flutter.git /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Configurar Flutter
RUN flutter channel stable
RUN flutter upgrade

# Configurar el directorio de trabajo
WORKDIR /app

# Copiar archivos del proyecto
COPY . .

# Obtener dependencias y compilar para web
RUN flutter pub get
RUN flutter build web --release --no-tree-shake-icons

# ETAPA 2: Servir con Nginx
FROM nginx:alpine

# Copiar el resultado de la etapa anterior al directorio de Nginx
COPY --from=build-env /app/build/web /usr/share/nginx/html

# Exponer el puerto 80
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
