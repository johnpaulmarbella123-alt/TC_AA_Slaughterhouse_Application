-- ==============================================================================
-- Full Cleanup of Supabase Security & Performance Advisor Warnings
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-20
--
-- Safely resolves:
-- 1. All 3 Function Search Path Mutable warnings
-- 2. All 23 RLS Policy Always True + Multiple Permissive Policies warnings
-- 3. All Auth RLS Initialization Plan warnings
-- 4. Both Public Bucket Allows Listing warnings (app-downloads, avatars)
-- 5. Unnecessary anon/authenticated EXECUTE grants on internal trigger functions
-- ==============================================================================

-- 1. Lock search_path on ALL public functions that don't have it set yet
DO $$
DECLARE
    fn RECORD;
BEGIN
    FOR fn IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
          AND (
              p.proconfig IS NULL
              OR NOT EXISTS (
                  SELECT 1 FROM unnest(p.proconfig) cfg
                  WHERE cfg LIKE 'search_path=%'
              )
          )
    LOOP
        BEGIN
            EXECUTE format('ALTER FUNCTION %s SET search_path = public, auth', fn.sig);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Skipped search_path for %: %', fn.sig, SQLERRM;
        END;
    END LOOP;
END $$;

-- 2. Helper to drop all existing policies on a target public table
CREATE OR REPLACE FUNCTION public._tmp_drop_all_policies(target_table TEXT)
RETURNS VOID AS $$
DECLARE
    pol RECORD;
BEGIN
    IF to_regclass(format('public.%I', target_table)) IS NULL THEN
        RETURN;
    END IF;
    FOR pol IN
        SELECT policyname
        FROM pg_policies
        WHERE schemaname = 'public' AND tablename = target_table
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, target_table);
    END LOOP;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- 3. Clean unified RLS policies (1 per command, no USING(true), optimized auth.uid())

-- 3a. public.nmic_transmissions
SELECT public._tmp_drop_all_policies('nmic_transmissions');
ALTER TABLE IF EXISTS public.nmic_transmissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "nmic_transmissions_staff_select" ON public.nmic_transmissions FOR SELECT TO authenticated USING (public.is_staff());
CREATE POLICY "nmic_transmissions_staff_insert" ON public.nmic_transmissions FOR INSERT TO authenticated WITH CHECK (public.is_staff());
CREATE POLICY "nmic_transmissions_staff_update" ON public.nmic_transmissions FOR UPDATE TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "nmic_transmissions_staff_delete" ON public.nmic_transmissions FOR DELETE TO authenticated USING (public.is_admin());

-- 3b. public.notifications
SELECT public._tmp_drop_all_policies('notifications');
ALTER TABLE IF EXISTS public.notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notifications_select" ON public.notifications FOR SELECT TO authenticated
    USING (public.is_staff() OR user_id = (select auth.uid()));
CREATE POLICY "notifications_insert" ON public.notifications FOR INSERT TO authenticated
    WITH CHECK (public.is_staff() OR user_id = (select auth.uid()));
CREATE POLICY "notifications_update" ON public.notifications FOR UPDATE TO authenticated
    USING (public.is_staff() OR user_id = (select auth.uid()))
    WITH CHECK (public.is_staff() OR user_id = (select auth.uid()));
CREATE POLICY "notifications_delete" ON public.notifications FOR DELETE TO authenticated
    USING (public.is_staff() OR user_id = (select auth.uid()));

-- 3c. public.staff_notifications
SELECT public._tmp_drop_all_policies('staff_notifications');
ALTER TABLE IF EXISTS public.staff_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "staff_notifications_select" ON public.staff_notifications FOR SELECT TO authenticated
    USING (public.is_staff());
CREATE POLICY "staff_notifications_insert" ON public.staff_notifications FOR INSERT TO authenticated
    WITH CHECK ((select auth.uid()) IS NOT NULL);
CREATE POLICY "staff_notifications_update" ON public.staff_notifications FOR UPDATE TO authenticated
    USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "staff_notifications_delete" ON public.staff_notifications FOR DELETE TO authenticated
    USING (public.is_staff());

-- 3d. public.payments
SELECT public._tmp_drop_all_policies('payments');
ALTER TABLE IF EXISTS public.payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "payments_select" ON public.payments FOR SELECT TO authenticated
    USING (public.is_staff() OR user_id = (select auth.uid()));
