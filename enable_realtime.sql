-- Habilitar el sistema de tiempo real (Realtime) para las tablas principales
-- Ejecuta este comando en la sección "SQL Editor" de tu panel de Supabase:

BEGIN;

-- Añadir las tablas a la publicación de tiempo real de Supabase
ALTER PUBLICATION supabase_realtime ADD TABLE orders;
ALTER PUBLICATION supabase_realtime ADD TABLE order_items;
ALTER PUBLICATION supabase_realtime ADD TABLE restaurant_tables;
ALTER PUBLICATION supabase_realtime ADD TABLE dishes;

COMMIT;
