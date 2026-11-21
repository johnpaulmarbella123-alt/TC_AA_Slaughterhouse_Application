-- ==============================================================================
-- Per-Head "Animals in Lot" Tracking Column
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-20
--
-- Adds JSONB column `animals_in_lot` to `public.requests` storing per-head
-- details (head_no, ear_tag, color, origin, sex, live_weight) while keeping
-- `animal_count` synchronized for fees, quotas, dashboards, and NMIS PDFs.
-- ==============================================================================

ALTER TABLE public.requests
    ADD COLUMN IF NOT EXISTS animals_in_lot JSONB NOT NULL DEFAULT '[]'::jsonb;

NOTIFY pgrst, 'reload schema';
