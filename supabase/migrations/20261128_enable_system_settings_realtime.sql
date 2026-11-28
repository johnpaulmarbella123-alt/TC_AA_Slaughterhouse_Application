-- ==============================================================================
-- Enable Supabase Realtime for System Settings (Live Fee Schedules Sync)
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-28
--
-- Adds `public.system_settings` to `supabase_realtime` with FULL replica
-- identity so whenever an Admin updates per-animal fees or adds an Additional
-- Administrative Charge, every connected customer Mobile App updates live.
-- ==============================================================================

ALTER TABLE public.system_settings REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'system_settings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.system_settings;
  END IF;
END $$;

-- Ensure authenticated customers can read live fee_schedules in real time
DROP POLICY IF EXISTS "Allow authenticated read fee_schedules" ON public.system_settings;
CREATE POLICY "Allow authenticated read fee_schedules"
  ON public.system_settings
  FOR SELECT
  TO authenticated
  USING (key = 'fee_schedules');
