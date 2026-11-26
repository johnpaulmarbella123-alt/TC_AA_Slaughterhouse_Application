-- Ensure public.requests has a contact_number column for walk-in SMS notifications
ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS contact_number TEXT;
