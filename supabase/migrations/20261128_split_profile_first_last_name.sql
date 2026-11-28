-- ==============================================================================
-- Normalize public.profiles Name into Atomic first_name & last_name Columns
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-28
--
-- 1. Adds `first_name` and `last_name` columns to `public.profiles`.
-- 2. Backfills all existing rows from `display_name` (multi-word first names
--    keep all leading tokens in `first_name` and the final token in `last_name`,
--    e.g., 'Melch John Paul Marbella' -> 'Melch John Paul' | 'Marbella').
-- 3. Adds case-insensitive B-tree indexes on `first_name` and `last_name` for
--    fast searching by either first name or last name.
-- 4. Installs a BEFORE INSERT/UPDATE trigger that keeps `first_name`,
--    `last_name`, and `display_name` automatically synchronized with zero
--    breaking changes to existing Mobile App or Admin Panel queries.
-- ==============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS first_name TEXT,
  ADD COLUMN IF NOT EXISTS last_name TEXT;

-- Backfill existing profiles from display_name
UPDATE public.profiles
SET
  first_name = CASE
    WHEN TRIM(COALESCE(display_name, '')) = '' THEN ''
    WHEN POSITION(' ' IN TRIM(display_name)) = 0 THEN TRIM(display_name)
    ELSE TRIM(REGEXP_REPLACE(TRIM(display_name), '\s+\S+$', ''))
  END,
  last_name = CASE
    WHEN TRIM(COALESCE(display_name, '')) = '' THEN ''
    WHEN POSITION(' ' IN TRIM(display_name)) = 0 THEN ''
    ELSE TRIM(SUBSTRING(TRIM(display_name) FROM '\S+$'))
  END
WHERE first_name IS NULL OR last_name IS NULL;

-- Indexes for fast Admin/SQL search by first name or last name
CREATE INDEX IF NOT EXISTS idx_profiles_first_name_lower
  ON public.profiles (LOWER(first_name));

CREATE INDEX IF NOT EXISTS idx_profiles_last_name_lower
  ON public.profiles (LOWER(last_name));

-- Trigger to keep display_name <-> (first_name, last_name) always in sync
CREATE OR REPLACE FUNCTION public.sync_profile_name_parts()
RETURNS TRIGGER AS $$
DECLARE
  v_full TEXT;
  v_first TEXT;
  v_last TEXT;
BEGIN
  v_first := TRIM(COALESCE(NEW.first_name, ''));
  v_last  := TRIM(COALESCE(NEW.last_name, ''));
  v_full  := TRIM(COALESCE(NEW.display_name, ''));

  -- Case 1: Caller explicitly provided/updated first_name or last_name
  IF (TG_OP = 'INSERT' AND (v_first <> '' OR v_last <> ''))
     OR (TG_OP = 'UPDATE' AND (
          NEW.first_name IS DISTINCT FROM OLD.first_name OR
          NEW.last_name  IS DISTINCT FROM OLD.last_name
        ) AND NEW.display_name IS NOT DISTINCT FROM OLD.display_name) THEN
    NEW.first_name := v_first;
    NEW.last_name := v_last;
    NEW.display_name := TRIM(CONCAT_WS(' ', NULLIF(v_first, ''), NULLIF(v_last, '')));
  -- Case 2: Caller provided/updated display_name (current Mobile/Admin flow)
  ELSIF v_full <> '' THEN
    IF POSITION(' ' IN v_full) = 0 THEN
      NEW.first_name := v_full;
      NEW.last_name := '';
    ELSE
      NEW.first_name := TRIM(REGEXP_REPLACE(v_full, '\s+\S+$', ''));
      NEW.last_name := TRIM(SUBSTRING(v_full FROM '\S+$'));
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_profile_name_parts ON public.profiles;
CREATE TRIGGER trg_sync_profile_name_parts
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_profile_name_parts();

NOTIFY pgrst, 'reload schema';
