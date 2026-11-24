-- Add amount_tendered and change_amount columns to public.payments
-- so Cash payments (both Cashier Process Payment and Cash-on-Pickup Verification)
-- persist the exact cash given by the customer and the auto-calculated change due.

ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS amount_tendered NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS change_amount NUMERIC(10, 2);

NOTIFY pgrst, 'reload schema';
