-- ============================================================
-- MENÚ COMPLETO - Gorditas Mis Hermanas
-- Ejecutar en Supabase > SQL Editor
-- ============================================================

-- 1. Borrar solo platillos que NO estén en órdenes históricas
--    (los que sí están en order_items se conservan para no romper el historial)
DELETE FROM dishes
WHERE id NOT IN (
  SELECT DISTINCT dish_id FROM order_items WHERE dish_id IS NOT NULL
);

-- ============================================================
-- 2. INSERTAR NUEVO MENÚ
-- ============================================================

INSERT INTO dishes (name, description, price, cost, category, requires_guisado, max_time) VALUES

-- ─────────────────────────────────────────────
-- HUARACHES (Con frijoles, lechuga, queso, crema y salsa)
-- ─────────────────────────────────────────────
('Huarache Sencillo',
 'Con frijoles, lechuga, queso, crema y salsa',
 95, 0, 'especialidades', false, 15),

('Huarache con Arrachera',
 'Con frijoles, lechuga, queso, crema y salsa',
 140, 0, 'especialidades', false, 15),

('Huarache con Guisado',
 'Con frijoles, lechuga, queso, crema y salsa. El mesero elegirá el guisado',
 130, 0, 'especialidades', true, 15),

('Huarache con Chorizo',
 'Con frijoles, lechuga, queso, crema y salsa',
 130, 0, 'especialidades', false, 15),

-- ─────────────────────────────────────────────
-- CHILAQUILES (Con frijoles, queso, cebolla y crema · incluye bolillo)
-- ─────────────────────────────────────────────
('Chilaquiles Rojos / Verdes / Rancheros',
 'Con frijoles, queso, cebolla y crema. Incluye bolillo. Salsa molcajeteada',
 95, 0, 'breakfast', false, 12),

('Chilaquiles con Huevo',
 'Con 1 huevo estrellado o revuelto montado en tortilla frita. Salsa roja, verde o ranchera',
 120, 0, 'breakfast', false, 12),

-- ─────────────────────────────────────────────
-- HUEVOS (Con frijoles y queso · incluye bolillo rebanado o tortilla)
-- ─────────────────────────────────────────────
('Huevos Rancheros',
 '2 huevos estrellados montados en tortilla frita bañados con salsa molcajeteada',
 90, 0, 'breakfast', false, 12),

('Huevos Divorciados',
 '2 huevos estrellados montados en tortilla frita bañados con salsa verde, roja o molcajeteada',
 90, 0, 'breakfast', false, 12),

('Huevos Poblanos',
 '2 huevos estrellados montados en tortilla frita bañados con mole poblano',
 110, 0, 'breakfast', false, 12),

('Huevos Revueltos con Jamón o Tocino',
 '2 huevos revueltos con jamón o tocino. Con frijoles y queso',
 90, 0, 'breakfast', false, 10),

('Huevos Naturales',
 '2 huevos revueltos o estrellados. Con frijoles y queso',
 90, 0, 'breakfast', false, 10),

('Huevos a la Mexicana',
 '2 huevos revueltos con cebolla, jitomate y chile serrano picados. Con frijoles y queso',
 90, 0, 'breakfast', false, 10),

-- ─────────────────────────────────────────────
-- MOLLETES (2 pzas.)
-- ─────────────────────────────────────────────
('Molletes Naturales',
 '2 piezas con frijoles y queso',
 85, 0, 'breakfast', false, 10),

('Molletes con Arrachera',
 '2 piezas con arrachera',
 125, 0, 'breakfast', false, 12),

('Molletes con Guisado',
 '2 piezas. El mesero elegirá el guisado',
 120, 0, 'breakfast', true, 12),

('Molletes de Chilaquiles',
 'Chilaquiles verdes o rojos en cama de frijol con crema, cebolla y queso',
 130, 0, 'breakfast', false, 12),

-- ─────────────────────────────────────────────
-- ENCHILADAS (4 pzas.)
-- ─────────────────────────────────────────────
('Enchiladas de Cebolla',
 '4 piezas',
 95, 0, 'mainCourse', false, 15),

('Enchiladas de Queso',
 '4 piezas',
 110, 0, 'mainCourse', false, 15),

('Enchiladas de Pollo',
 '4 piezas',
 120, 0, 'mainCourse', false, 15),

-- ─────────────────────────────────────────────
-- ENMOLADAS (4 pzas.)
-- ─────────────────────────────────────────────
('Enmoladas de Cebolla',
 '4 piezas con mole',
 110, 0, 'mainCourse', false, 15),

('Enmoladas de Queso',
 '4 piezas con mole',
 120, 0, 'mainCourse', false, 15),

('Enmoladas de Pollo',
 '4 piezas con mole',
 130, 0, 'mainCourse', false, 15),

-- ─────────────────────────────────────────────
-- SOPES (2 pzas.)
-- ─────────────────────────────────────────────
('Sopes Sencillos',
 '2 piezas',
 100, 0, 'mainCourse', false, 15),

('Sopes con Arrachera',
 '2 piezas con arrachera',
 130, 0, 'mainCourse', false, 15),

('Sopes con Guisado',
 '2 piezas. El mesero elegirá el guisado',
 120, 0, 'mainCourse', true, 15),

