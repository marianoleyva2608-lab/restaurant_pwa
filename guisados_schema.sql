-- Tabla de guisados disponibles
CREATE TABLE IF NOT EXISTS guisados (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  branch_name TEXT DEFAULT NULL, -- NULL = todas las sucursales
  available BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insertar guisados de ejemplo
INSERT INTO guisados (name) VALUES
  ('Picadillo'),('Rajas con queso'),('Frijoles'),('Papa con chorizo'),
  ('Chicharrón en salsa'),('Tinga de pollo'),('Mole'),('Rajas con crema')
ON CONFLICT DO NOTHING;

-- Campo en dishes para indicar si requiere guisado
ALTER TABLE dishes ADD COLUMN IF NOT EXISTS requires_guisado BOOLEAN DEFAULT false;

-- Campo en order_items para guardar los guisados seleccionados
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS guisados_selected TEXT DEFAULT NULL;
