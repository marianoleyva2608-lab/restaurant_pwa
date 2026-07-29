// Print-worker: escucha la tabla `orders` de Supabase y manda cada
// orden nueva a la impresora térmica Star TSP143 (USB en Windows).
//
// Flujo:
//   1. Al arrancar, procesa todas las órdenes sin imprimir (catch-up).
//   2. Se subscribe vía Realtime a INSERT en `orders` para esta sucursal.
//   3. Por cada orden: fetch items+dishes → formato ESC-POS → imprime
//      → UPDATE orders SET printed_at = NOW().
//
// Idempotencia: el guard `printed_at IS NULL` evita duplicados aunque
// el evento se vuelva a entregar tras un reconnect de Realtime.

'use strict';

require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');
const {
  printer: ThermalPrinter,
  types: PrinterTypes,
} = require('node-thermal-printer');

// Node <22 no tiene WebSocket nativo y @supabase/realtime-js lo exige
// (incluso si solo hacemos polling). Cargamos `ws` como polyfill.
let wsTransport;
try {
  wsTransport = require('ws');
} catch {
  // Node 22+ trae WebSocket nativo, no se necesita.
}

// ── Config ──────────────────────────────────────────────────────────
const {
  SUPABASE_URL,
  SUPABASE_SERVICE_KEY,
  PRINTER_NAME,    // Windows: nombre en el spooler ("Star TSP143")
  PRINTER_DEVICE,  // Linux/Raspberry: device file ("/dev/usb/lp0")
  PRINTER_TYPE,    // 'epson' (default) o 'star' — comando set de la impresora
  PAPER_WIDTH_CHARS, // 48 (80mm, default) o 32 (58mm)
  PAUSE_BETWEEN_TICKETS_MS, // ms de pausa entre BAR y COCINA (default 5000)
  RESTAURANT_NAME, // se imprime en el encabezado de cada ticket
  DISPLAY_MODE, // 'printer' (default) o 'screen' — ver abajo
  PRINT_AREA,   // '', 'drinks' o 'kitchen' — ver abajo
  BRANCH_NAME,
  DRY_RUN,
} = process.env;

// PRINT_AREA filtra qué items imprime esta Pi. Permite dividir la
// misma sucursal en varias Pis, cada una imprimiendo solo su parte:
//   - ''        (o unset): imprime TODO — un ticket COCINA + uno BAR.
//                           Es el comportamiento original, compat.
//   - 'drinks': imprime SOLO bebidas. Ticket titulado "BAR".
//   - 'kitchen': imprime SOLO comida. Ticket titulado "COCINA".
//   - 'line':   igual que 'kitchen' (mismo filtro), pero el ticket
//                se titula "LÍNEA DE PRODUCCIÓN". Para sucursales
//                donde al área de comida se le dice "línea" y no
//                "cocina".
//   - 'takeout': comida SOLO de órdenes to_go/delivery. Ticket
//                titulado "PARA LLEVAR". Automáticamente filtra
//                por order_type — no necesita PRINT_ORDER_TYPES.
// Idempotencia: cada Pi marca únicamente los `order_items` que le
// tocan (por id). Cuando la última Pi termina, no quedan items
// pendientes y se marca `orders.printed_at`.
const printArea = String(PRINT_AREA || '').toLowerCase();
const validAreas = ['', 'drinks', 'kitchen', 'line', 'takeout', 'receipt'];
if (!validAreas.includes(printArea)) {
  console.error(`✘ PRINT_AREA inválida: "${printArea}". Valores: '', 'drinks', 'kitchen', 'line', 'takeout', 'receipt'.`);
  process.exit(1);
}

// PRINT_AREA='receipt' es completamente distinto a las demás áreas.
// - No imprime tickets de cocina.
// - Se dispara cuando el mesero taps "Imprimir Cuenta" en la PWA
//   (que setea `orders.cuenta_requested_at = NOW()`).
// - Imprime UN ticket por orden con items+precios+total como una
//   cuenta formal para dar al cliente antes de pagar.
// - Marca `orders.caja_printed_at` para no reimprimir en loop.
const isReceiptMode = printArea === 'receipt';

// PRINT_ORDER_TYPES: whitelist opcional de tipos de orden a imprimir.
// Comma-separated. Valores: dine_in, to_go, delivery.
//   - Vacío / no definido → acepta todos los tipos.
//   - "dine_in"           → solo órdenes para comer aquí.
//   - "to_go,delivery"    → solo órdenes para llevar/domicilio.
// Se usa para evitar duplicados: si rasp3 imprime takeouts con
// PRINT_AREA=takeout, en rasp2 pon PRINT_ORDER_TYPES=dine_in para
// que NO imprima esos mismos takeouts.
// Cuando PRINT_AREA='takeout' esta variable se ignora — el área ya
// tiene su propio filtro implícito (to_go+delivery).
const printOrderTypes = String(process.env.PRINT_ORDER_TYPES || '')
  .toLowerCase()
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
const validOrderTypes = ['dine_in', 'to_go', 'delivery'];
for (const t of printOrderTypes) {
  if (!validOrderTypes.includes(t)) {
    console.error(`✘ PRINT_ORDER_TYPES tiene valor inválido: "${t}". Valores: ${validOrderTypes.join(', ')}.`);
    process.exit(1);
  }
}

// DRY_RUN=true → no manda nada a la impresora; imprime el ticket
// formateado en la terminal. Útil para probar localmente (p.ej. en
// Mac sin impresora térmica) que la suscripción a Supabase, el
// formato y la división en COCINA/BAR funcionan end-to-end.
const isDryRun = String(DRY_RUN || '').toLowerCase() === 'true';

const paperWidth = Math.max(20, parseInt(PAPER_WIDTH_CHARS || '48', 10));
const pauseBetweenTicketsMs = Math.max(0, parseInt(PAUSE_BETWEEN_TICKETS_MS || '5000', 10));
const restaurantName = (RESTAURANT_NAME || 'GORDITAS MIS HERMANAS').trim();

// Cuánto espera una Pi 'kitchen'/'line' sin PRINT_ORDER_TYPES configurado
// antes de imprimir la comida de una orden To Go/Delivery, para darle
// tiempo a una Pi 'takeout' dedicada (si existe) a reclamarla primero.
// Ver el uso en processOrder() — evita duplicar el ticket sin necesitar
// configurar PRINT_ORDER_TYPES=dine_in a mano en cada Pi.
const takeoutGraceMs = Math.max(0, parseInt(process.env.TAKEOUT_GRACE_MS || '6000', 10));

// 'printer' (default): comportamiento normal — imprime tickets.
// 'screen': la sucursal usa pantalla de cocina (kitchen_view de la PWA)
//   en vez de tickets físicos. El worker NO imprime nada, pero sigue
//   corriendo para que cuando el admin vuelva al modo 'printer' arranque
//   sin reiniciar el servicio. Las órdenes nuevas se ven en la pantalla
//   vía Supabase Realtime (kitchen_view ya hace eso por su cuenta).
//
// El modo se puede setear de 3 formas, en orden de precedencia:
//   1. Env var DISPLAY_MODE (override manual, p.ej. para debugging)
//   2. admin_settings.display_modes (JSON {branch:mode}) — set desde la UI
//      de admin de la PWA, refreshea cada 30s sin reiniciar el worker.
//   3. Default 'printer'.
const envDisplayMode = String(DISPLAY_MODE || '').toLowerCase();
const hasEnvOverride = envDisplayMode === 'screen' || envDisplayMode === 'printer';
let displayMode = hasEnvOverride ? envDisplayMode : 'printer';

