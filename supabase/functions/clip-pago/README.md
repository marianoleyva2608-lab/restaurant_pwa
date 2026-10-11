# Edge Function `clip-pago`

Procesa pagos con Clip y envía tickets por correo desde el Supabase del restaurante.

La función lee la configuración de la tabla `public.app_config` (key/value).

## Crear la tabla y los registros (SQL Editor)

```sql
CREATE TABLE IF NOT EXISTS public.app_config (
  key   text PRIMARY KEY,
  value text NOT NULL
);

INSERT INTO public.app_config (key, value) VALUES
  ('clip_secret_key',    'TU_SECRET_KEY'),
  ('clip_api_url',       'https://api.payclip.com'),
  ('resend_api_key',     'TU_TOKEN_DE_RESEND'),
  ('ticket_from_email',  'tickets@TU-DOMINIO-VERIFICADO.com'),
  ('restaurant_name',    'Gorditas Mis Hermanas')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

> ⚠️ Reemplaza `TU_TOKEN_DE_RESEND` y `ticket_from_email` por valores reales antes de probar.

## Despliegue (CLI)

```bash
# Si tienes problemas con `supabase login`, usa un token:
# https://supabase.com/dashboard/account/tokens
export SUPABASE_ACCESS_TOKEN=<token>

supabase functions deploy clip-pago \
  --project-ref jcaqolmacqhhgtjdgvaz \
  --no-verify-jwt
```

## Despliegue (sin CLI, desde el dashboard)

1. https://supabase.com/dashboard/project/jcaqolmacqhhgtjdgvaz/functions
2. **Create a new function** → nombre `clip-pago`
3. Pega el contenido de `index.ts`
4. **Deploy**

## Probar

```bash
# Enviar un ticket de prueba
curl -X POST \
  "https://jcaqolmacqhhgtjdgvaz.supabase.co/functions/v1/clip-pago" \
  -H "Content-Type: application/json" \
  -d '{
    "action":"ticket",
    "email":"tu@correo.com",
    "payment_id":"DEMO-1",
    "total":40,
    "items":[{"nombre":"Refresco","cantidad":1,"precio":40}]
  }'
```

## Cambiar la URL en la app Flutter

Una vez desplegada, actualiza `lib/services/clip_service.dart` para que apunte aquí
en lugar del Supabase del proyecto PV.