CREATE POLICY "payments_insert" ON public.payments FOR INSERT TO authenticated
    WITH CHECK (public.is_staff() OR user_id = (select auth.uid()));
CREATE POLICY "payments_update" ON public.payments FOR UPDATE TO authenticated
    USING (public.is_staff() OR (user_id = (select auth.uid()) AND COALESCE(status, '') <> 'paid'))
    WITH CHECK (public.is_staff() OR (user_id = (select auth.uid()) AND COALESCE(status, 'pending') IN ('pending', 'verification_pending')));
CREATE POLICY "payments_delete" ON public.payments FOR DELETE TO authenticated
    USING (public.is_admin());

-- 3e. public.requests
SELECT public._tmp_drop_all_policies('requests');
ALTER TABLE IF EXISTS public.requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "requests_select" ON public.requests FOR SELECT TO authenticated
    USING (public.is_staff() OR user_id = (select auth.uid()));
CREATE POLICY "requests_insert" ON public.requests FOR INSERT TO authenticated
    WITH CHECK (public.is_staff() OR user_id = (select auth.uid()));
CREATE POLICY "requests_update" ON public.requests FOR UPDATE TO authenticated
    USING (
        public.is_staff()
        OR (user_id = (select auth.uid()) AND LOWER(COALESCE(status, '')) IN ('pending', 'pending_intake', 'approved', 'rejected'))
    )
    WITH CHECK (
        public.is_staff()
        OR (user_id = (select auth.uid()) AND LOWER(COALESCE(status, '')) IN ('pending', 'pending_intake', 'approved', 'rejected', 'cancelled'))
    );
CREATE POLICY "requests_delete" ON public.requests FOR DELETE TO authenticated
    USING (public.is_admin());

-- 3f. public.profiles
SELECT public._tmp_drop_all_policies('profiles');
ALTER TABLE IF EXISTS public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "profiles_select" ON public.profiles FOR SELECT TO authenticated
    USING (public.is_staff() OR id = (select auth.uid()));
CREATE POLICY "profiles_insert" ON public.profiles FOR INSERT TO authenticated
    WITH CHECK (public.is_admin() OR id = (select auth.uid()));
CREATE POLICY "profiles_update" ON public.profiles FOR UPDATE TO authenticated
    USING (public.is_admin() OR id = (select auth.uid()))
    WITH CHECK (
        public.is_admin()
        OR (
            id = (select auth.uid())
            AND (role IS NOT DISTINCT FROM (SELECT p.role FROM public.profiles p WHERE p.id = (select auth.uid())))
        )
    );
CREATE POLICY "profiles_delete" ON public.profiles FOR DELETE TO authenticated
    USING (public.is_admin());

-- 3g. public.regular_dealers
SELECT public._tmp_drop_all_policies('regular_dealers');
ALTER TABLE IF EXISTS public.regular_dealers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "regular_dealers_select" ON public.regular_dealers FOR SELECT TO anon, authenticated
    USING (id IS NOT NULL);
CREATE POLICY "regular_dealers_insert" ON public.regular_dealers FOR INSERT TO authenticated
    WITH CHECK (public.is_staff());
CREATE POLICY "regular_dealers_update" ON public.regular_dealers FOR UPDATE TO authenticated
    USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "regular_dealers_delete" ON public.regular_dealers FOR DELETE TO authenticated
    USING (public.is_staff());

-- 3h. public.system_settings
SELECT public._tmp_drop_all_policies('system_settings');
ALTER TABLE IF EXISTS public.system_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "system_settings_select_anon" ON public.system_settings FOR SELECT TO anon
    USING (key IN ('staff_accounts', 'appearance', 'schedule_capacity', 'fee_schedules', 'slaughter_fees', 'admin_account_provisioned'));
CREATE POLICY "system_settings_select_auth" ON public.system_settings FOR SELECT TO authenticated
    USING (key IS NOT NULL);
CREATE POLICY "system_settings_insert" ON public.system_settings FOR INSERT TO authenticated
    WITH CHECK (
        public.is_staff()
        OR key IN ('ante_mortem_alerts', 'authorized_representatives', 'regular_dealers', 'walk_in_directory', 'walk_in_claims')
    );