// Cocina Especializada (toggle en Ajustes de la PWA, admin_settings.
// split_kitchen_mode — JSON {sucursal: bool}, por sucursal igual que
// display_modes). Cuando está activo para BRANCH_NAME, una Pi 'kitchen'/
// 'line' SIN PRINT_ORDER_TYPES configurado a mano deja de imprimir
// pedidos To Go/Delivery (solo imprime dine_in), igual que
// kitchen_view.dart hace con la Línea de Producción en pantalla. Se
// refresca cada 30s, ver setInterval más abajo.
let splitKitchenMode = false;

async function refreshSplitKitchenModeFromDb() {
  try {
    const { data, error } = await supabase
      .from('admin_settings')
      .select('setting_value')
      .eq('setting_key', 'split_kitchen_mode')
      .maybeSingle();
    if (error || !data?.setting_value) return;
    const modes = JSON.parse(data.setting_value);
    const newValue = modes?.[BRANCH_NAME] === true || modes?.[BRANCH_NAME] === 'true';
    if (newValue !== splitKitchenMode) {
      console.log(`🔁 Cocina Especializada cambió: ${splitKitchenMode} → ${newValue} (admin_settings)`);
      splitKitchenMode = newValue;
    }
  } catch (e) {
    // Silencioso — la próxima iteración reintenta.
  }
}

// Helper para leer el modo desde admin_settings (lo invoca un setInterval
// más abajo, después de que el cliente de supabase está creado).
async function refreshDisplayModeFromDb() {
  if (hasEnvOverride) return; // env var siempre gana
  try {
    const { data, error } = await supabase
      .from('admin_settings')
      .select('setting_value')
      .eq('setting_key', 'display_modes')
      .maybeSingle();
    if (error || !data?.setting_value) return;
    const modes = JSON.parse(data.setting_value);
    const branchMode = String(modes[BRANCH_NAME] || 'printer').toLowerCase();
    const newMode = branchMode === 'screen' ? 'screen' : 'printer';
    if (newMode !== displayMode) {
      console.log(`🔁 Modo cambió: ${displayMode} → ${newMode} (admin_settings)`);
      displayMode = newMode;
    }
  } catch (e) {
    // Silencioso — la próxima iteración reintenta.
  }
}

const requiredVars = { SUPABASE_URL, SUPABASE_SERVICE_KEY, BRANCH_NAME };
for (const [k, v] of Object.entries(requiredVars)) {
  if (!v) {
    console.error(`✘ Falta variable de entorno: ${k}. Revisa el archivo .env`);
    process.exit(1);
  }
}
// Validación de printer: ya no es exit-fatal porque el modo puede
// venir de admin_settings en runtime. Si no hay printer config y el
// modo termina siendo 'printer', el intento de impresión falla
// graceful con un log de error, pero el worker sigue vivo.
if (!isDryRun && !PRINTER_NAME && !PRINTER_DEVICE) {
  console.warn(
    '⚠ No hay PRINTER_NAME ni PRINTER_DEVICE en .env. El worker solo funcionará en modo "screen" (admin_settings.display_modes).',
  );
}

const printerTarget = PRINTER_DEVICE || PRINTER_NAME || '';

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { persistSession: false },
  realtime: wsTransport ? { transport: wsTransport } : undefined,
});

// Heartbeat: cada Pi escribe su último "estoy viva" cada ~20s en
// print_worker_heartbeats, para que la app de Caja pueda mostrar un LED
// verde/rojo por impresora sin tener que conectarse a las Raspberries a
// mano (ver lib/views/print_status_view.dart). No es crítico: si falla
// (p.ej. no se aplicó la migración todavía), no afecta la impresión.
const heartbeatArea = isReceiptMode ? 'receipt' : (printArea || 'todo-en-uno');
const heartbeatId = `${BRANCH_NAME}:${heartbeatArea}`;
async function sendHeartbeat() {
  try {
    const { error } = await supabase.from('print_worker_heartbeats').upsert({
      id: heartbeatId,
      branch_name: BRANCH_NAME,
      print_area: heartbeatArea,
      last_seen_at: new Date().toISOString(),
    });
    // supabase-js no lanza excepción en errores de BD — vienen en
    // `error`, no como throw. Sin este chequeo, un fallo (tabla sin
    // migrar, RLS, etc.) queda completamente invisible en los logs.
    if (error) {
      console.error(`⚠ Heartbeat falló (${heartbeatId}): ${error.message}`);
    }
  } catch (e) {
    console.error(`⚠ Heartbeat falló (${heartbeatId}): ${e.message}`);
  }
}

// Fake printer para DRY_RUN: misma API que ThermalPrinter pero acumula
// líneas en memoria y al execute() las vuelca a la terminal con cierto
// formato (mayúsculas para bold, ====== para drawLine, ✂️ para cut).
function buildDryRunPrinter() {
  const lines = [];
  let bold = false;
  let align = 'left';
  let scale = 'normal';
  const pad = (s) => {
    s = String(s);
    if (align === 'center') {
      const w = paperWidth;
      const trimmed = s.length > w ? s.slice(0, w) : s;
      const space = Math.max(0, Math.floor((w - trimmed.length) / 2));
      return ' '.repeat(space) + trimmed;
    }
    return s;
  };
  const fmt = (s) => {
    let out = pad(s);
    if (bold) out = out.toUpperCase();
    if (scale === 'double') out = `★ ${out} ★`;
    return out;
  };
  return {
    isPrinterConnected: async () => true,
    alignCenter: () => { align = 'center'; },
    alignLeft: () => { align = 'left'; },
    alignRight: () => { align = 'right'; },
    bold: (v) => { bold = !!v; },
    setTextDoubleHeight: () => { scale = 'double'; },
    setTextNormal: () => { scale = 'normal'; },
    println: (s) => lines.push(fmt(s)),
    newLine: () => lines.push(''),
    drawLine: () => lines.push('-'.repeat(paperWidth)),
    cut: () => lines.push('\n────────── ✂️  CORTE ──────────\n'),
    execute: async () => {
      console.log(
        '\n┌─── [DRY_RUN] Ticket(s) que se imprimirían ───┐',
      );
      for (const l of lines) console.log(l);
      console.log('└──────────────────────────────────────────────┘\n');
      lines.length = 0;
    },
  };
}

function buildPrinter() {
  if (isDryRun) return wrapPrinterAscii(buildDryRunPrinter());
  // - Windows: PRINTER_NAME="Star TSP143" → 'printer:Star TSP143' (spooler)
  // - Linux/Raspberry: PRINTER_DEVICE="/dev/usb/lp0" → escribe al device USB
  //   directamente (no requiere CUPS).
  const iface = PRINTER_DEVICE ? PRINTER_DEVICE : `printer:${PRINTER_NAME}`;
  const type = String(PRINTER_TYPE || 'epson').toLowerCase() === 'star'
    ? PrinterTypes.STAR
    : PrinterTypes.EPSON;
  const printer = new ThermalPrinter({
    type,
    interface: iface,
    width: paperWidth,
    characterSet: 'PC858_EURO',
    removeSpecialCharacters: false,
    lineCharacter: '-',
    options: { timeout: 5000 },
  });
  return wrapPrinterAscii(printer);
}

