-- ==============================================================================
-- Dynamic Admin Registration & Staff Provisioning Bootstrap Migration
-- Target System: Tabaco City Slaughterhouse Management System (TCAASlaughter_App)
-- Date: 2026-11-08
-- ==============================================================================

-- 1. Helper function to check if any registered Administrator exists
CREATE OR REPLACE FUNCTION public.has_registered_admin()
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE LOWER(COALESCE(role, '')) = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execution to anon and authenticated so /signup can check without signing in
GRANT EXECUTE ON FUNCTION public.has_registered_admin() TO anon, authenticated;

-- 2. Allow anon read access to public system configuration keys
DO $$
BEGIN
    DROP POLICY IF EXISTS "Allow anon read public system_settings" ON public.system_settings;
    CREATE POLICY "Allow anon read public system_settings"
    ON public.system_settings FOR SELECT
    TO anon
    USING (key IN ('staff_accounts', 'appearance', 'schedule_capacity', 'fee_schedules', 'admin_account_provisioned'));
EXCEPTION WHEN others THEN NULL;
END $$;

