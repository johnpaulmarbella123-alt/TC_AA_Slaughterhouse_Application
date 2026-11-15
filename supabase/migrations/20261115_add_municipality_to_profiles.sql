-- Add optional municipality column to public.profiles so Barangay dealers'
-- confirmed municipality persists alongside their barangay.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS municipality TEXT;
