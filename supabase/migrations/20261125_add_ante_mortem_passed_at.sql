-- Migration: Add ante_mortem_passed_at timestamp to slaughter_inspection
-- Date: 2026-11-25
-- Purpose: Persists the exact UTC timestamp when ante-mortem inspection is marked Passed,
--          driving reliable 5-minute automated slaughter stage progression
--          (Stunning -> Bleeding -> Scalding/Dehairing -> Evisceration) across browser refreshes.

ALTER TABLE IF EXISTS public.slaughter_inspection
ADD COLUMN IF NOT EXISTS ante_mortem_passed_at TIMESTAMPTZ;
