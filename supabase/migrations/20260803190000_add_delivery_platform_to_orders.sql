-- Agrega la plataforma de delivery (Uber Eats / Didi Food) a las órdenes,
-- para distinguirlas de una futura entrega propia y para que Caja pueda
-- filtrar/reportar las ventas cobradas a crédito por estas plataformas.
--
-- payment_method no tiene CHECK constraint (ya se usan valores libres como
-- 'EFECTIVO', 'cash', 'card', 'mixed'), así que el nuevo valor 'credito'
-- no requiere migración aparte — se usa directo desde la app.

ALTER TABLE orders
ADD COLUMN IF NOT EXISTS delivery_platform TEXT CHECK (delivery_platform IN ('uber', 'didi'));
