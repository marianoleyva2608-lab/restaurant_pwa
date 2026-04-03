-- Add coordinates and order type features
ALTER TABLE restaurant_tables
ADD COLUMN IF NOT EXISTS pos_x DOUBLE PRECISION DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS pos_y DOUBLE PRECISION DEFAULT 0.0;

-- Ensure orders have a type and optional customer info for takeout/delivery
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS order_type TEXT DEFAULT 'dine_in' CHECK (order_type IN ('dine_in', 'takeout', 'delivery')),
ADD COLUMN IF NOT EXISTS customer_name TEXT;

-- Drop foreign key constraint on table_id if it prevents takeout orders without a table
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_table_id_fkey;

-- Re-add constraint to allow NULL table_id for takeout/delivery
-- Assumes restaurant_tables has id as primary key
ALTER TABLE orders 
  ADD CONSTRAINT orders_table_id_fkey 
  FOREIGN KEY (table_id) 
  REFERENCES restaurant_tables(id)
  ON DELETE SET NULL;
