#!/bin/sh
# Genera env-config.js en /usr/share/nginx/html ANTES de iniciar nginx,
# inyectando las variables de entorno del container como propiedades
# de window.* para que Flutter las pueda leer al cargar.
set -e

cat > /usr/share/nginx/html/env-config.js <<EOF
// Auto-generado por docker-entrypoint.sh en cada arranque del container.
window.GOOGLE_MAPS_API_KEY = "${GOOGLE_MAPS_API_KEY:-}";
EOF

echo "env-config.js generado:"
cat /usr/share/nginx/html/env-config.js

# Estado de Raspberry vía Tailscale (solo si hay credenciales).
if [ -n "$TS_CLIENT_ID" ] || [ -n "$TS_API_KEY" ]; then
  node /ts-status.js &
else
  echo "ts-status: sin TS_CLIENT_ID/TS_API_KEY, no se inicia"
fi

exec "$@"
