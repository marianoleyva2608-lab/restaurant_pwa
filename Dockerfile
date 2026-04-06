# ETAPA 1: Compilación de la aplicación
FROM debian:latest AS build-env

# Instalar dependencias necesarias para Flutter
RUN apt-get update && apt-get install -y \
    curl \
    git \
    wget \
    unzip \
    libgconf-2-4 \
    gdb \
    libstdc++6 \
    libglu1-mesa \
    fonts-droid-fallback \
    lib32stdc++6 \
    python3 \
    && apt-get clean

# Descargar Flutter SDK (usando la rama estable)
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
# Se añade --no-tree-shake-icons para evitar errores de compilación comunes
RUN flutter pub get
RUN flutter build web --release --no-tree-shake-icons

# ETAPA 2: Servir con Nginx
FROM nginx:alpine

# Copiar el resultado de la etapa anterior al directorio de Nginx
COPY --from=build-env /app/build/web /usr/share/nginx/html

# Exponer el puerto 80
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
