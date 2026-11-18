-- ==============================================================================
-- Fix Supabase Security & Performance Advisor Warnings
-- Target System: Tabaco City Slaughterhouse Management System (TCAASlaughter_App)
-- Date: 2026-11-18
--
-- Fixes:
-- 1. Security Advisor (CRITICAL):
--    - "Policy Exists RLS Disabled" & "RLS Disabled in Public" on public.system_settings
--    Re-enables RLS on public.system_settings while preserving:
--      * Anon read access for public config keys (login/signup/fees)
--      * Authenticated read access for all settings
--      * Staff (admin, inspector, cashier, clerk) full write access
--      * Authenticated customer write access ONLY for customer-sync keys
--        ('ante_mortem_alerts', 'authorized_representatives', 'regular_dealers',
--         'walk_in_directory', 'walk_in_claims')
-- 2. Performance Advisor (WARN):
--    - "Auth RLS Initialization Plan" on public.profiles, public.requests,
--      and public.notifications by wrapping auth.uid() in (select auth.uid())
-- ==============================================================================

-- 0. Ensure helper functions exist safely (in case 20261105 migration was not run)
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = (select auth.uid())
          AND LOWER(COALESCE(role, '')) = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = (select auth.uid())
          AND LOWER(COALESCE(role, '')) IN ('admin', 'inspector', 'cashier', 'clerk')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public;

-- 1. Re-enable RLS on public.system_settings safely
ALTER TABLE IF EXISTS public.system_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read system_settings" ON public.system_settings;
DROP POLICY IF EXISTS "Allow anon read public system_settings" ON public.system_settings;
DROP POLICY IF EXISTS "Allow admin write system_settings" ON public.system_settings;
DROP POLICY IF EXISTS "Allow staff write system_settings" ON public.system_settings;
DROP POLICY IF EXISTS "Allow customer sync keys write system_settings" ON public.system_settings;
DROP POLICY IF EXISTS "Allow customer sync keys update system_settings" ON public.system_settings;

-- Authenticated users (customers + staff) can read system_settings
CREATE POLICY "Allow read system_settings"
ON public.system_settings FOR SELECT
TO authenticated
USING (true);

-- Unauthenticated (anon) users can only read non-sensitive public config keys
CREATE POLICY "Allow anon read public system_settings"
ON public.system_settings FOR SELECT
TO anon
USING (
    key IN (
        'staff_accounts',
        'appearance',
        'schedule_capacity',
        'fee_schedules',
        'slaughter_fees',
        'admin_account_provisioned'
    )
);

-- Staff (admin, inspector, cashier, clerk) have full write access to system_settings
CREATE POLICY "Allow staff write system_settings"
ON public.system_settings FOR ALL
TO authenticated
USING (public.is_staff())
WITH CHECK (public.is_staff());

-- Authenticated mobile customers can insert/update only their customer-sync keys
CREATE POLICY "Allow customer sync keys write system_settings"
ON public.system_settings FOR INSERT
TO authenticated
WITH CHECK (
    key IN (
        'ante_mortem_alerts',
        'authorized_representatives',
        'regular_dealers',
        'walk_in_directory',
        'walk_in_claims'
    )
);

CREATE POLICY "Allow customer sync keys update system_settings"
ON public.system_settings FOR UPDATE
TO authenticated
USING (
    key IN (
        'ante_mortem_alerts',
        'authorized_representatives',
        'regular_dealers',
        'walk_in_directory',
        'walk_in_claims'
    )
)
WITH CHECK (
    key IN (
        'ante_mortem_alerts',
        'authorized_representatives',
        'regular_dealers',
        'walk_in_directory',
        'walk_in_claims'
    )
);

-- 2. Optimize RLS policies on public.profiles (wrap auth.uid() in (select auth.uid()))
DROP POLICY IF EXISTS "Users can view profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile non-sensitive fields" ON public.profiles;

CREATE POLICY "Users can view profiles"
ON public.profiles FOR SELECT
TO authenticated
USING ((select auth.uid()) = id OR public.is_staff());

CREATE POLICY "Users can insert own profile"
ON public.profiles FOR INSERT
TO authenticated
WITH CHECK ((select auth.uid()) = id);

CREATE POLICY "Users can update own profile non-sensitive fields"
ON public.profiles FOR UPDATE
TO authenticated
USING ((select auth.uid()) = id)
WITH CHECK (
    (select auth.uid()) = id
    AND (
        public.is_admin()
        OR (role IS NOT DISTINCT FROM (SELECT p.role FROM public.profiles p WHERE p.id = (select auth.uid())))
    )
);

-- 3. Optimize RLS policies on public.requests (wrap auth.uid() in (select auth.uid()))
DROP POLICY IF EXISTS "Clients can view own bookings" ON public.requests;
DROP POLICY IF EXISTS "Clients can insert own bookings" ON public.requests;
DROP POLICY IF EXISTS "Clients can update pending bookings" ON public.requests;

CREATE POLICY "Clients can view own bookings"
ON public.requests FOR SELECT
TO authenticated
USING ((select auth.uid()) = user_id OR public.is_staff());

CREATE POLICY "Clients can insert own bookings"
ON public.requests FOR INSERT
TO authenticated
WITH CHECK ((select auth.uid()) = user_id);

CREATE POLICY "Clients can update pending bookings"
ON public.requests FOR UPDATE
TO authenticated
USING ((select auth.uid()) = user_id AND status IN ('pending', 'rejected'))
WITH CHECK (
    (select auth.uid()) = user_id
    AND status IN ('pending', 'rejected')
);

-- 4. Safely optimize any remaining policies on profiles, requests, and notifications
--    that call auth.uid() directly without a SELECT wrapper (preserving all existing rules).
DO $$
DECLARE
    pol RECORD;
    new_qual TEXT;
    new_check TEXT;
    roles_sql TEXT;
    ddl TEXT;
BEGIN
    FOR pol IN
        SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('profiles', 'requests', 'notifications')
          AND (
              (qual IS NOT NULL AND qual LIKE '%auth.uid()%' AND qual NOT ILIKE '%select auth.uid()%')
              OR (with_check IS NOT NULL AND with_check LIKE '%auth.uid()%' AND with_check NOT ILIKE '%select auth.uid()%')
          )
    LOOP
        new_qual := CASE
            WHEN pol.qual IS NOT NULL THEN replace(pol.qual, 'auth.uid()', '(select auth.uid())')
            ELSE NULL
        END;
        new_check := CASE
            WHEN pol.with_check IS NOT NULL THEN replace(pol.with_check, 'auth.uid()', '(select auth.uid())')
            ELSE NULL
        END;

        SELECT string_agg(quote_ident(r), ', ')
        INTO roles_sql
        FROM unnest(pol.roles) AS r;

        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', pol.policyname, pol.schemaname, pol.tablename);

        ddl := format(
            'CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s',
            pol.policyname,
            pol.schemaname,
            pol.tablename,
            pol.permissive,
            pol.cmd,
            COALESCE(roles_sql, 'PUBLIC')
        );

        IF new_qual IS NOT NULL THEN
            ddl := ddl || format(' USING (%s)', new_qual);
        END IF;

        IF new_check IS NOT NULL THEN
            ddl := ddl || format(' WITH CHECK (%s)', new_check);
        END IF;

        EXECUTE ddl;
    END LOOP;
END $$;
