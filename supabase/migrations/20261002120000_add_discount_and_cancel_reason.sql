-- Modificaciones oct-2026:
--  * Descuentos: guardar % , monto y motivo en la orden para que salgan
--    en el ticket y en "Venta de Hoy" / corte.
--  * Cuentas canceladas: guardar motivo, quién y cuándo (la orden NO se
--    borra, sólo queda status = 'cancelled').
-- Ejecutar en: Supabase > SQL Editor. Es seguro correrlo varias veces.

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS discount_percent NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS discount_amount  NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS discount_reason  TEXT,
  ADD COLUMN IF NOT EXISTS cancel_reason    TEXT,
  ADD COLUMN IF NOT EXISTS cancelled_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_by     TEXT;
