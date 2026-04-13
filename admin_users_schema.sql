CREATE TABLE IF NOT EXISTS admin_users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'admin', -- 'superadmin' o 'admin'
  branch_name TEXT DEFAULT NULL, -- NULL = todas las sucursales
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insertar usuario superadmin inicial
INSERT INTO admin_users (username, password, role, branch_name)
VALUES ('admin', '1234', 'superadmin', NULL)
ON CONFLICT (username) DO NOTHING;
