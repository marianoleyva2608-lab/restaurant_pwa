# Print-worker

Mini servicio Node.js que corre en la mini-PC de cocina (Windows). Escucha la tabla `orders` de Supabase y manda cada orden nueva a la impresora térmica Star TSP143 conectada por USB.

```
┌────────────┐   realtime   ┌──────────────┐    ESC-POS    ┌──────────┐
│  Supabase  │ ───────────► │ print-worker │ ────────────► │ TSP143   │
│  (orders)  │              │  (Node.js)   │   via Windows │ (USB)    │
└────────────┘              └──────────────┘    spooler    └──────────┘
```

Marca cada orden como `printed_at = NOW()` después de imprimir, así no se duplican tickets ni cuando se reinicia el worker.

## Probar localmente (Mac/Linux, sin impresora)

Para verificar que el flujo de Supabase → ticket funciona end-to-end sin tener que estar frente a la Star, usa el modo **DRY_RUN**:

```bash
cd print-worker
npm install
cp .env.example .env
# Edita .env:
#   SUPABASE_URL=...
#   SUPABASE_SERVICE_KEY=...
#   BRANCH_NAME=Sucursal Maravillas
#   DRY_RUN=true        ← clave
npm start
```

El worker se conecta a Supabase de verdad, pero en vez de mandar bytes ESC-POS a una impresora, te dibuja el ticket en la **terminal** con la división COCINA/BEBIDAS. Ejemplo de output cuando alguien aprueba un pedido desde la PWA:

```
Print-worker iniciado | Sucursal: Maravillas | 🧪 DRY_RUN (terminal)
Realtime: SUBSCRIBED
→ Imprimiendo abc-1234 (realtime-update)...

┌─── [DRY_RUN] Ticket(s) que se imprimirían ───┐
                  COCINA
            Sucursal Maravillas
------------------------------------------------
Tipo: DELIVERY
Fecha: 16/06/2026 22:14
Cliente: Mariano
Tel: 4491234567
Direccion:
  Calle Moscatell, Fracc. Arboledas
------------------------------------------------
2 X GORDITA DE ASADA
   Bistec, Chicharrón
1 X ENVÍO FLASH
------------------------------------------------
                ID: abc-1234

────────── ✂️  CORTE ──────────

                 BEBIDAS
            Sucursal Maravillas
------------------------------------------------
1 X REFRESCO 600ML
   Coca-Cola
------------------------------------------------
                ID: abc-1234

────────── ✂️  CORTE ──────────
└──────────────────────────────────────────────┘

✓ abc-1234 impresa y marcada
```

`printed_at` se marca igual en la BD — así puedes verificar el ciclo completo. Cuando estés listo para producción en la mini-PC, quita `DRY_RUN=true` del `.env`.

## Varias Pis en la misma sucursal (`PRINT_AREA`)

Cuando quieres separar la impresión en **más de una Pi** (típicamente una para cocina y otra para bebidas), setea `PRINT_AREA` en el `.env` de cada Pi:

| Pi | `PRINT_AREA` | `PRINT_ORDER_TYPES` | Qué imprime |
|---|---|---|---|
| Bebidas / barra | `drinks` | (vacío) | Solo items de categoría `drink`, `alcohol`, `bebidas` o `drinks`. Ticket titulado **BEBIDAS**. |
| Cocina | `kitchen` | (vacío o `dine_in`) | Todo lo que NO es bebida. Ticket titulado **COCINA**. |
| Línea de producción | `line` | (vacío o `dine_in`) | Mismo filtro que `kitchen`, pero el ticket dice **LÍNEA DE PRODUCCIÓN**. Para sucursales que llaman "línea" al área de comida (p.ej. Pocitos). |
| Para llevar | `takeout` | (auto — ignora esta var) | Comida (no bebida) SOLO de órdenes `to_go` o `delivery`. Ticket titulado **TO GO**. |
| Cuenta / caja | `receipt` | (no aplica) | No imprime tickets de cocina — imprime la CUENTA (items+precios+total) cuando el mesero pide "Imprimir Cuenta" en la PWA. |
| Todo-en-uno | (vacío o no definido) | (vacío) | Comportamiento original: **COCINA** y **BEBIDAS** en la misma impresora, con pausa entre ambos. |

**Ejemplo Maravillas con 4 Pis (bebidas + cocina + para llevar + cuenta):**