// ── Utils ───────────────────────────────────────────────────────────

// Normaliza el texto a ASCII básico: quita acentos (á→a, é→e, ñ→n, ü→u…)
// y otros diacríticos. La impresora térmica con charset PC858 a veces
// renderiza glifos raros con vocales acentuadas; con esto siempre salen
// letras "normales" sin importar la configuración del driver.
function stripAccents(s) {
  if (s == null) return s;
  return String(s)
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, ''); // combining diacritical marks
}

// Wraps un printer para que TODO lo que pase por println / drawLine /
// alignXxx pase por stripAccents primero. Solo `println` mete texto;
// el resto son comandos sin payload de string.
function wrapPrinterAscii(printer) {
  const origPrintln = printer.println.bind(printer);
  printer.println = (s) => origPrintln(stripAccents(s));
  return printer;
}

function fmtDateTime(ts) {
  const d = ts ? new Date(ts) : new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// `customer_name` viene smushed: "Mariano (Pago: efectivo) - DIR: ... - TEL: ..."
// Lo partimos para imprimirlo en líneas separadas.
function parseCustomerName(raw) {
  if (!raw) return { name: '', pago: '', dir: '', tel: '' };
  const out = { name: '', pago: '', dir: '', tel: '' };
  // name = todo antes del primer paréntesis o guion
  const m = raw.match(/^([^()\-]+)/);
  out.name = (m ? m[1] : raw).trim();
  const pago = raw.match(/\(Pago:\s*([^)]+)\)/i);
  if (pago) out.pago = pago[1].trim();
  const dir = raw.match(/-\s*DIR:\s*([^-]+?)(?:\s*-\s*TEL:|$)/i);
  if (dir) out.dir = dir[1].trim();
  const tel = raw.match(/-\s*TEL:\s*([^-]+)$/i);
  if (tel) out.tel = tel[1].trim();
  return out;
}

function parseGuisados(raw) {
  if (!raw) return [];
  try {
    const arr = JSON.parse(raw);
    return Array.isArray(arr) ? arr.filter(Boolean) : [];
  } catch {
    return [];
  }
}

// Refrescos/Aguas/Jugos comparten UN solo dish_id "representativo" en la
// BD sin importar el TAMAÑO elegido en el diálogo del mesero (ej. todo
// refresco se guarda con el id de "Refresco 355 ml vidrio", aunque el
// mesero haya elegido 600 ml) — por eso `dishes.name` no refleja el
// tamaño real. El primer guisado SÍ trae el tamaño real (ej. "600 ml",
// "355 ml", "1 litro"), así que si coincide con ese patrón, reconstruimos
// el nombre a partir de ahí en vez del nombre (potencialmente equivocado)
// de la BD. Espejo de `_drinkDisplayName` en dish_card.dart.
function correctDrinkName(rawName, guisados) {
  const sizeStr = guisados[0];
  if (!sizeStr || !/^\d+\s?(ml|litro)$/i.test(sizeStr.trim())) return rawName;
  const n = String(rawName || '').toLowerCase();
  if (n.includes('refresco')) {
    if (sizeStr.includes('355')) return 'Refresco de vidrio';
    if (sizeStr.includes('600')) return 'Refresco no retornable';
    return 'Refresco';
  }
  if (n.includes('jugo')) return 'Jugo';
  if (n.includes('agua') && !n.includes('natural')) return 'Agua Fresca';
  return rawName;
}

// Extrae el marcador de tamaño del nombre del platillo. En este proyecto
// cada tamaño es un platillo separado en `dishes` con nombre tipo:
//   "Molletes con Guisado (Orden)"  → orden entera
//   "Molletes con Guisado (1/2)"    → media orden
//   "Molletes Dulces (1/2) orden"   → media orden (variante de nomenclatura)
//   "Refresco Coca"                 → no aplica (bebida sin tamaño)
//
// Devuelve { fraction, cleanName } donde:
//   - fraction: '1' para orden entera, '1/2' para media, null si no aplica.
//   - cleanName: el nombre sin el sufijo del marcador.
function parseSizeMarker(name) {
  const s = String(name || '').trim();
  // Media orden: acepta "(1/2)" opcionalmente seguido de "orden(es)".
  const half = s.match(/\s*\(1\/2\)(\s+ord[eé]n(es)?)?\s*$/i);
  if (half) {
    return { fraction: '1/2', cleanName: s.slice(0, half.index).trim() };
  }
  // Orden entera: "(Orden)" o "(orden)" o "(órden)" al final.
  const whole = s.match(/\s*\(ord[eé]n(es)?\)\s*$/i);
  if (whole) {
    return { fraction: '1', cleanName: s.slice(0, whole.index).trim() };
  }
  return { fraction: null, cleanName: s };
}

// Etiqueta a imprimir para el marcador de tamaño: "Orden" en vez de "1",
// "Media" en vez de "1/2" — más claro para cocina que la fracción.
function fractionLabel(fraction) {
  if (fraction === '1') return 'Orden';
  if (fraction === '1/2') return 'Media';
  return fraction;
}

