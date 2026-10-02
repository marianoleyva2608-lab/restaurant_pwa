-- Menú oct-2026: productos de cortesía en $0 + productos nuevos.
-- Ejecutar en: Supabase > SQL Editor. Seguro de correr varias veces
-- (no duplica si el producto ya existe).

-- ─── Cortesías ($0) ─────────────────────────────────────────────────
-- Categoría propia 'cortesias' → aparece como chip "Cortesías" en el menú
-- del mesero/caja y se imprime en $0.00.
INSERT INTO dishes (name, description, price, cost, category, requires_guisado, max_time)
SELECT v.name, 'Cortesía', 0, 0, 'cortesias', false, v.t
FROM (VALUES
  ('Café de Olla Cortesía', 5),
  ('Churros Cortesía', 8),
  ('Hot Cakes Cortesía', 10),
  ('Agua Cortesía', 3),
  ('Orden de Molletes Cortesía', 10)
) AS v(name, t)
WHERE NOT EXISTS (
  SELECT 1 FROM dishes d WHERE LOWER(TRIM(d.name)) = LOWER(v.name)
);

-- ─── Café de litro $100 ─────────────────────────────────────────────
INSERT INTO dishes (name, description, price, cost, category, requires_guisado, max_time)
SELECT 'Café de Litro', '', 100, 0, 'cafes', false, 5
WHERE NOT EXISTS (
  SELECT 1 FROM dishes WHERE LOWER(TRIM(name)) = 'café de litro'
);

-- ─── Rol de canela $35 (misma categoría que Churros / "Lo dulce") ───
INSERT INTO dishes (name, description, price, cost, category, requires_guisado, max_time)
SELECT 'Rol de Canela', '', 35, 0,
       COALESCE((SELECT category FROM dishes WHERE LOWER(name) LIKE 'churros%' AND category <> 'cortesias' LIMIT 1), 'lo_dulce'),
       false, 3
WHERE NOT EXISTS (
  SELECT 1 FROM dishes WHERE LOWER(TRIM(name)) = 'rol de canela'
);

-- ─── Bolillo de guisado con queso (PRECIO PENDIENTE) ────────────────
-- Quitar los "--" y poner el precio en lugar de 0 antes de ejecutar.
-- INSERT INTO dishes (name, description, price, cost, category, requires_guisado, max_time)
-- SELECT 'Bolillo de Guisado con Queso', '', 0, 0,
--        COALESCE((SELECT category FROM dishes WHERE LOWER(name) = 'bolillo con guisado' LIMIT 1), 'especialidades'),
--        true, 10
-- WHERE NOT EXISTS (
--   SELECT 1 FROM dishes WHERE LOWER(TRIM(name)) = 'bolillo de guisado con queso'
-- );
