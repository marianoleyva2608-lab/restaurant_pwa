// Supabase Edge Function: clip-pago
// Procesa pagos con Clip y envía el ticket por correo.
//
// Endpoint: POST {SUPABASE_URL}/functions/v1/clip-pago
//
// Lee la configuración de la tabla `app_config`:
//   key                  value
//   ------------------   -------------------------------------------------
//   clip_secret_key      <tu_secret_key>
//   clip_api_url         https://api.payclip.com
//   resend_api_key       re_xxxxxx
//   ticket_from_email    tickets@misdominio.mx  (debe estar verificado en Resend)
//   restaurant_name      Gorditas Mis Hermanas
//
// Acciones (campo "action" del body):
//   - "clip"   → procesa un pago tokenizado contra la API de Clip
//   - "ticket" → envía un ticket por email vía Resend

// deno-lint-ignore-file no-explicit-any
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: CORS_HEADERS });
}

// Cargar config desde la tabla app_config (cacheada por ejecución)
let _configCache: Record<string, string> | null = null;
async function loadConfig(): Promise<Record<string, string>> {
  if (_configCache) return _configCache;
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
  const { data, error } = await supabase
    .from('app_config')
    .select('key, value');
  if (error) throw new Error(`No se pudo leer app_config: ${error.message}`);
  const cfg: Record<string, string> = {};
  for (const row of (data ?? []) as Array<{ key: string; value: string }>) {
    cfg[row.key] = row.value;
  }
  _configCache = cfg;
  return cfg;
}

async function procesarPagoClip(body: any) {
  const cfg = await loadConfig();
  const token = String(body.token ?? '').trim();
  const amount = Number(body.amount ?? 0);
  const email = String(body.email ?? '').trim();
  if (!token) return json({ ok: false, message: 'Falta token' }, 400);
  if (!amount || amount <= 0) {
    return json({ ok: false, message: 'Monto inválido' }, 400);
  }
  if (!email) {
    return json({ ok: false, status: 'rejected', message: 'Falta el correo del cliente' }, 400);
  }
  const clipApiKey = cfg.clip_api_key ?? '';
  const clipSecret = cfg.clip_secret_key ?? '';
  if (!clipApiKey || !clipSecret) {
    return json(
      { ok: false, message: 'credenciales de Clip no configuradas' },
      500,
    );
  }
  const clipApiUrl = cfg.clip_api_url || 'https://api.payclip.com';
  const restaurantName = cfg.restaurant_name || 'Restaurante';

  // Clip usa Basic auth con api_key:secret_key (igual que /v2/checkout).
  const basic = btoa(`${clipApiKey}:${clipSecret}`);

  const resp = await fetch(`${clipApiUrl}/payments`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Basic ${basic}`,
    },
    // Formato actual de Clip POST /payments: payment_method.token y
    // customer.email son obligatorios (source.token_id ya no se acepta).
    body: JSON.stringify({
      amount,
      currency: 'MXN',
      description: `Pedido ${restaurantName}`,
      payment_method: { token },
      customer: { email },
    }),
  });

  let data: any = {};
  try {
    const text = await resp.text();
    try { data = JSON.parse(text); } catch (_) { data = { raw: text }; }
  } catch (_) { /* sin body */ }

  if (!resp.ok) {
    return json({
      ok: false,
      status: 'rejected',
      payment_id: data.id ?? null,
      status_detail: data.error_message ?? data.detail ?? `HTTP ${resp.status}`,
      message: data.message ?? 'Pago rechazado por Clip',
    });
  }

  const clipStatus = String(data.status ?? '').toLowerCase();
  return json({
    ok: clipStatus === 'approved' || clipStatus === 'succeeded',
    status: clipStatus || 'approved',
    payment_id: data.id ?? data.payment_id ?? null,
    status_detail: data.status_detail ?? null,
  });
}

// Crea un Payment Link de Clip y devuelve la URL para redirigir al cliente.
// Clip NO usa OAuth (no hay /oauth/token). La auth es Basic base64(api_key:secret_key)
// directo sobre el endpoint del recurso /v2/checkout.
async function crearLinkPago(body: any) {
  let cfg: Record<string, string>;
  try {
    cfg = await loadConfig();
  } catch (e: any) {
    return json({ ok: false, step: 'loadConfig', detail: String(e?.message ?? e) }, 500);
  }

  const amount = Number(body.amount ?? 0);
  const description = String(body.description ?? 'Pedido').slice(0, 250);
  const redirectUrl = String(body.redirect_url ?? '');
  if (!amount || amount <= 0) {
    return json({ ok: false, message: 'Monto inválido' }, 400);
  }

  const clipApiKey = cfg.clip_api_key ?? '';
  const clipSecretKey = cfg.clip_secret_key ?? '';
  const clipApiUrl = cfg.clip_api_url || 'https://api.payclip.com';

  if (!clipApiKey || !clipSecretKey) {
    return json({ ok: false, message: 'clip_api_key / clip_secret_key no configuradas' }, 500);
  }

  const basic = btoa(`${clipApiKey}:${clipSecretKey}`);

  let resp: Response;
  try {
    resp = await fetch(`${clipApiUrl}/v2/checkout`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${basic}`,
      },
      body: JSON.stringify({
        amount,
        currency: 'MXN',
        purchase_description: description,
        redirection_url: {
          success: redirectUrl || undefined,
          error: redirectUrl || undefined,
          default: redirectUrl || undefined,
        },
      }),
    });
  } catch (e: any) {
    return json({ ok: false, step: 'fetch_clip', detail: String(e?.message ?? e) }, 500);
  }

  let text = '';
  try {
    text = await resp.text();
  } catch (e: any) {
    return json({ ok: false, step: 'read_body', http_status: resp.status, detail: String(e?.message ?? e) }, 500);
  }

  let data: any = {};
  try { data = JSON.parse(text); } catch (_) { data = { raw: text }; }

  if (!resp.ok) {
    return json({
      ok: false,
      step: 'clip_error',
      http_status: resp.status,
      message: data.message ?? data.error_message ?? `HTTP ${resp.status}`,
      detail: data,
    }, resp.status);
  }

  return json({
    ok: true,
    payment_id: data.payment_request_id ?? data.id ?? null,
    url: data.payment_request_url ?? data.url ?? data.checkout_url ?? null,
    raw: data,
  });
}