-- ─────────────────────────────────────────────
-- TAPAS DE GUISADO (¡Para probar de todo!)
-- 5 rebanadas de pan · requiere selección de guisado
-- ─────────────────────────────────────────────
('Tapas de Guisado',
 '5 rebanadas de pan con el guisado de tu preferencia',
 100, 0, 'especialidades', true, 10),

('Tapas de Guisado con Queso',
 '5 rebanadas de pan con guisado de tu preferencia y queso',
 125, 0, 'especialidades', true, 10),

-- ─────────────────────────────────────────────
-- MENUDO (Sábados y Domingos)
-- ─────────────────────────────────────────────
('Menudo Chico',
 'Con o sin carne. Solo sábados y domingos',
 90, 0, 'soup', false, 10),

('Menudo Mediano',
 'Con o sin carne. Solo sábados y domingos',
 100, 0, 'soup', false, 10),

('Menudo Grande',
 'Con o sin carne. Solo sábados y domingos',
 110, 0, 'soup', false, 10),

('Cuajadilla Chica',
 'Tortilla tortillería',
 30, 0, 'side', false, 8),

('Cuajadilla Grande',
 'Tortilla hecha a mano',
 70, 0, 'side', false, 8),

-- ─────────────────────────────────────────────
-- LO DULCE / POSTRES
-- ─────────────────────────────────────────────
('Molletes Dulces',
 'Con mantequilla y mermelada. 2 piezas',
 80, 0, 'dessert', false, 8),

('Hot Cakes Naturales (3 pzas.)',
 '3 hot cakes naturales',
 90, 0, 'dessert', false, 10),

('Hot Cakes Naturales (2 pzas.)',
 '2 hot cakes naturales',
 70, 0, 'dessert', false, 10),

('Hot Cakes Naturales (1 pza.)',
 '1 hot cake natural',
 40, 0, 'dessert', false, 8),

('Churros',
 '',
 12, 0, 'dessert', false, 8),

-- ─────────────────────────────────────────────
-- ÓRDENES EXTRAS / COMPLEMENTOS
-- ─────────────────────────────────────────────
('Tocino o Jamón (3 pzas.)',
 'Orden extra',
 30, 0, 'side', false, 5),

('Guisado Extra',
 'Orden extra de guisado',
 40, 0, 'side', false, 5),

('Arrachera Extra',
 'Orden extra de arrachera',
 40, 0, 'side', false, 5),

('Huevo Estrellado o Revuelto',
 'Orden extra',
 20, 0, 'side', false, 5),

('Pieza de Bolillo',
 '',
 16, 0, 'side', false, 3),

-- ─────────────────────────────────────────────
-- PARA LLEVAR
-- ─────────────────────────────────────────────
('½ Litro Guisado con Carne',
 'Para llevar',
 120, 0, 'side', false, 10),

('½ Litro Guisado sin Carne',
 'Para llevar',
 80, 0, 'side', false, 10),

('½ Litro Arroz o Frijoles',
 'Para llevar',
 40, 0, 'side', false, 5),

('¼ Litro Salsa',
 'Para llevar',
 40, 0, 'side', false, 5),

('Chile Relleno con Salsa',
 'Para llevar',
 50, 0, 'side', false, 10),

-- ─────────────────────────────────────────────
-- BEBIDAS
-- (Verifica los precios en el menú físico)
-- ─────────────────────────────────────────────
('Café de Olla con Refill',
 '',
 45, 0, 'drink', false, 5),

('Café Instantáneo',
 '',
 45, 0, 'drink', false, 5),

('Jugo Verde (330 ml)',
 'Jugo verde natural',
 40, 0, 'drink', false, 5),

('Jugo Verde (1 litro)',
 'Jugo verde natural',
 110, 0, 'drink', false, 5),

('Jugo de Naranja Natural (330 ml)',
 '',
 38, 0, 'drink', false, 5),

('Jugo de Naranja Natural (1 litro)',
 '',
 95, 0, 'drink', false, 5),

('Jugo de Zanahoria Natural (330 ml)',
 '',
 35, 0, 'drink', false, 5),

('Jugo de Zanahoria Natural (1 litro)',
 '',
 60, 0, 'drink', false, 5),

('Agua Fresca (600 ml)',
 '',
 25, 0, 'drink', false, 3),

('Agua Fresca (1 litro)',
 '',
 35, 0, 'drink', false, 3),

('Agua Fresca (2 litros)',
 '',
 60, 0, 'drink', false, 3),

('Agua Natural (500 ml)',
 '',
 30, 0, 'drink', false, 3),

('Refresco (355 ml vidrio)',
 '',
 44, 0, 'drink', false, 3),

('Refresco (600 ml no retornable)',
 '',
 35, 0, 'drink', false, 3),

('Vaso de Leche (330 ml)',
 '',
 40, 0, 'drink', false, 3),

('Choco (600 ml)',
 '',
 35, 0, 'drink', false, 3),

('Té',
 '',
 30, 0, 'drink', false, 3);

-- ============================================================
-- Resultado esperado: ~58 platillos insertados
-- Platillos con requires_guisado = true:
--   · Huarache con Guisado
--   · Molletes con Guisado
--   · Sopes con Guisado
--   · Tapas de Guisado
--   · Tapas de Guisado con Queso
-- ============================================================