// ── Fetch + Format + Print ──────────────────────────────────────────
// Fetch SOLO los datos de la orden (no items). Items se traen aparte
// filtrados por printed_at IS NULL.
//
// JOIN-via-FK:
//   - table_id  → restaurant_tables.table_number (número de mesa legible)
//   - waiter_id → waiters.name (nombre del mesero)
async function fetchOrder(orderId) {
  const { data, error } = await supabase
    .from('orders')
    .select(`
      id, branch_name, order_type, customer_name, total_amount,
      table_id, waiter_id, created_at, payment_method, daily_folio,
      sent_to_kitchen_at, printed_at,
      cuenta_requested_at, caja_printed_at,
      restaurant_tables ( table_number ),
      waiters ( name )
    `)
    .eq('id', orderId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

// Trae solo los order_items que aún no se han impreso. Esto es lo que
// permite imprimir las adiciones de una orden ya enviada sin reimprimir
// los items que ya fueron a cocina.
async function fetchUnprintedItems(orderId) {
  const { data, error } = await supabase
    .from('order_items')
    .select(`
      id, quantity, price_at_time, guisados_selected, client_label,
      dishes ( name, category )
    `)
    .eq('order_id', orderId)
    .is('printed_at', null)
    .order('id', { ascending: true });
  if (error) throw error;
  return data || [];
}

// Marca los items que acabamos de imprimir. Si después de eso ya no
// quedan items sin imprimir, marca la orden como printed_at = NOW()
// también, para que la query del catch-up (printed_at IS NULL) la
// excluya y sea barata.
async function markItemsPrinted(orderId, itemIds) {
  if (itemIds.length === 0) return;
  const nowIso = new Date().toISOString();
  const { error: e1 } = await supabase
    .from('order_items')
    .update({ printed_at: nowIso })
    .in('id', itemIds);
  if (e1) throw e1;
  // ¿Quedan items sin imprimir? Si no, marca también orders.printed_at
  // para que el catch-up (filtrado por printed_at IS NULL) sea barato.
  const { count, error: e2 } = await supabase
    .from('order_items')
    .select('id', { count: 'exact', head: true })
    .eq('order_id', orderId)
    .is('printed_at', null);
  if (e2) throw e2;
  if ((count ?? 0) === 0) {
    await supabase
      .from('orders')
      .update({ printed_at: nowIso })
      .eq('id', orderId);
  }
}

// Clasifica un order_item como bebida (BAR) o comida (COCINA) usando
// la misma regla de category que `kitchen_view.dart`. El Envío FLASH
// (categoría 'Envío') se considera comida para que el cocinero vea
// que es delivery.
const DRINK_CATEGORIES = ['drink', 'alcohol', 'bebidas', 'drinks', 'aguas', 'jugos', 'cafes', 'refrescos'];
function isDrink(item) {
  const cat = (item.dishes?.category || '').toString().toLowerCase().trim();
  if (DRINK_CATEGORIES.includes(cat)) return true;
  // Respaldo por nombre: si por lo que sea la categoría no quedó bien
  // puesta en el dish, "café"/"capuchino" en el nombre igual cuenta
  // como bebida — no debe depender de que el dato esté perfecto.
  const name = (item.dishes?.name || '').toString().toLowerCase();
  return name.includes('café') || name.includes('cafe') || name.includes('capuchino');
}

// Filtra los items que esta Pi debe imprimir según PRINT_AREA. Si el
// área no está seteada, no filtra nada — el caller mantiene la lógica
// original de dos tickets (COCINA + BAR).
function filterItemsByArea(items) {
  if (!printArea) return items;
  if (printArea === 'drinks') return items.filter(isDrink);
  // 'kitchen', 'line' y 'takeout' comparten el mismo filtro de área
  // (todo lo no-bebida); se diferencian en el header y en si además
  // se filtra por order_type (takeout).
  if (printArea === 'kitchen' || printArea === 'line' || printArea === 'takeout') {
    return items.filter((it) => !isDrink(it));
  }
  return items;
}

// Normaliza el order_type de la BD a nuestro enum interno.
// La PWA usa 'takeout' pero el código estándar (y algunos legacy) usan
// 'to_go' — los tratamos como equivalentes.
function normalizeOrderType(raw) {
  const t = String(raw || '').toLowerCase().trim();
  if (t === 'takeout' || t === 'to_go' || t === 'togo') return 'to_go';
  if (t === 'delivery' || t === 'a_domicilio') return 'delivery';
  if (t === 'dine_in' || t === 'dinein' || t === 'comer_aqui') return 'dine_in';
  return t;
}

// Devuelve true si la orden matchea los filtros por tipo (order_type)
// según PRINT_AREA y/o PRINT_ORDER_TYPES.
function orderTypeMatches(order) {
  const type = normalizeOrderType(order?.order_type);
  if (printArea === 'takeout') {
    // Área takeout: implícitamente solo to_go y delivery.
    return type === 'to_go' || type === 'delivery';
  }
  if (printOrderTypes.length > 0) {
    const wanted = printOrderTypes.map(normalizeOrderType);
    return wanted.includes(type);
  }
  // Sin PRINT_ORDER_TYPES manual: si Cocina Especializada está activo,
  // 'kitchen'/'line' se comporta como si tuviera PRINT_ORDER_TYPES=dine_in.
  if ((printArea === 'kitchen' || printArea === 'line') && splitKitchenMode) {
    return type === 'dine_in';
  }
  return true;
}

// Añade un ticket completo (header → ítems → cut) al buffer del printer.
// `kind` es 'COCINA', 'BEBIDAS' o 'PARA LLEVAR'. No llama execute() — lo
// hace el caller.
// Traduce el enum order_type de la BD a un label humano en español.
// Los guisos técnicos ("dine_in") confunden a la cocina cuando aparecen
// en el ticket físico.
const ORDER_TYPE_LABELS = {
  dine_in: 'COMER AQUÍ',
  to_go: 'TO GO',
  delivery: 'A DOMICILIO',
};
function orderTypeLabel(raw) {
  // Normaliza primero para que 'takeout' → 'TO GO' también.
  const key = normalizeOrderType(raw);
  return ORDER_TYPE_LABELS[key] || (raw || 'PEDIDO').toString().toUpperCase();
}

function appendTicket(printer, kind, order, items) {
  const cust = parseCustomerName(order.customer_name);
  const tipo = orderTypeLabel(order.order_type);
  // Mesa: viene como un JOIN (restaurant_tables.table_number). Si la
  // PWA cambia el nombre del FK, cae al table_id (UUID) como fallback.
  const tableNumber = order.restaurant_tables?.table_number;
  // Mesero: igual, viene de waiters.name.
  const waiterName = order.waiters?.name;

  // ── Encabezado
  printer.alignCenter();
  printer.setTextDoubleHeight();
  printer.bold(true);
  printer.println(restaurantName);
  printer.setTextNormal();
  printer.println(kind);
  printer.bold(false);
  // Si el ticket es de BEBIDAS (bar/drinks) y la orden NO es dine_in,
  // imprime un subtítulo GRANDE con el tipo (TO GO / A DOMICILIO) para
  // que el barman sepa que la bebida va en vaso desechable, no en la barra.
  const kindNorm = String(kind || '').toUpperCase();
  const isBarTicket = kindNorm.includes('BEBIDAS') || kindNorm.includes('BAR');
  const orderTypeRaw = String(order.order_type || '').toLowerCase();
  if (isBarTicket && orderTypeRaw && orderTypeRaw !== 'dine_in') {
    printer.setTextDoubleHeight();
    printer.bold(true);
    printer.println(orderTypeLabel(order.order_type));
    printer.setTextNormal();
    printer.bold(false);
  }
  // `branch_name` en la BD ya viene como "Sucursal Maravillas", no le
  // anteponemos "Sucursal " porque salía duplicado ("Sucursal Sucursal
  // Maravillas").
  if (order.branch_name) printer.println(order.branch_name);
  printer.drawLine();

  // ── Tipo + fecha + cliente
  printer.alignLeft();
  printer.setTextNormal();
  printer.println(`Tipo: ${tipo}`);
  if (tableNumber != null) {
    printer.println(`Mesa: ${tableNumber}`);
  } else if (order.table_id) {
    // Fallback: si por alguna razón no resolvió el JOIN, mostramos el UUID
    // recortado para no romper el ticket.
    printer.println(`Mesa: ${String(order.table_id).slice(0, 8)}`);
  }
  if (waiterName) printer.println(`Mesero: ${waiterName}`);
  printer.println(`Fecha: ${fmtDateTime(order.created_at)}`);
  if (cust.name) printer.println(`Cliente: ${cust.name}`);
  if (cust.tel) printer.println(`Tel: ${cust.tel}`);
  if (cust.dir) {
    printer.println('Direccion:');
    printer.println(`  ${cust.dir}`);
  }
  if (cust.pago) printer.println(`Pago: ${cust.pago}`);
  printer.drawLine();

  // ── Ítems (sin precios — esto es ticket de producción, no recibo)
  //
  // Formato compacto ("2x Orden MOLLETES..."):
  //   "Nx <Orden|Media> NOMBRE"   si el nombre trae "(Orden)" o "(1/2)"
  //   "Nx NOMBRE"                 si no trae marcador (bebidas, etc.)
  //
  // Ejemplos:
  //   2× "Molletes con Guisado (Orden)" → "2x Orden MOLLETES CON GUISADO"
  //   3× "Molletes con Guisado (1/2)"   → "3x Media MOLLETES CON GUISADO"
  //   1× "Refresco Coca"                → "1x REFRESCO COCA"
  //
  // Cuando la mesa tiene varios clientes (client_label = "Cliente 1",
  // "Cliente 2", ...), agrupamos por cliente y ponemos una línea divisoria
  // ENTRE grupos. El label del cliente en sí no se imprime — la línea
  // separa visualmente cada pedido individual.
  const groups = [];
  const groupMap = new Map();
  for (const it of items) {
    const label = it.client_label || 'Cliente 1';
    if (!groupMap.has(label)) {
      groupMap.set(label, []);
      groups.push(groupMap.get(label));
    }
    groupMap.get(label).push(it);
  }
  for (let g = 0; g < groups.length; g++) {
    if (g > 0) printer.drawLine();
    for (const it of groups[g]) {
      const guisados = parseGuisados(it.guisados_selected);
      const rawName = correctDrinkName(it.dishes?.name || '(sin nombre)', guisados);
      const { fraction, cleanName } = parseSizeMarker(rawName);
      const qty = it.quantity || 1;
      const line = fraction
        ? `${qty}x ${fractionLabel(fraction)} ${cleanName}`
        : `${qty}x ${cleanName}`;
      printer.bold(true);
      printer.println(line);
      printer.bold(false);
      if (guisados.length) {
        printer.println(`   ${guisados.join(', ')}`);
      }
    }
  }
  printer.drawLine();

  // ── Pie
  printer.alignCenter();
  printer.println(order.daily_folio != null
    ? `Folio #${String(order.daily_folio).padStart(3, '0')}`
    : `ID: ${String(order.id).slice(0, 8)}`);
  printer.newLine();
  printer.cut();
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Imprime un ticket "solo" (su propio buffer + execute), para que el
// barman/cocinero pueda cortarlo físicamente antes de que salga el siguiente.
async function printSingleTicket(kind, order, items) {
  const printer = buildPrinter();
  const connected = await printer.isPrinterConnected();
  if (!connected) {
    throw new Error(`Impresora "${printerTarget}" no responde. Verifica USB/driver.`);
  }
  appendTicket(printer, kind, order, items);
  await printer.execute();
}

// Imprime los items dados (ya filtrados por unprinted y por área).
// Devuelve true si efectivamente mandó algo, false si no había nada.
//
// Modos:
//   - PRINT_AREA='drinks' → un solo ticket "BEBIDAS".
//   - PRINT_AREA='kitchen' → un solo ticket "COCINA".
//   - PRINT_AREA='takeout' → un solo ticket "TO GO".
//   - PRINT_AREA no seteada → COCINA primero, después BEBIDAS
//     (comportamiento original), con pausa PAUSE_BETWEEN_TICKETS_MS entre
//     ambos.
async function printItems(order, items) {
  if (!items.length) return false;
  const isAddition = !!order.printed_at;

  if (printArea === 'drinks') {
    await printSingleTicket(isAddition ? 'BEBIDAS — ADICIÓN' : 'BEBIDAS', order, items);
    return true;
  }
  if (printArea === 'kitchen') {
    await printSingleTicket(isAddition ? 'COCINA — ADICIÓN' : 'COCINA', order, items);
    return true;
  }
  if (printArea === 'line') {
    await printSingleTicket(
      isAddition ? 'LÍNEA DE PRODUCCIÓN — ADICIÓN' : 'LÍNEA DE PRODUCCIÓN',
      order,
      items,
    );
    return true;
  }
  if (printArea === 'takeout') {
    await printSingleTicket(
      isAddition ? 'TO GO — ADICIÓN' : 'TO GO',
      order,
      items,
    );
    return true;
  }

  const drinks = items.filter(isDrink);
  const kitchen = items.filter((it) => !isDrink(it));

  if (kitchen.length) {
    await printSingleTicket(
      isAddition ? 'COCINA — ADICIÓN' : 'COCINA',
      order,
      kitchen,
    );
  }

  if (drinks.length && kitchen.length && pauseBetweenTicketsMs > 0) {
    await sleep(pauseBetweenTicketsMs);
  }

  if (drinks.length) {
    await printSingleTicket(
      isAddition ? 'BEBIDAS — ADICIÓN' : 'BEBIDAS',
      order,
      drinks,
    );
  }

  return true;
}

// Lock en memoria para no procesar la misma orden en paralelo (puede
// pasar si realtime entrega un evento mientras el catch-up trabaja).
const _inFlight = new Set();

async function processOrder(orderId, source = 'unknown') {
  if (_inFlight.has(orderId)) {
    return; // ya hay otro procesando esta orden
  }
  _inFlight.add(orderId);
  try {
    const order = await fetchOrder(orderId);
    if (!order) {
      console.warn(`⚠ Orden ${orderId} no encontrada (${source})`);
      return;
    }
    if (order.branch_name !== BRANCH_NAME) return; // otra sucursal
    if (!order.sent_to_kitchen_at) return;         // aún no mandada a cocina

    // Modo pantalla: la sucursal usa kitchen_view en la pantalla en vez
    // de tickets. No imprimimos y no marcamos printed_at (kitchen_view
    // tiene su propio flujo de "marcar como listo"). Solo logueamos por
    // visibilidad.
    if (displayMode === 'screen') {
      console.log(`🖥  ${orderId} — modo pantalla, no se imprime (${source})`);
      return;
    }

    // Filtro por tipo de orden (dine_in / to_go / delivery). Si la
    // orden no matchea el whitelist de esta Pi, la ignoramos completa.
    if (!orderTypeMatches(order)) return;

    const allUnprinted = await fetchUnprintedItems(orderId);
    if (allUnprinted.length === 0) return; // todo ya impreso, nada que hacer

    // Si esta Pi tiene PRINT_AREA, se queda solo con los items de su
    // área. Los items de OTRAS áreas quedan intactos (printed_at=null)
    // para que la Pi de ese área los procese cuando le toque.
    let items = filterItemsByArea(allUnprinted);
    if (items.length === 0) return; // nada de MI área en esta orden

    // Salvavidas contra tickets duplicados sin necesitar configurar
    // PRINT_ORDER_TYPES en cada Pi a mano: si esta Pi es 'kitchen'/'line'
    // (por defecto imprime TODA la comida, sin filtrar por tipo de
    // orden) y la orden es To Go/Delivery, esperamos un poco para darle
    // tiempo a una Pi 'takeout' dedicada (si existe) de reclamarla
    // primero. Si al revisar de nuevo ya se imprimió, no la duplicamos
    // aquí. Si no hay ninguna Pi 'takeout' en la sucursal, se imprime
    // igual — solo se atrasa unos segundos.
    if (
      (printArea === 'kitchen' || printArea === 'line') &&
      printOrderTypes.length === 0
    ) {
      const type = normalizeOrderType(order.order_type);
      if (type === 'to_go' || type === 'delivery') {
        await sleep(takeoutGraceMs);
        const recheck = await fetchUnprintedItems(orderId);
        const recheckIds = new Set(recheck.map((it) => it.id));
        items = items.filter((it) => recheckIds.has(it.id));
        if (items.length === 0) {
          console.log(`↷ ${orderId} — ya lo imprimió la Pi de Para Llevar, omitido (${source})`);
          return;
        }
      }
    }

    const tag = order.printed_at ? 'adición' : 'primera';
    const areaTag = printArea ? ` [${printArea}]` : '';
    console.log(
      `→ Imprimiendo ${items.length} item(s) de ${orderId} (${source}, ${tag}${areaTag})...`,
    );
    const printed = await printItems(order, items);
    if (!printed) return; // por si acaso
    await markItemsPrinted(
      orderId,
      items.map((it) => it.id),
    );
    console.log(`✓ ${orderId} — ${items.length} item(s) impresos y marcados`);
  } catch (e) {
    console.error(`✘ Falló orden ${orderId}: ${e.message}`);
    // No marcamos printed_at en items → vuelven a entrar al siguiente
    // catch-up (cada 60s) o al próximo evento de realtime.
  } finally {
    _inFlight.delete(orderId);
  }
}

// ── Catch-up al arrancar y cada 60s (red de seguridad por si Realtime
//    se cae y no nos enteramos) ──────────────────────────────────────
//
// Solo imprime órdenes que ya fueron "mandadas a cocina" por el mesero
// (sent_to_kitchen_at IS NOT NULL). Las órdenes del cliente que aún
// no aprueba el mesero quedan en cola sin tocar.
async function catchUp() {
  const { data, error } = await supabase
    .from('orders')
    .select('id')
    .eq('branch_name', BRANCH_NAME)
    .not('sent_to_kitchen_at', 'is', null)
    .is('printed_at', null)
    .order('sent_to_kitchen_at', { ascending: true })
    .limit(50);
  if (error) {
    console.error('Catch-up falló:', error.message);
    return;
  }
  if (!data?.length) return;
  console.log(`Catch-up: ${data.length} orden(es) pendiente(s)`);
  for (const o of data) {
    await processOrder(o.id, 'catch-up');
  }
}

// Defensive: el realtime UPDATE dispara para CUALQUIER cambio en la
// fila (p.ej. el mesero edita total). Antes de imprimir, re-checamos
// el gate contra la BD para no imprimir si ya está impresa o si el
// sent_to_kitchen_at sigue null.
function isReadyToPrint(row) {
  return !!row?.sent_to_kitchen_at && !row?.printed_at;
}

// ─── Modo RECEIPT (impresora de caja) ──────────────────────────────
// Fetch de items con precios (para el ticket de cuenta, no filtramos
// por printed_at porque queremos TODO lo que el cliente pidió).
async function fetchAllItemsForOrder(orderId) {
  const { data, error } = await supabase
    .from('order_items')
    .select(`
      id, quantity, price_at_time, guisados_selected, client_label,
      dishes ( name, category )
    `)
    .eq('order_id', orderId)
    .order('id', { ascending: true });
  if (error) throw error;
  return data || [];
}

// Imprime la CUENTA (recibo con precios) — formato distinto al ticket
// de cocina. Incluye items+precios, subtotal, total, y espacio para firma.
function appendCuentaTicket(printer, order, items) {
  const cust = parseCustomerName(order.customer_name);
  const tipo = orderTypeLabel(order.order_type);
  const tableNumber = order.restaurant_tables?.table_number;
  const waiterName = order.waiters?.name;

  // ── Encabezado
  printer.alignCenter();
  printer.setTextDoubleHeight();
  printer.bold(true);
  printer.println(restaurantName);
  printer.setTextNormal();
  printer.println('CUENTA');
  printer.bold(false);
  if (order.branch_name) printer.println(order.branch_name);
  printer.drawLine();

  // ── Info general
  printer.alignLeft();
  printer.println(`Tipo: ${tipo}`);
  if (tableNumber != null) {
    printer.println(`Mesa: ${tableNumber}`);
  }
  if (waiterName) printer.println(`Mesero: ${waiterName}`);
  printer.println(`Fecha: ${fmtDateTime(order.created_at)}`);
  if (cust.name) printer.println(`Cliente: ${cust.name}`);
  printer.drawLine();

  // ── Items con precios (agrupados por client_label)
  const groups = [];
  const groupMap = new Map();
  for (const it of items) {
    const label = it.client_label || 'Cliente 1';
    if (!groupMap.has(label)) {
      groupMap.set(label, []);
      groups.push(groupMap.get(label));
    }
    groupMap.get(label).push(it);
  }
  let total = 0;
  for (let g = 0; g < groups.length; g++) {
    if (g > 0) printer.drawLine();
    for (const it of groups[g]) {
      const guisados = parseGuisados(it.guisados_selected);
      const rawName = correctDrinkName(it.dishes?.name || '(sin nombre)', guisados);
      const { fraction, cleanName } = parseSizeMarker(rawName);
      const qty = it.quantity || 1;
      const price = Number(it.price_at_time || 0);
      const subtotal = price * qty;
      total += subtotal;
      const line = fraction
        ? `${qty}x ${fractionLabel(fraction)} ${cleanName}`
        : `${qty}x ${cleanName}`;
      // Nombre a la izquierda, precio a la derecha en la misma línea
      const priceStr = `$${subtotal.toFixed(2)}`;
      const nameWidth = paperWidth - priceStr.length - 1;
      const nameTrunc = line.length > nameWidth
        ? line.slice(0, nameWidth)
        : line.padEnd(nameWidth, ' ');
      printer.bold(true);
      printer.println(`${nameTrunc} ${priceStr}`);
      printer.bold(false);
      if (guisados.length) {
        printer.println(`   ${guisados.join(', ')}`);
      }
    }
  }
  printer.drawLine();

  // ── Total
  printer.alignRight();
  printer.setTextDoubleHeight();
  printer.bold(true);
  printer.println(`TOTAL: $${total.toFixed(2)}`);
  printer.setTextNormal();
  printer.bold(false);
  printer.newLine();

  // ── Pie
  printer.alignCenter();
  printer.println('Gracias por su preferencia');
  printer.println(order.daily_folio != null
    ? `Folio #${String(order.daily_folio).padStart(3, '0')}`
    : `ID: ${String(order.id).slice(0, 8)}`);
  printer.newLine();
  printer.newLine();
  printer.cut();
}

async function printCuenta(order, items) {
  const printer = buildPrinter();
  const connected = await printer.isPrinterConnected();
  if (!connected) {
    throw new Error(`Impresora "${printerTarget}" no responde. Verifica USB/driver.`);
  }
  appendCuentaTicket(printer, order, items);
  await printer.execute();
}

// ── Corte del día ───────────────────────────────────────────────────
// Se dispara cuando la caja inserta una fila en `corte_requests` (botón
// "Imprimir Corte del Día" en Reportes). A diferencia de la cuenta, no
// está atado a una orden: agrega TODAS las órdenes completadas de HOY
// para esta sucursal, agrupadas por método de pago, más los
// movimientos de caja (fondo inicial/entradas/salidas) para calcular
// el efectivo que debería haber físicamente en la caja.
//
// Clasificación de payment_method (mismo criterio que usa la vista de
// Reportes en la app para no mostrar números distintos entre pantalla
// y ticket impreso):
//   - 'mixed' (o con amount_cash/amount_card presentes): se reparte
//     entre efectivo y tarjeta según esos montos exactos.
//   - contiene 'cash'/'efectivo': todo el total va a efectivo.
//   - contiene 'openpay'/'trans': todo el total va a "otros".
//   - cualquier otro valor (card, clip, mercado, tarjeta...): tarjeta.
async function fetchCorteSummary(branchName) {
  const now = new Date();
  const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);

  const { data: orders, error } = await supabase
    .from('orders')
    .select('id, total_amount, payment_method, amount_cash, amount_card')
    .eq('branch_name', branchName)
    .eq('status', 'completed')
    .gte('created_at', startOfDay.toISOString());
  if (error) throw error;

  let efectivo = 0;
  let tarjeta = 0;
  let otros = 0;
  let count = 0;
  for (const o of orders || []) {
    count++;
    const total = Number(o.total_amount || 0);
    const pm = String(o.payment_method || '').toLowerCase();
    if (pm.includes('mixed') || o.amount_cash != null || o.amount_card != null) {
      efectivo += Number(o.amount_cash || 0);
      tarjeta += Number(o.amount_card || 0);
    } else if (pm.includes('cash') || pm.includes('efectivo')) {
      efectivo += total;
    } else if (pm.includes('openpay') || pm.includes('trans')) {
      otros += total;
    } else {
      tarjeta += total;
    }
  }

  const { data: movs, error: movsError } = await supabase
    .from('cash_movements')
    .select('type, category, amount')
    .eq('branch_name', branchName)
    .gte('created_at', startOfDay.toISOString());
  if (movsError) throw movsError;

  let fondoInicial = 0;
  let entradas = 0;
  let salidas = 0;
  for (const m of movs || []) {
    const amt = Number(m.amount || 0);
    if (m.category === 'apertura') {
      fondoInicial += amt;
    } else if (m.type === 'entrada') {
      entradas += amt;
    } else if (m.type === 'salida') {
      salidas += amt;
    }
  }

  const total = efectivo + tarjeta + otros;
  const efectivoEsperado = fondoInicial + efectivo + entradas - salidas;
  return { date: now, count, efectivo, tarjeta, otros, total, fondoInicial, entradas, salidas, efectivoEsperado };
}

function appendCorteTicket(printer, summary, branchName) {
  const row = (label, amt) => {
    const amtStr = `$${amt.toFixed(2)}`;
    const width = paperWidth - amtStr.length - 1;
    const labelTrunc = label.length > width ? label.slice(0, width) : label.padEnd(width, ' ');
    printer.println(`${labelTrunc} ${amtStr}`);
  };

  printer.alignCenter();
  printer.setTextDoubleHeight();
  printer.bold(true);
  printer.println(restaurantName);
  printer.setTextNormal();
  printer.println('CORTE DEL DIA');
  printer.bold(false);
  if (branchName) printer.println(branchName);
  printer.drawLine();

  printer.alignLeft();
  printer.println(`Fecha: ${fmtDateTime(summary.date)}`);
  printer.println(`Ordenes cobradas: ${summary.count}`);
  printer.drawLine();

  row('Efectivo', summary.efectivo);
  row('Tarjeta', summary.tarjeta);
  if (summary.otros > 0) row('Otros (transf/openpay)', summary.otros);
  printer.drawLine();
  printer.bold(true);
  row('TOTAL VENTAS', summary.total);
  printer.bold(false);
  printer.newLine();

  row('Fondo inicial', summary.fondoInicial);
  if (summary.entradas > 0) row('Entradas extra', summary.entradas);
  if (summary.salidas > 0) row('Salidas/gastos', -summary.salidas);
  printer.drawLine();
  printer.bold(true);
  row('EFECTIVO ESPERADO', summary.efectivoEsperado);
  printer.bold(false);

  printer.alignCenter();
  printer.newLine();
  printer.println(fmtDateTime());
  printer.newLine();
  printer.newLine();
  printer.cut();
}

async function printCorte(summary, branchName) {
  const printer = buildPrinter();
  const connected = await printer.isPrinterConnected();
  if (!connected) {
    throw new Error(`Impresora "${printerTarget}" no responde. Verifica USB/driver.`);
  }
  appendCorteTicket(printer, summary, branchName);
  await printer.execute();
}

async function markCorteRequestPrinted(requestId) {
  const { error } = await supabase
    .from('corte_requests')
    .update({ printed_at: new Date().toISOString() })
    .eq('id', requestId);
  if (error) throw error;
}

async function processCorteRequest(requestId, branchName, source = 'unknown') {
  const flightKey = `corte:${requestId}`;
  if (_inFlight.has(flightKey)) return;
  _inFlight.add(flightKey);
  try {
    console.log(`→ Imprimiendo CORTE DEL DÍA de ${branchName} (${source})...`);
    const summary = await fetchCorteSummary(branchName);
    await printCorte(summary, branchName);
    await markCorteRequestPrinted(requestId);
    console.log(`✓ Corte ${requestId} impreso y marcado`);
  } catch (e) {
    console.error(`✘ Falló corte ${requestId}: ${e.message}`);
  } finally {
    _inFlight.delete(flightKey);
  }
}

async function catchUpCorteRequests() {
  const { data, error } = await supabase
    .from('corte_requests')
    .select('id, branch_name')
    .eq('branch_name', BRANCH_NAME)
    .is('printed_at', null)
    .order('requested_at', { ascending: true })
    .limit(20);
  if (error) {
    console.error('Catch-up corte falló:', error.message);
    return;
  }
  if (!data?.length) return;
  console.log(`Catch-up corte: ${data.length} solicitud(es) pendiente(s)`);
  for (const r of data) {
    await processCorteRequest(r.id, r.branch_name, 'catch-up');
  }
}

// Si el canal se cae (CHANNEL_ERROR/TIMED_OUT/CLOSED — ej. tras un corte
// de conexión con Supabase) el cliente NO se reconecta solo; sin esto,
// el worker se queda dependiendo únicamente del catch-up cada 60s (los
// tickets tardan hasta 1 minuto en salir en vez de ser instantáneos).
function isDeadChannelStatus(status) {
  return status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED';
}

function subscribeRealtimeCorteRequests() {
  const channel = supabase
    .channel('corte-requests-worker')
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'corte_requests',
        filter: `branch_name=eq.${BRANCH_NAME}`,
      },
      (payload) => {
        if (payload?.new?.id) {
          processCorteRequest(payload.new.id, payload.new.branch_name, 'realtime-insert');
        }
      },
    )
    .subscribe((status) => {
      console.log(`Realtime corte: ${status}`);
      if (isDeadChannelStatus(status)) {
        console.warn('Realtime corte desconectado, reintentando en 3s...');
        supabase.removeChannel(channel);
        setTimeout(subscribeRealtimeCorteRequests, 3000);
      }
    });
  return channel;
}

