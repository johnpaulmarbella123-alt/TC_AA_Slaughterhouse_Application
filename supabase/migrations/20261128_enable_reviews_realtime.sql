-- ==============================================================================
-- Enable Supabase Realtime for Customer Reviews & Likes
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-28
--
-- Adds `public.reviews` to the `supabase_realtime` publication with FULL
-- replica identity so INSERT (new reviews), UPDATE (likes / helpful counts),
-- and DELETE events broadcast immediately to the Admin Panel in real time.
-- ==============================================================================

ALTER TABLE public.reviews REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'reviews'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.reviews;
  END IF;
END $$;
