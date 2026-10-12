// Mini servicio que consulta la API de Tailscale y devuelve SOLO si cada
// Raspberry está conectada. Corre dentro del mismo container que la app
// web (nginx lo expone en /ts-status). La llave de Tailscale vive en
// variables de entorno de Easypanel, nunca en la app.
//
// Variables (en Easypanel → restaurant-pwa → Environment):
//   TS_CLIENT_ID / TS_CLIENT_SECRET  → OAuth client de Tailscale (recomendado, no caduca)
//   o TS_API_KEY                     → API key (caduca máx. 90 días)
//   TS_HOST_PREFIX                   → opcional, default "rasp"
const http = require('http');

const PORT = 8090;
const PREFIX = (process.env.TS_HOST_PREFIX || 'rasp').toLowerCase();
const CACHE_MS = 30_000;

let token = null, tokenExp = 0;
let cache = null, cacheAt = 0;

async function getToken() {
  if (process.env.TS_API_KEY) return process.env.TS_API_KEY;
  if (token && Date.now() < tokenExp) return token;
  const body = new URLSearchParams({
    client_id: process.env.TS_CLIENT_ID || '',
    client_secret: process.env.TS_CLIENT_SECRET || '',
  });
  const r = await fetch('https://api.tailscale.com/api/v2/oauth/token', { method: 'POST', body });
  if (!r.ok) throw new Error(`oauth ${r.status}`);
  const j = await r.json();
  token = j.access_token;
  tokenExp = Date.now() + ((j.expires_in || 3600) - 300) * 1000;
  return token;
}

async function getDevices() {
  if (cache && Date.now() - cacheAt < CACHE_MS) return cache;
  const t = await getToken();
  const r = await fetch('https://api.tailscale.com/api/v2/tailnet/-/devices', {
    headers: { Authorization: `Bearer ${t}` },
  });
  if (!r.ok) throw new Error(`devices ${r.status}`);
  const j = await r.json();
  cache = (j.devices || [])
    .filter((d) => String(d.hostname || '').toLowerCase().startsWith(PREFIX))
    .map((d) => ({
      host: d.hostname,
      online: d.connectedToControl === true,
      lastSeen: d.lastSeen || null,
    }))
    .sort((a, b) => a.host.localeCompare(b.host));
  cacheAt = Date.now();
  return cache;
}

http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'no-store');
  try {
    res.end(JSON.stringify({ ok: true, devices: await getDevices() }));
  } catch (e) {
    console.error('ts-status:', e.message);
    res.statusCode = 502;
    res.end(JSON.stringify({ ok: false, error: e.message }));
  }
}).listen(PORT, '127.0.0.1', () => console.log(`ts-status en :${PORT}`));
