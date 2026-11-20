-- ==============================================================================
-- Guaranteed Full Customer Account Deletion (Profiles + Auth Users)
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-20
--
-- Ensures that when an Admin deletes a customer account from the Admin Panel,
-- ALL linked records and the Supabase Authentication (`auth.users`) login are
-- cleanly and permanently removed without foreign-key failures.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.admin_delete_customer_account(target_user_id UUID)
RETURNS VOID AS $$
DECLARE
    target_role TEXT;
BEGIN
    -- 1. Enforce Admin-only authorization
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Forbidden: Only administrators can permanently delete customer accounts.';
    END IF;

    -- 2. Protect Admin & Staff accounts from accidental deletion via customer endpoint
    SELECT LOWER(COALESCE(role, '')) INTO target_role
    FROM public.profiles
    WHERE id = target_user_id;

    IF target_role IN ('admin', 'clerk', 'inspector', 'cashier', 'staff') THEN
        RAISE EXCEPTION 'Protected account: Staff and Admin accounts cannot be deleted from Customer Accounts.';
    END IF;

    -- 3. Safely unlink regular_dealers (keep dealer record if present, clear user_id)
    UPDATE public.regular_dealers
    SET user_id = NULL
    WHERE user_id = target_user_id;

    -- 4. Remove child customer data in FK-safe order
    DELETE FROM public.notifications WHERE user_id = target_user_id;
    DELETE FROM public.payments WHERE request_id IN (
        SELECT id FROM public.requests WHERE user_id = target_user_id
    );
    DELETE FROM public.slaughter_inspection WHERE request_id IN (
        SELECT id FROM public.requests WHERE user_id = target_user_id
    );
    DELETE FROM public.requests WHERE user_id = target_user_id;
    DELETE FROM public.profiles WHERE id = target_user_id;

    -- 5. Remove Supabase Authentication records (sessions, identities, MFA, user)
    DELETE FROM auth.sessions WHERE user_id = target_user_id;
    DELETE FROM auth.identities WHERE user_id = target_user_id;
    DELETE FROM auth.mfa_factors WHERE user_id = target_user_id;
    DELETE FROM auth.users WHERE id = target_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION public.admin_delete_customer_account(UUID) TO authenticated;

-- Also harden the fallback profile-delete trigger so direct profile deletes clean auth tables too
CREATE OR REPLACE FUNCTION public.fn_delete_auth_user_on_profile_delete()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.regular_dealers SET user_id = NULL WHERE user_id = OLD.id;
    DELETE FROM auth.sessions WHERE user_id = OLD.id;
    DELETE FROM auth.identities WHERE user_id = OLD.id;
    DELETE FROM auth.mfa_factors WHERE user_id = OLD.id;
    DELETE FROM auth.users WHERE id = OLD.id;
    RETURN OLD;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_delete_auth_user_on_profile_delete failed: %', SQLERRM;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

DROP TRIGGER IF EXISTS trg_profiles_delete_auth_user ON public.profiles;
CREATE TRIGGER trg_profiles_delete_auth_user
  AFTER DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.fn_delete_auth_user_on_profile_delete();

NOTIFY pgrst, 'reload schema';