async function markCajaPrinted(orderId) {
  const { error } = await supabase
    .from('orders')
    .update({ caja_printed_at: new Date().toISOString() })
    .eq('id', orderId);
  if (error) throw error;
}

async function processReceipt(orderId, source = 'unknown') {
  if (_inFlight.has(orderId)) return;
  _inFlight.add(orderId);
  try {
    const order = await fetchOrder(orderId);
    if (!order) {
      console.warn(`⚠ Orden ${orderId} no encontrada (${source})`);
      return;
    }
    if (order.branch_name !== BRANCH_NAME) return;
    // Guard: solo imprimir si el mesero pidió cuenta y aún no imprimimos.
    if (!order.cuenta_requested_at) return;
    if (order.caja_printed_at) return;

    const items = await fetchAllItemsForOrder(orderId);
    if (items.length === 0) {
      console.log(`⚠ ${orderId} no tiene items — se marca como impresa igual`);
      await markCajaPrinted(orderId);
      return;
    }

    console.log(
      `→ Imprimiendo CUENTA de ${orderId} (${items.length} item(s), ${source})...`,
    );
    await printCuenta(order, items);
    await markCajaPrinted(orderId);
    console.log(`✓ ${orderId} — cuenta impresa y marcada`);
  } catch (e) {
    console.error(`✘ Falló cuenta ${orderId}: ${e.message}`);
  } finally {
    _inFlight.delete(orderId);
  }
}

