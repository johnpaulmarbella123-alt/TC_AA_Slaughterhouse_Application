-- Add passed_count and condemned_count columns to support partial batch
-- health issue handling when a customer requests 2 or more livestock.
ALTER TABLE public.slaughter_inspection
  ADD COLUMN IF NOT EXISTS passed_count INTEGER,
  ADD COLUMN IF NOT EXISTS condemned_count INTEGER;

ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS passed_count INTEGER,
  ADD COLUMN IF NOT EXISTS condemned_count INTEGER;
