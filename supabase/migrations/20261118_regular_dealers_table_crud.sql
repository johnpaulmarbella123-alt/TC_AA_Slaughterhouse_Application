-- ==============================================================================
-- Migration: Ensure public.regular_dealers Table & Complete CRUD Policies
-- Target System: Tabaco City Slaughterhouse Management System (TCAASlaughter_App)
-- Date: 2026-11-18
-- ==============================================================================

-- 1. Ensure public.regular_dealers table exists
CREATE TABLE IF NOT EXISTS public.regular_dealers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_number INT NOT NULL,
    name TEXT NOT NULL,
    markings TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('market', 'barangay')),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    phone TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(category, dealer_number)
);

CREATE INDEX IF NOT EXISTS idx_regular_dealers_category ON public.regular_dealers(category);
CREATE INDEX IF NOT EXISTS idx_regular_dealers_markings ON public.regular_dealers(markings);
CREATE INDEX IF NOT EXISTS idx_regular_dealers_user_id ON public.regular_dealers(user_id);

-- 2. Ensure Row-Level Security is enabled
ALTER TABLE IF EXISTS public.regular_dealers ENABLE ROW LEVEL SECURITY;

-- 3. Reset existing policies to ensure clean, non-conflicting rules
DROP POLICY IF EXISTS "Allow read regular_dealers" ON public.regular_dealers;
DROP POLICY IF EXISTS "Allow authenticated read regular_dealers" ON public.regular_dealers;
DROP POLICY IF EXISTS "Allow public read regular_dealers" ON public.regular_dealers;
DROP POLICY IF EXISTS "Allow authenticated insert/update regular_dealers" ON public.regular_dealers;
DROP POLICY IF EXISTS "Allow admin write regular_dealers" ON public.regular_dealers;
DROP POLICY IF EXISTS "Allow staff write regular_dealers" ON public.regular_dealers;

-- Read Policy: Public and authenticated users can view the meat dealers directory
CREATE POLICY "Allow read regular_dealers"
ON public.regular_dealers FOR SELECT
TO anon, authenticated
USING (true);

-- Write Policy: Staff & Administrators have full CRUD access
CREATE POLICY "Allow staff write regular_dealers"
ON public.regular_dealers FOR ALL
TO authenticated
USING (public.is_staff() OR public.is_admin())
WITH CHECK (public.is_staff() OR public.is_admin());
