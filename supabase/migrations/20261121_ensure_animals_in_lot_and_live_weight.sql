-- ==============================================================================
-- Ensure animals_in_lot (JSONB) and live_weight (NUMERIC) exist on public.requests
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-21
-- ==============================================================================

ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS animals_in_lot JSONB DEFAULT '[]'::jsonb;

ALTER TABLE public.requests
  ADD COLUMN IF NOT EXISTS live_weight NUMERIC(10, 2);

NOTIFY pgrst, 'reload schema';

-- Verification check
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'requests'
  AND column_name IN ('animals_in_lot', 'live_weight')
ORDER BY column_name;
