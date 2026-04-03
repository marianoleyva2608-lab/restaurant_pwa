-- Migration to add individual item status for the kitchen

ALTER TABLE order_items
ADD COLUMN status TEXT NOT NULL DEFAULT 'pending';

-- Add policy to allow updating order_items status
CREATE POLICY "Allow update for order_items status" ON order_items FOR UPDATE USING (true) WITH CHECK (true);
