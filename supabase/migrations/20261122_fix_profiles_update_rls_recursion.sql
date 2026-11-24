-- ==============================================================================
-- Fix 42P17 Infinite Recursion on public.profiles UPDATE RLS Policy
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-22
--
-- Root Cause: profiles_update policy queried `public.profiles` directly inside
-- its own WITH CHECK clause, causing Postgres error 42P17 when a customer
-- updated their profile photo or personal info.
-- Fix: Use a SECURITY DEFINER helper function `public.current_user_profile_role()`
-- to safely compare the existing role without triggering RLS recursion.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.current_user_profile_role()
RETURNS TEXT AS $$
    SELECT role FROM public.profiles WHERE id = (SELECT auth.uid()) LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.current_user_profile_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_profile_role() TO authenticated;

DROP POLICY IF EXISTS "profiles_update" ON public.profiles;

CREATE POLICY "profiles_update" ON public.profiles FOR UPDATE TO authenticated
    USING (public.is_admin() OR id = (SELECT auth.uid()))
    WITH CHECK (
        public.is_admin()
        OR (
            id = (SELECT auth.uid())
            AND (role IS NOT DISTINCT FROM public.current_user_profile_role())
        )
    );

NOTIFY pgrst, 'reload schema';