```
rasp1 (bebidas):     PRINT_AREA=drinks
rasp2 (cocina):      PRINT_AREA=kitchen     PRINT_ORDER_TYPES=dine_in
rasp3 (para llevar): PRINT_AREA=takeout
rasp4 (cuenta/caja): PRINT_AREA=receipt
```

**Ejemplo Pocitos con 3 Pis (bebidas + línea + para llevar):**

```
rasp1 (bebidas):     PRINT_AREA=drinks
rasp2 (línea):       PRINT_AREA=line       PRINT_ORDER_TYPES=dine_in
rasp3 (para llevar): PRINT_AREA=takeout
```

Sin el `PRINT_ORDER_TYPES=dine_in` en rasp2, esa Pi imprimiría también los takeouts que rasp3 imprime — resultando en doble ticket (rasp2 marcaría los items y rasp3 no vería nada). Con el filtro, los takeouts caen SOLO en rasp3.

**Cocina Especializada** (toggle en Ajustes de la PWA, por sucursal): si está activo, una Pi `kitchen`/`line` sin `PRINT_ORDER_TYPES` configurado deja de imprimir To Go/Delivery automáticamente (equivalente a `PRINT_ORDER_TYPES=dine_in`). Si está apagado (Modo Unificado), esa Pi imprime todo, incluyendo To Go — aunque haya una Pi `takeout` dedicada que también los imprima (duplicado intencional, igual que en pantalla).

Cada Pi marca solo los `order_items` que le tocaron por id — cuando la última termina, se marca también `orders.printed_at`. Si dejas `PRINT_AREA` vacía en **dos Pis distintas** de la misma sucursal, ambas se pelean por la orden y solo una imprime.

## Instalación en Raspberry Pi (recomendado)

Para desplegar varias Pis igual (p.ej. las 4 de Maravillas), usa el instalador automático:

```bash
# En cada Pi, con la carpeta print-worker/ ya copiada/clonada:
cd print-worker
./install.sh
```