async function catchUpReceipts() {
  const { data, error } = await supabase
    .from('orders')
    .select('id')
    .eq('branch_name', BRANCH_NAME)
    .not('cuenta_requested_at', 'is', null)
    .is('caja_printed_at', null)
    .order('cuenta_requested_at', { ascending: true })
    .limit(50);
  if (error) {
    console.error('Catch-up receipts falló:', error.message);
    return;
  }
  if (!data?.length) return;
  console.log(`Catch-up receipts: ${data.length} cuenta(s) pendiente(s)`);
  for (const o of data) {
    await processReceipt(o.id, 'catch-up');
  }
}

function isReadyForReceipt(row) {
  return !!row?.cuenta_requested_at && !row?.caja_printed_at;
}

function subscribeRealtimeReceipts() {
  const channel = supabase
    .channel('orders-receipt-worker')
    .on(
      'postgres_changes',
      {
        event: 'UPDATE',
        schema: 'public',
        table: 'orders',
        filter: `branch_name=eq.${BRANCH_NAME}`,
      },
      (payload) => {
        if (isReadyForReceipt(payload?.new)) {
          processReceipt(payload.new.id, 'realtime-update');
        }
      },
    )
    .subscribe((status) => {
      console.log(`Realtime: ${status}`);
      if (isDeadChannelStatus(status)) {
        console.warn('Realtime recibo desconectado, reintentando en 3s...');
        supabase.removeChannel(channel);
        setTimeout(subscribeRealtimeReceipts, 3000);
      }
    });
  return channel;
}

