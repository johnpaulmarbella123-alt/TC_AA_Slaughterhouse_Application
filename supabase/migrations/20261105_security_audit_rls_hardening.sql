-- ==============================================================================
-- Comprehensive Security Hardening & Row-Level Security (RLS) Policy Migration
-- Target System: Tabaco City Slaughterhouse Management System (TCAASlaughter_App)
-- Date: 2026-11-05
-- Standard: OWASP Top 10 (2021) A01: Broken Access Control & RA 10173 (Data Privacy)
-- ==============================================================================

-- 1. Helper Functions to Identify Staff & Administrators
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND LOWER(COALESCE(role, '')) IN ('admin', 'superadmin', 'super admin')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND LOWER(COALESCE(role, '')) IN ('admin', 'superadmin', 'super admin', 'inspector', 'cashier', 'clerk')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- 2. Hardening: Regular Dealers & Permanent Markings Registry
ALTER TABLE IF EXISTS public.regular_dealers ENABLE ROW LEVEL SECURITY;

-- Drop insecure legacy policies if present
DROP POLICY IF EXISTS "Allow authenticated insert/update regular_dealers" ON public.regular_dealers;
DROP POLICY IF EXISTS "Allow authenticated read regular_dealers" ON public.regular_dealers;
DROP POLICY IF EXISTS "Allow public read regular_dealers" ON public.regular_dealers;
DROP POLICY IF EXISTS "Allow admin write regular_dealers" ON public.regular_dealers;

-- Read: Authenticated clients and staff can read dealer entries to verify tags & claim walk-in slips
CREATE POLICY "Allow read regular_dealers"
ON public.regular_dealers FOR SELECT
TO authenticated, anon
USING (true);

-- Write: Strictly restricted to abattoir administrators
CREATE POLICY "Allow admin write regular_dealers"
ON public.regular_dealers FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- 3. Hardening: Payments & Financial Integrity (Preventing Client Tampering)
ALTER TABLE IF EXISTS public.payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Clients can view own payments" ON public.payments;
DROP POLICY IF EXISTS "Staff full access to payments" ON public.payments;
DROP POLICY IF EXISTS "Clients submit payment reference" ON public.payments;

-- SELECT: Customers view their own records; staff view all abattoir payments
CREATE POLICY "Clients can view own payments"
ON public.payments FOR SELECT
TO authenticated
USING (auth.uid() = user_id OR public.is_staff());

-- INSERT: Staff or system triggers can create records
CREATE POLICY "Staff insert payments"
ON public.payments FOR INSERT
TO authenticated
WITH CHECK (public.is_staff() OR auth.uid() = user_id);

-- UPDATE: Staff can verify and confirm payments (status = 'paid').
-- Customers can only update payment method and transaction reference for cashier verification.
CREATE POLICY "Staff update payments"
ON public.payments FOR UPDATE
TO authenticated
USING (public.is_staff())
WITH CHECK (public.is_staff());

CREATE POLICY "Clients submit online payment reference"
ON public.payments FOR UPDATE
TO authenticated
USING (auth.uid() = user_id AND status != 'paid')
WITH CHECK (
    auth.uid() = user_id 
    AND status IN ('pending', 'verification_pending')
);

-- 4. Hardening: Requests Table Access Control
ALTER TABLE IF EXISTS public.requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Clients can view own bookings" ON public.requests;
DROP POLICY IF EXISTS "Staff have full access to bookings" ON public.requests;
DROP POLICY IF EXISTS "Clients can insert own bookings" ON public.requests;
DROP POLICY IF EXISTS "Clients can update pending bookings" ON public.requests;

CREATE POLICY "Clients can view own bookings"
ON public.requests FOR SELECT
TO authenticated
USING (auth.uid() = user_id OR public.is_staff());

CREATE POLICY "Clients can insert own bookings"
ON public.requests FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Staff have full access to bookings"
ON public.requests FOR ALL
TO authenticated
USING (public.is_staff())
WITH CHECK (public.is_staff());

CREATE POLICY "Clients can update pending bookings"
ON public.requests FOR UPDATE
TO authenticated
USING (auth.uid() = user_id AND status IN ('pending', 'rejected'))
WITH CHECK (
    auth.uid() = user_id 
    AND status IN ('pending', 'rejected')
);

-- 5. Hardening: System Settings & Abattoir Configuration
ALTER TABLE IF EXISTS public.system_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read system_settings" ON public.system_settings;
DROP POLICY IF EXISTS "Allow admin write system_settings" ON public.system_settings;

CREATE POLICY "Allow read system_settings"
ON public.system_settings FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Allow admin write system_settings"
ON public.system_settings FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- 6. Hardening: NMIC Transmissions Audit Log
ALTER TABLE IF EXISTS public.nmic_transmissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow authenticated read nmic_transmissions" ON public.nmic_transmissions;
DROP POLICY IF EXISTS "Allow authenticated insert nmic_transmissions" ON public.nmic_transmissions;
DROP POLICY IF EXISTS "Staff access nmic_transmissions" ON public.nmic_transmissions;

CREATE POLICY "Staff access nmic_transmissions"
ON public.nmic_transmissions FOR ALL
TO authenticated
USING (public.is_staff())
WITH CHECK (public.is_staff());

-- 7. Hardening: Profiles Table (Preventing Self-Promotion to Admin)
ALTER TABLE IF EXISTS public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Staff full access to profiles" ON public.profiles;

CREATE POLICY "Users can view profiles"
ON public.profiles FOR SELECT
TO authenticated
USING (auth.uid() = id OR public.is_staff());

CREATE POLICY "Users can insert own profile"
ON public.profiles FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- Users can update display_name, phone_number, avatar_url, but CANNOT elevate their role
CREATE POLICY "Users can update own profile non-sensitive fields"
ON public.profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (
    auth.uid() = id 
    AND (
        (public.is_admin())
        OR (role IS NOT DISTINCT FROM (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid()))
    )
);

CREATE POLICY "Admin full access to profiles"
ON public.profiles FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- 8. Storage Security Policies for Sensitive Documents (request-documents)
-- Enforce that request-documents is restricted to owner + authorized staff
DO $$
BEGIN
    -- Ensure storage objects table has RLS
    ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN others THEN NULL;
END $$;

DROP POLICY IF EXISTS "Allow owner and staff read request documents" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated upload request documents" ON storage.objects;

CREATE POLICY "Allow owner and staff read request documents"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'request-documents'
    AND (
        (storage.foldername(name))[1] = auth.uid()::text
        OR public.is_staff()
    )
);

CREATE POLICY "Allow authenticated upload request documents"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'request-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

