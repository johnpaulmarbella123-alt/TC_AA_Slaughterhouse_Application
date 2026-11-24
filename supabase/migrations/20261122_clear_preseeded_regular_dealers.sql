-- ==============================================================================
-- Clear Pre-Seeded Default Regular Dealers & Legacy Walk-In Claim Settings
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-22
--
-- Removes unlinked pre-seeded default dealers (where user_id IS NULL) so the
-- Meat Dealers Directory starts clean on a brand-new system and populates
-- organically from real registered/submitted customer requests.
-- ==============================================================================

DELETE FROM public.regular_dealers
WHERE user_id IS NULL;

UPDATE public.system_settings
SET value = '[]'::jsonb, updated_at = NOW()
WHERE key IN ('regular_dealers', 'walk_in_directory');

UPDATE public.system_settings
SET value = '{}'::jsonb, updated_at = NOW()
WHERE key IN ('walk_in_claims');

-- Verification check
SELECT COUNT(*) AS remaining_registered_dealers
FROM public.regular_dealers;