function renderTicketHtml(payload: any, restaurantName: string): string {
  const items: Array<{ nombre: string; cantidad: number; precio: number }> =
    Array.isArray(payload.items) ? payload.items : [];
  const total = Number(payload.total ?? 0);
  const paymentId = String(payload.payment_id ?? '—');
  const fecha = new Date().toLocaleString('es-MX', {
    timeZone: 'America/Mexico_City',
  });
  const rows = items
    .map((i) => {
      const subtotal = Number(i.precio ?? 0) * Number(i.cantidad ?? 0);
      return `
        <tr>
          <td style="padding:6px 4px;border-bottom:1px solid #eee">${
            escapeHtml(i.nombre)
          }</td>
          <td style="padding:6px 4px;text-align:center;border-bottom:1px solid #eee">${i.cantidad}</td>
          <td style="padding:6px 4px;text-align:right;border-bottom:1px solid #eee">$${subtotal.toFixed(2)}</td>
        </tr>`;
    })
    .join('');
  // QR de Clip para este pago (Clip lo genera automáticamente por payment_id)
  const qrUrl = paymentId && paymentId !== '—'
      ? `https://qr.payclip.com/${encodeURIComponent(paymentId)}?version=v3`
      : '';
  const qrBlock = qrUrl
      ? `
      <div style="margin-top:24px;text-align:center;padding:20px;background:#f8fafc;border-radius:12px;border:1px solid #e2e8f0">
        <p style="margin:0 0 12px 0;color:#475569;font-size:13px;font-weight:600">Comprobante de pago (QR)</p>
        <img src="${qrUrl}" alt="QR de pago" style="width:180px;height:180px;display:block;margin:0 auto;background:#fff;padding:8px;border-radius:8px" />
        <p style="margin:12px 0 0 0;color:#64748b;font-size:11px">Escanea con la app de Clip o cámara para verificar el pago.</p>
      </div>`
      : '';
  return `<!doctype html><html><body style="font-family:system-ui,sans-serif;background:#f4f4f4;padding:24px;color:#0f172a">
    <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:14px;padding:24px;box-shadow:0 2px 10px rgba(0,0,0,0.05)">
      <h2 style="margin:0 0 8px 0">${escapeHtml(restaurantName)}</h2>
      <p style="margin:0 0 16px 0;color:#64748b;font-size:13px">${fecha}</p>
      <p style="margin:0 0 4px 0;font-size:13px;color:#64748b">ID de pago: <code>${paymentId}</code></p>
      <table style="width:100%;border-collapse:collapse;margin-top:16px;font-size:14px">
        <thead>
          <tr style="background:#f1f5f9">
            <th style="padding:8px 4px;text-align:left">Producto</th>
            <th style="padding:8px 4px;text-align:center">Cant.</th>
            <th style="padding:8px 4px;text-align:right">Subtotal</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
      <div style="text-align:right;margin-top:16px;font-size:18px;font-weight:bold">
        Total: $${total.toFixed(2)}
      </div>${qrBlock}
      <p style="margin-top:24px;color:#64748b;font-size:12px">Gracias por tu compra. Conserva este ticket como comprobante.</p>
    </div>
  </body></html>`;
}

