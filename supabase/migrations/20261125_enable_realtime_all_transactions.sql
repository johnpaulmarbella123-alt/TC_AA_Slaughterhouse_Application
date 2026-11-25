-- Migration: Enable Supabase Realtime for all core abattoir transaction tables
-- Date: 2026-11-25
-- Purpose: Ensures Admin, Clerk, and Inspector screens receive instant (<1s) Postgres
--          change events without waiting for polling or manual browser refresh.

-- Ensure full row payloads are emitted on UPDATE / DELETE for core transaction tables
ALTER TABLE IF EXISTS public.requests REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.payments REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.slaughter_inspection REPLICA IDENTITY FULL;

-- Idempotently add all transaction tables to the supabase_realtime publication
DO $$
DECLARE
  tbl TEXT;
  tables TEXT[] := ARRAY[
    'requests',
    'payments',
    'slaughter_inspection',
    'regular_dealers',
    'reports',
    'notifications',
    'staff_notifications'
  ];
BEGIN
  FOREACH tbl IN ARRAY tables LOOP
    IF EXISTS (
      SELECT 1
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = tbl
    ) AND NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = tbl
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', tbl);
    END IF;
  END LOOP;
END $$;
