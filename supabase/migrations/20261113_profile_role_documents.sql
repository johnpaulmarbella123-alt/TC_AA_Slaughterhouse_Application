-- ==============================================================================
-- Profile Role Location & Verified Role Document Columns
-- Date: 2026-11-13
-- Stores chosen barangay / market_name / stall_number / role_document_url
-- directly on public.profiles upon permanent dealer role selection.
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS barangay TEXT;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS market_name TEXT;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS stall_number TEXT;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS role_document_url TEXT;