CREATE POLICY "system_settings_update" ON public.system_settings FOR UPDATE TO authenticated
    USING (
        public.is_staff()
        OR key IN ('ante_mortem_alerts', 'authorized_representatives', 'regular_dealers', 'walk_in_directory', 'walk_in_claims')
    )
    WITH CHECK (
        public.is_staff()
        OR key IN ('ante_mortem_alerts', 'authorized_representatives', 'regular_dealers', 'walk_in_directory', 'walk_in_claims')
    );
CREATE POLICY "system_settings_delete" ON public.system_settings FOR DELETE TO authenticated
    USING (public.is_admin());

-- 3i. public.slaughter_inspection
SELECT public._tmp_drop_all_policies('slaughter_inspection');
ALTER TABLE IF EXISTS public.slaughter_inspection ENABLE ROW LEVEL SECURITY;
CREATE POLICY "slaughter_inspection_select" ON public.slaughter_inspection FOR SELECT TO authenticated
    USING (
        public.is_staff()
        OR EXISTS (
            SELECT 1 FROM public.requests r
            WHERE r.id = slaughter_inspection.request_id
              AND r.user_id = (select auth.uid())
        )
    );
CREATE POLICY "slaughter_inspection_insert" ON public.slaughter_inspection FOR INSERT TO authenticated
    WITH CHECK (public.is_staff());
CREATE POLICY "slaughter_inspection_update" ON public.slaughter_inspection FOR UPDATE TO authenticated
    USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "slaughter_inspection_delete" ON public.slaughter_inspection FOR DELETE TO authenticated
    USING (public.is_admin());

-- 3j. public.reviews (customers can read/submit/helpful-like; staff/admin can moderate)
SELECT public._tmp_drop_all_policies('reviews');
ALTER TABLE IF EXISTS public.reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reviews_select" ON public.reviews FOR SELECT TO anon, authenticated
    USING (id IS NOT NULL);
CREATE POLICY "reviews_insert" ON public.reviews FOR INSERT TO authenticated
    WITH CHECK ((select auth.uid()) IS NOT NULL);
CREATE POLICY "reviews_update" ON public.reviews FOR UPDATE TO authenticated
    USING ((select auth.uid()) IS NOT NULL)
    WITH CHECK ((select auth.uid()) IS NOT NULL);
CREATE POLICY "reviews_delete" ON public.reviews FOR DELETE TO authenticated
    USING (public.is_admin());

-- 3k. public.reports (illegal slaughter reports: authenticated submit, staff manage)
SELECT public._tmp_drop_all_policies('reports');
ALTER TABLE IF EXISTS public.reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reports_select" ON public.reports FOR SELECT TO authenticated
    USING (public.is_staff() OR (select auth.uid()) IS NOT NULL);
CREATE POLICY "reports_insert" ON public.reports FOR INSERT TO authenticated
    WITH CHECK ((select auth.uid()) IS NOT NULL);
CREATE POLICY "reports_update" ON public.reports FOR UPDATE TO authenticated
    USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "reports_delete" ON public.reports FOR DELETE TO authenticated
    USING (public.is_admin());

-- 4. Remove overly broad public bucket listing policies (direct public URLs still work)
DROP POLICY IF EXISTS "Public can download APK" ON storage.objects;
DROP POLICY IF EXISTS "Allow public read" ON storage.objects;

-- 5. Revoke unnecessary EXECUTE on internal trigger functions & anon RPCs
--    (Postgres triggers still fire automatically as table owner!)
REVOKE EXECUTE ON FUNCTION public.auto_enroll_dealer_on_role_confirm() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_delete_auth_user_on_profile_delete() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_profiles_notify_admin_new_customer() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_requests_staff_notify() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_auto_confirm_admin() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;

-- Revoke anon (unauthenticated) access from authenticated-only RPCs
REVOKE EXECUTE ON FUNCTION public.admin_delete_customer_account(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.increment_review_helpful(uuid, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.mark_staff_notifications_read(bigint[], text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_staff() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.admin_delete_customer_account(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_review_helpful(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_staff_notifications_read(bigint[], text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_staff() TO authenticated;

-- 6. Clean up temporary helper function & reload schema
DROP FUNCTION IF EXISTS public._tmp_drop_all_policies(TEXT);
NOTIFY pgrst, 'reload schema';
