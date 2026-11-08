-- ==============================================================================
-- Selective Admin Demo Account Auto-Confirmation Trigger
-- Target System: Tabaco City Slaughterhouse Management System (TCAASlaughter_App)
-- Date: 2026-11-08
-- ==============================================================================

-- 1. Trigger to automatically confirm email ONLY for Admin accounts.
-- Clerk and Inspector accounts will continue to require real email confirmation.
CREATE OR REPLACE FUNCTION public.handle_auto_confirm_admin()
RETURNS TRIGGER AS $$
BEGIN
    IF LOWER(COALESCE(NEW.raw_user_meta_data->>'role', '')) = 'admin' THEN
        NEW.email_confirmed_at = COALESCE(NEW.email_confirmed_at, NOW());
        NEW.confirmed_at = COALESCE(NEW.confirmed_at, NOW());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Bind trigger to auth.users BEFORE INSERT
DROP TRIGGER IF EXISTS on_auth_user_created_auto_confirm_admin ON auth.users;
CREATE TRIGGER on_auth_user_created_auto_confirm_admin
    BEFORE INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_auto_confirm_admin();

-- 3. Also auto-confirm on UPDATE if metadata role was set to admin
CREATE OR REPLACE FUNCTION public.handle_auto_confirm_admin_update()
RETURNS TRIGGER AS $$
BEGIN
    IF LOWER(COALESCE(NEW.raw_user_meta_data->>'role', '')) = 'admin' AND NEW.email_confirmed_at IS NULL THEN
        NEW.email_confirmed_at = NOW();
        NEW.confirmed_at = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_updated_auto_confirm_admin ON auth.users;
CREATE TRIGGER on_auth_user_updated_auto_confirm_admin
    BEFORE UPDATE ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_auto_confirm_admin_update();