// ── Realtime subscription ───────────────────────────────────────────
function subscribeRealtime() {
  const channel = supabase
    .channel('orders-print-worker')
    // INSERT — cuando el mesero crea orden ya con sent_to_kitchen_at
    // seteado (su "guardar" es el "mandar a cocina" de una vez).
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'orders',
        filter: `branch_name=eq.${BRANCH_NAME}`,
      },
      (payload) => {
        if (isReadyToPrint(payload?.new)) {
          processOrder(payload.new.id, 'realtime-insert');
        }
      },
    )
    // UPDATE — cuando el mesero toca "Mandar a cocina" en una orden
    // del cliente que estaba esperando aprobación.
    .on(
      'postgres_changes',
      {
        event: 'UPDATE',
        schema: 'public',
        table: 'orders',
        filter: `branch_name=eq.${BRANCH_NAME}`,
      },
      (payload) => {
        if (isReadyToPrint(payload?.new)) {
          processOrder(payload.new.id, 'realtime-update');
        }
      },
    )
    .subscribe((status) => {
      console.log(`Realtime: ${status}`);
      if (isDeadChannelStatus(status)) {
        console.warn('Realtime órdenes desconectado, reintentando en 3s...');
        supabase.removeChannel(channel);
        setTimeout(subscribeRealtime, 3000);
      }
    });
  return channel;
}