Te pregunta `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `BRANCH_NAME` (default `Sucursal Maravillas`) y el rol de esa Pi (bebidas/cocina/para llevar/cuenta/todo-en-uno). Instala Node.js si falta, corre `npm install`, agrega tu usuario al grupo `lp` (acceso al USB de la impresora) y deja el worker corriendo como servicio systemd (`print-worker`) que arranca solo al prender la Pi y se reinicia si crashea.

Repite en las 4 Pis, eligiendo un rol distinto en cada una (bebidas, cocina, para llevar, cuenta/caja — ver tabla de `PRINT_AREA` arriba).

Comandos útiles después de instalar:
```bash
sudo journalctl -u print-worker -f     # logs en vivo
sudo systemctl restart print-worker    # reiniciar tras editar .env
nano print-worker/.env                 # editar config
```

## Pre-requisitos en la mini-PC (instalación manual / Windows)

1. **Windows 10 / 11** (probado en estos).
2. **Driver de la impresora** — Star *futurePRNT* o Star *LineMode*. Descárgalo de https://starmicronics.com/support/products/tsp100futureprnt/ y, durante la instalación, elige el modelo TSP143 USB. Al final debe aparecer la impresora en *Devices and Printers* con un nombre como `Star TSP143 (TSP100)`.
3. **Node.js LTS (18+)** — https://nodejs.org/ → descarga el `Windows Installer (.msi)` de la versión LTS y siguiente-siguiente-finalizar.

## Instalación del worker

1. **Clona o copia este folder** en la mini-PC, p. ej. `C:\restaurant\print-worker\`.

2. Abre **PowerShell** en esa carpeta y corre:
   ```powershell
   npm install
   ```
   Tarda 1-2 minutos. Crea `node_modules/`.

3. **Configura el `.env`** — copia la plantilla y llena los valores:
   ```powershell
   copy .env.example .env
   notepad .env
   ```
   Llena:
   - `SUPABASE_URL` — del dashboard de Supabase (Project Settings → API).
   - `SUPABASE_SERVICE_KEY` — la **service_role** key (no la anon). Te da acceso full a la BD; no la pegues en chats ni la subas a git.
   - `PRINTER_NAME` — el nombre EXACTO de la impresora en Windows. Para verlo: Panel de control → *Devices and Printers* → click derecho en la Star → *Printer properties* → pestaña *General* → campo *Name*.
   - `BRANCH_NAME` — el nombre de tu sucursal, EXACTO como está en `orders.branch_name` (incluye el prefijo "Sucursal "; p. ej. `Sucursal Maravillas`, `Sucursal Pocitos`).

4. **Aplica la migración** en Supabase (solo una vez, en el dashboard SQL Editor):
   ```sql
   -- supabase/migrations/20260616050000_add_printed_at_to_orders.sql
   ALTER TABLE orders ADD COLUMN IF NOT EXISTS printed_at TIMESTAMPTZ NULL;
   ```
   *(Esta migración ya viene en el repo del PWA — si usas `supabase db push` se aplica sola.)*

5. **Prueba la impresora** — debe sacar un ticket de prueba:
   ```powershell
   npm run test-print
   ```
   Si dice `✘ Impresora no conectada`, revisa el cable USB y que el nombre en `.env` coincida exactamente con el de Windows.

6. **Arranca el worker**:
   ```powershell
   npm start
   ```
   Si todo está bien, verás:
   ```
   Print-worker iniciado | Sucursal: Maravillas | Impresora: Star TSP143 (TSP100)
   Realtime: SUBSCRIBED
   ```
   Manda una orden de prueba desde la PWA — el ticket debe salir en segundos.

## Que arranque solo al prender la mini-PC

Para que no tengas que abrir PowerShell cada vez, instálalo como **servicio de Windows** con [NSSM](https://nssm.cc/download):

1. Descarga NSSM, descomprime, y desde PowerShell **como administrador**:
   ```powershell
   nssm install RestauPrintWorker
   ```
2. En la ventana que abre:
   - *Path*: `C:\Program Files\nodejs\node.exe`
   - *Startup directory*: `C:\restaurant\print-worker\`
   - *Arguments*: `index.js`
3. Pestaña *I/O* → redirige *stdout* y *stderr* a un archivo, p. ej. `C:\restaurant\print-worker\worker.log` (para troubleshoot).
4. *Install service* → ya arranca solo al booteo.

Para verificarlo: reinicia la mini-PC, manda una orden desde otro dispositivo, debe imprimirse. Si no, abre `worker.log` y mándame el error.

## Troubleshooting

| Síntoma | Causa probable | Fix |
|---|---|---|
| `Falta variable de entorno` | `.env` mal llenado | Verifica que las 4 vars estén y sin comillas. |
| `Impresora no conectada` | nombre no coincide o USB desconectado | Verifica el nombre en *Devices and Printers* y prueba imprimir test de Windows. |
| Ticket sale en blanco | driver mal | Reinstala el driver de Star usando *futurePRNT* y reinicia. |
| Tickets duplicados | dos workers corriendo | Solo debe correr 1. Verifica `Get-Process node` en PowerShell. |
| No imprime órdenes nuevas | Realtime caído | El catch-up cada 60 s las recoge igual. Si tampoco, mira `worker.log`. |
| `Catch-up falló: ... permission denied` | usaste anon key en vez de service_role | Cambia `SUPABASE_SERVICE_KEY` por la correcta. |

## Formato del ticket

Cada orden saca **dos tickets** (cocina + bar) que cortan entre sí. El
de COCINA sale primero, después hay una pausa de 5 s (configurable con
`PAUSE_BETWEEN_TICKETS_MS`) para dar tiempo a cortar/agarrar el ticket
antes de que salga el de BEBIDAS. Solo se imprime el ticket de un área si
esa área tiene ítems — una orden sin bebidas no saca ticket de bar.

```
============================================
                COCINA
          Sucursal Maravillas
============================================
Tipo: DELIVERY
Fecha: 16/06/2026 19:42
Cliente: Mariano
Tel: 4491234567
Direccion:
  Calle X 123, Col. Centro
--------------------------------------------
2 x Gordita de Asada
   Bistec, Chicharrón
1 x Envío FLASH
--------------------------------------------
                ID: 8f3a1b2c
[CORTE]

============================================
                BEBIDAS
          Sucursal Maravillas
============================================
Tipo: DELIVERY
Fecha: 16/06/2026 19:42
Cliente: Mariano
--------------------------------------------
1 x Refresco 600ml
   Coca-Cola
--------------------------------------------
                ID: 8f3a1b2c
[CORTE]
```

Estos son tickets de **producción** (para cocina/bar) — no llevan
precio ni total. Si quieres agregar precios, edita `appendTicket()`
en `index.js`.

Las categorías que cuentan como bebida son: `drink`, `alcohol`,
`bebidas`, `drinks`, `aguas`, `jugos`, `cafes`, `refrescos` (mismas
que usa `kitchen_view.dart`). Cualquier otra categoría va a cocina,
incluyendo el Envío FLASH (para que el cocinero sepa que es delivery).
