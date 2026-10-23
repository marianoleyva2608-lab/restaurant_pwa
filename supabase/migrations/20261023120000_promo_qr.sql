-- Descuentos por QR (en el restaurante). Cada código se puede usar una vez
-- por teléfono de cliente.
CREATE TABLE IF NOT EXISTS public.promo_codes (
  code        text PRIMARY KEY,
  percent     numeric NOT NULL CHECK (percent > 0 AND percent <= 100),
  active      boolean NOT NULL DEFAULT true,
  expires_at  timestamptz,
  description text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.promo_redemptions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL REFERENCES public.promo_codes(code),
  phone       text NOT NULL,
  order_id    uuid,
  branch_name text,
  redeemed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (code, phone)
);

INSERT INTO public.promo_codes (code, percent, description)
VALUES ('PROMO20', 20, 'QR 20% una vez por teléfono')
ON CONFLICT (code) DO NOTHING;