function escapeHtml(s: string): string {
  return String(s)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

async function enviarTicket(body: any) {
  const cfg = await loadConfig();
  const to = String(body.email ?? '').trim();
  if (!to) return json({ ok: false, message: 'Falta email' }, 400);
  const resendKey = cfg.resend_api_key;
  if (!resendKey || resendKey.startsWith('pon-')) {
    return json(
      { ok: false, message: 'resend_api_key no configurada en app_config' },
      500,
    );
  }
  const fromEmail = cfg.ticket_from_email || 'tickets@example.com';
  const restaurantName = cfg.restaurant_name || 'Restaurante';

  const html = renderTicketHtml(body, restaurantName);
  const resp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${resendKey}`,
    },
    body: JSON.stringify({
      from: `${restaurantName} <${fromEmail}>`,
      to: [to],
      subject: `Ticket de tu pedido - ${restaurantName}`,
      html,
    }),
  });

  if (!resp.ok) {
    const detail = await resp.text();
    return json({ ok: false, message: 'Error al enviar ticket', detail }, 500);
  }
  return json({ ok: true });
}

// Consulta el status actual de un payment link por su id (polling).
// Devuelve { ok, status, message, raw } — status es CHECKOUT_CREATED |
// CHECKOUT_PENDING | CHECKOUT_COMPLETED | CHECKOUT_CANCELLED | CHECKOUT_EXPIRED.
async function checkStatus(body: any) {
  let cfg: Record<string, string>;
  try {
    cfg = await loadConfig();
  } catch (e: any) {
    return json({ ok: false, step: 'loadConfig', detail: String(e?.message ?? e) }, 500);
  }

  const paymentId = String(body.payment_id ?? '').trim();
  if (!paymentId) return json({ ok: false, message: 'Falta payment_id' }, 400);

  const clipApiKey = cfg.clip_api_key ?? '';
  const clipSecretKey = cfg.clip_secret_key ?? '';
  const clipApiUrl = cfg.clip_api_url || 'https://api.payclip.com';
  if (!clipApiKey || !clipSecretKey) {
    return json({ ok: false, message: 'clip credentials no configuradas' }, 500);
  }

  const basic = btoa(`${clipApiKey}:${clipSecretKey}`);
  let resp: Response;
  try {
    resp = await fetch(`${clipApiUrl}/v2/checkout/${encodeURIComponent(paymentId)}`, {
      method: 'GET',
      headers: { 'Authorization': `Basic ${basic}` },
    });
  } catch (e: any) {
    return json({ ok: false, step: 'fetch_clip', detail: String(e?.message ?? e) }, 500);
  }

  const text = await resp.text();
  let data: any = {};
  try { data = JSON.parse(text); } catch (_) { data = { raw: text }; }

  if (!resp.ok) {
    return json({ ok: false, http_status: resp.status, detail: data }, resp.status);
  }

  return json({
    ok: true,
    payment_id: paymentId,
    status: String(data.status ?? ''),
    message: String(data.last_status_message ?? ''),
    raw: data,
  });
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return json({ ok: false, message: 'Método no permitido' }, 405);
  }
  let body: any;
  try {
    body = await req.json();
  } catch (_) {
    return json({ ok: false, message: 'JSON inválido' }, 400);
  }
  const action = String(body.action ?? '').toLowerCase();
  try {
    if (action === 'clip') return await procesarPagoClip(body);
    if (action === 'ticket') return await enviarTicket(body);
    if (action === 'create_link') return await crearLinkPago(body);
    if (action === 'check_status') return await checkStatus(body);
    return json({ ok: false, message: `Acción desconocida: ${action}` }, 400);
  } catch (e: any) {
    return json(
      { ok: false, message: 'Error interno', detail: String(e?.message ?? e) },
      500,
    );
  }
});
