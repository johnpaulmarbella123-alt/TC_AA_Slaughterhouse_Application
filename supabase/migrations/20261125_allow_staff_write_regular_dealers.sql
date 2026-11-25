-- Migration: Allow all abattoir staff (Admin, Clerk, Inspector, Cashier) to manage regular_dealers
-- Date: 2026-11-25
-- Purpose: Ensures Admin and Clerk accounts can register, update, and delete walk-in meat dealers
--          in public.regular_dealers without silent RLS rejections.

ALTER TABLE IF EXISTS public.regular_dealers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow admin write regular_dealers" ON public.regular_dealers;
DROP POLICY IF EXISTS "Allow staff write regular_dealers" ON public.regular_dealers;
DROP POLICY IF EXISTS "Allow authenticated insert/update regular_dealers" ON public.regular_dealers;

CREATE POLICY "Allow staff write regular_dealers"
ON public.regular_dealers FOR ALL
TO authenticated
USING (public.is_staff())
WITH CHECK (public.is_staff());
