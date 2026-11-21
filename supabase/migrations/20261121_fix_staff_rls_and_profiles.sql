-- ==============================================================================
-- Fix Admin Panel Not Seeing Customer Requests (Staff Profiles & RLS Hardening)
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-21
--
-- Fixes:
-- 1. Restores/upserts the 3 official staff accounts in public.profiles from auth.users
--    (Admin, Clerk, Inspector) so role-based RLS checks always match.
-- 2. Upgrades public.is_admin() and public.is_staff() to check:
--    a) public.profiles (normalized role variants)
--    b) auth.users.email (official staff emails)
--    c) public.system_settings ('staff_accounts') active staff list
-- ==============================================================================

-- 1. Upsert the 3 official staff rows in public.profiles directly from auth.users
INSERT INTO public.profiles (id, email, display_name, role)
SELECT
    u.id,
    u.email,
    CASE LOWER(COALESCE(u.email, ''))
        WHEN 'tcaaslaughterhouse@gmail.com' THEN 'Abattoir Administrator'
        WHEN 'jonathanbino63@gmail.com'     THEN 'Receiving Clerk'
        WHEN 'andriebarasona46@gmail.com'   THEN 'Meat Inspector'
        ELSE COALESCE(u.raw_user_meta_data->>'display_name', u.email)
    END,
    CASE LOWER(COALESCE(u.email, ''))
        WHEN 'tcaaslaughterhouse@gmail.com' THEN 'admin'
        WHEN 'jonathanbino63@gmail.com'     THEN 'clerk'
        WHEN 'andriebarasona46@gmail.com'   THEN 'inspector'
        ELSE 'customer'
    END
FROM auth.users u
WHERE LOWER(COALESCE(u.email, '')) IN (
    'tcaaslaughterhouse@gmail.com',
    'jonathanbino63@gmail.com',
    'andriebarasona46@gmail.com'
)
ON CONFLICT (id) DO UPDATE
SET
    email = EXCLUDED.email,
    role  = EXCLUDED.role;

-- 2. Upgrade public.is_admin() to be resilient across profiles, auth.users, and staff_accounts
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
DECLARE
    uid UUID := (SELECT auth.uid());
    user_email TEXT;
BEGIN
    IF uid IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check public.profiles role
    IF EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = uid
          AND LOWER(TRIM(COALESCE(p.role, ''))) IN ('admin', 'administrator', 'abattoir administrator')
    ) THEN
        RETURN TRUE;
    END IF;

    -- Check auth.users email against official admin & active system_settings staff_accounts
    SELECT LOWER(TRIM(COALESCE(u.email, ''))) INTO user_email
    FROM auth.users u
    WHERE u.id = uid;

    IF user_email = 'tcaaslaughterhouse@gmail.com' THEN
        RETURN TRUE;
    END IF;

    IF user_email IS NOT NULL AND user_email <> '' AND EXISTS (
        SELECT 1
        FROM public.system_settings s,
             LATERAL jsonb_array_elements(
                 CASE WHEN jsonb_typeof(s.value) = 'array' THEN s.value ELSE '[]'::jsonb END
             ) elem
        WHERE s.key = 'staff_accounts'
          AND LOWER(TRIM(COALESCE(elem->>'email', ''))) = user_email
          AND COALESCE((elem->>'isActive')::boolean, TRUE) = TRUE
          AND LOWER(TRIM(COALESCE(elem->>'role', ''))) IN ('admin', 'administrator', 'abattoir administrator')
    ) THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, auth;

-- 3. Upgrade public.is_staff() to be resilient across profiles, auth.users, and staff_accounts
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS BOOLEAN AS $$
DECLARE
    uid UUID := (SELECT auth.uid());
    user_email TEXT;
BEGIN
    IF uid IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check public.profiles role
    IF EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = uid
          AND LOWER(TRIM(COALESCE(p.role, ''))) IN (
              'admin', 'administrator', 'abattoir administrator',
              'clerk', 'receiving clerk',
              'inspector', 'meat inspector',
              'cashier', 'staff'
          )
    ) THEN
        RETURN TRUE;
    END IF;

    -- Check auth.users email against official staff & active system_settings staff_accounts
    SELECT LOWER(TRIM(COALESCE(u.email, ''))) INTO user_email
    FROM auth.users u
    WHERE u.id = uid;

    IF user_email IN (
        'tcaaslaughterhouse@gmail.com',
        'jonathanbino63@gmail.com',
        'andriebarasona46@gmail.com'
    ) THEN
        RETURN TRUE;
    END IF;

    IF user_email IS NOT NULL AND user_email <> '' AND EXISTS (
        SELECT 1
        FROM public.system_settings s,
             LATERAL jsonb_array_elements(
                 CASE WHEN jsonb_typeof(s.value) = 'array' THEN s.value ELSE '[]'::jsonb END
             ) elem
        WHERE s.key = 'staff_accounts'
          AND LOWER(TRIM(COALESCE(elem->>'email', ''))) = user_email
          AND COALESCE((elem->>'isActive')::boolean, TRUE) = TRUE
    ) THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, auth;

-- 4. Lock down grants & reload PostgREST schema cache
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_staff() TO authenticated;

NOTIFY pgrst, 'reload schema';

-- 5. Verification check: confirm all 3 staff profiles & existing requests
SELECT id, email, display_name, role
FROM public.profiles
WHERE LOWER(COALESCE(email, '')) IN (
    'tcaaslaughterhouse@gmail.com',
    'jonathanbino63@gmail.com',
    'andriebarasona46@gmail.com'
)
ORDER BY role;
