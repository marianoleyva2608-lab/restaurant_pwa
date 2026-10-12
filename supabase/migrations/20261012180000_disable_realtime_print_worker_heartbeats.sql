-- Los LEDs de impresoras ahora consultan la tabla cada 30s en vez de usar
-- Realtime. Quitarla de la publicación evita que cada latido de cada
-- Raspberry se reparta como mensaje Realtime a todas las tablets.
ALTER PUBLICATION supabase_realtime DROP TABLE print_worker_heartbeats;