// ── Test print ──────────────────────────────────────────────────────
async function testPrint() {
  const target = isDryRun ? 'DRY_RUN (terminal)' : `"${printerTarget}"`;
  console.log(`Imprimiendo ticket de prueba en ${target}...`);
  const printer = buildPrinter();
  const ok = await printer.isPrinterConnected();
  if (!ok) {
    console.error('✘ Impresora no conectada. Revisa el cable USB y el nombre.');
    process.exit(2);
  }
  printer.alignCenter();
  printer.setTextDoubleHeight();
  printer.bold(true);
  printer.println('TEST');
  printer.setTextNormal();
  printer.bold(false);
  printer.println('Print-worker activo');
  printer.println(fmtDateTime());
  printer.drawLine();
  printer.println(`Sucursal: ${BRANCH_NAME}`);
  printer.println(`Modo: ${isDryRun ? 'DRY_RUN' : `Impresora ${printerTarget}`}`);
  printer.println(`Ancho: ${paperWidth} cols`);
  printer.newLine();
  printer.cut();
  await printer.execute();
  console.log('✓ Test impreso.');
  process.exit(0);
}

// ── Main ────────────────────────────────────────────────────────────
async function main() {
  if (process.argv.includes('--test')) {
    await testPrint();
    return;
  }

  // Lee el modo inicial desde admin_settings (si no hay env var override).
  // El env var DISPLAY_MODE siempre gana — útil para forzar el modo en
  // un Pi específico independiente de lo que diga el admin.
  await refreshDisplayModeFromDb();
  await refreshSplitKitchenModeFromDb();

  const modeSrc = hasEnvOverride ? 'env var' : 'admin_settings';
  const modeLabel = displayMode === 'screen'
    ? `🖥  Modo pantalla (${modeSrc}, no imprime)`
    : isDryRun
      ? '🧪 DRY_RUN (terminal)'
      : `Impresora: ${printerTarget} (${paperWidth} cols, modo via ${modeSrc})`;
  const areaLabel = printArea ? ` | Área: ${printArea}` : ' | Área: todo (COCINA+BAR)';
  const orderTypesLabel = printOrderTypes.length > 0
    ? ` | Tipos: ${printOrderTypes.join(',')}`
    : '';
  console.log(
    `Print-worker iniciado | Sucursal: ${BRANCH_NAME}${areaLabel}${orderTypesLabel} | ${modeLabel}`,
  );

  await sendHeartbeat();
  setInterval(sendHeartbeat, 20_000);

  if (isReceiptMode) {
    // Modo caja/recibo: escucha `cuenta_requested_at` y no toca los
    // items ni printed_at (esos son del ticket de cocina).
    await catchUpReceipts();
    subscribeRealtimeReceipts();
    setInterval(catchUpReceipts, 60_000);

    await catchUpCorteRequests();
    subscribeRealtimeCorteRequests();
    setInterval(catchUpCorteRequests, 30_000);
  } else {
    // Modo normal: ticket de cocina (drinks/kitchen/line/takeout).
    await catchUp();
    subscribeRealtime();
    setInterval(catchUp, 60_000);
  }
  // Refresca el display mode desde admin_settings cada 30 s (si no hay
  // env override). Permite al admin cambiar el modo desde la UI de la
  // PWA y el worker se ajusta sin reiniciar.
  if (!hasEnvOverride) {
    setInterval(refreshDisplayModeFromDb, 30_000);
  }
  setInterval(refreshSplitKitchenModeFromDb, 30_000);
}

main().catch((e) => {
  console.error('Error fatal:', e);
  process.exit(1);
});

process.on('SIGINT', () => {
  console.log('\nDeteniendo print-worker...');
  process.exit(0);
});
