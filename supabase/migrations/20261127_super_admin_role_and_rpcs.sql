-- ==============================================================================
-- Super Admin Role, Staff Governance & Password Management RPCs
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-27
--
-- 1. Introduces `super_admin` as the top-tier governance role above `admin`,
--    `clerk`, and `inspector`.
-- 2. Promotes `tcaaslaughterhouse@gmail.com` to `super_admin` in `public.profiles`.
-- 3. Keeps `public.is_admin()` returning TRUE for BOTH `super_admin` and `admin`
--    so all existing operational RLS policies remain 100% compatible.
-- 4. Provides `SECURITY DEFINER` RPCs for Super Admin–only password resets
--    and staff profile synchronization.
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Super Admin authorization helper
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN AS $$
DECLARE
  v_role TEXT;
  v_email TEXT;
BEGIN
  SELECT LOWER(COALESCE(role, '')), LOWER(COALESCE(email, ''))
  INTO v_role, v_email
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_role IN ('super_admin', 'super admin', 'superadmin') THEN
    RETURN TRUE;
  END IF;

  IF v_email = 'tcaaslaughterhouse@gmail.com' THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;

-- 2. Keep public.is_admin() backward-compatible (TRUE for both super_admin and admin,
--    checking both public.profiles.role and auth.users.raw_user_meta_data->>'role')
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
DECLARE
  v_role TEXT;
  v_meta_role TEXT;
  v_email TEXT;
BEGIN
  IF public.is_super_admin() THEN
    RETURN TRUE;
  END IF;

  SELECT LOWER(COALESCE(role, '')), LOWER(COALESCE(email, ''))
  INTO v_role, v_email
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_role IN ('admin', 'super_admin', 'super admin', 'superadmin')
     OR v_email IN ('admin@tabaco.gov.ph', 'tcaaslaughterhouse@gmail.com') THEN
    RETURN TRUE;
  END IF;

  SELECT LOWER(COALESCE(raw_user_meta_data->>'role', '')), LOWER(COALESCE(email, ''))
  INTO v_meta_role, v_email
  FROM auth.users
  WHERE id = auth.uid();

  RETURN v_meta_role IN ('admin', 'super_admin', 'super admin', 'superadmin')
      OR v_email IN ('admin@tabaco.gov.ph', 'tcaaslaughterhouse@gmail.com');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- 3. Bootstrap primary IT owner account to super_admin
UPDATE public.profiles
SET role = 'super_admin'
WHERE LOWER(COALESCE(email, '')) = 'tcaaslaughterhouse@gmail.com';

UPDATE auth.users
SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || '{"role": "super_admin"}'::jsonb
WHERE LOWER(COALESCE(email, '')) = 'tcaaslaughterhouse@gmail.com';

-- 4. Super Admin RPC: Set or Reset Password for Admin / Clerk / Inspector
CREATE OR REPLACE FUNCTION public.super_admin_set_staff_password(
  p_target_email TEXT,
  p_new_password TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
  v_user_id UUID;
  v_clean_email TEXT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Forbidden: Only Super Admin can reset staff or admin passwords.';
  END IF;

  v_clean_email := LOWER(TRIM(COALESCE(p_target_email, '')));
  IF v_clean_email = '' THEN
    RAISE EXCEPTION 'Target email is required.';
  END IF;

  IF LENGTH(COALESCE(p_new_password, '')) < 6 THEN
    RAISE EXCEPTION 'Password must be at least 6 characters.';
  END IF;

  SELECT id INTO v_user_id
  FROM auth.users
  WHERE LOWER(email) = v_clean_email
  LIMIT 1;

  IF v_user_id IS NULL THEN
    -- Staff account may be managed purely via system_settings roster (no auth.users row yet)
    RETURN FALSE;
  END IF;

  UPDATE auth.users
  SET encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
      updated_at = NOW()
  WHERE id = v_user_id;

  -- Revoke existing sessions so the staff user signs in with the newly assigned password
  DELETE FROM auth.sessions WHERE user_id = v_user_id;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, extensions;

GRANT EXECUTE ON FUNCTION public.super_admin_set_staff_password(TEXT, TEXT) TO authenticated;

-- 5. Super Admin RPC: Sync Staff Profile Role & Active Status
CREATE OR REPLACE FUNCTION public.super_admin_sync_staff_profile(
  p_target_email TEXT,
  p_full_name TEXT,
  p_role TEXT,
  p_is_active BOOLEAN DEFAULT TRUE
)
RETURNS VOID AS $$
DECLARE
  v_clean_email TEXT;
  v_norm_role TEXT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Forbidden: Only Super Admin can manage staff roles.';
  END IF;

  v_clean_email := LOWER(TRIM(COALESCE(p_target_email, '')));
  IF v_clean_email = '' THEN
    RETURN;
  END IF;

  v_norm_role := CASE LOWER(TRIM(COALESCE(p_role, 'admin')))
    WHEN 'super admin' THEN 'super_admin'
    WHEN 'superadmin' THEN 'super_admin'
    WHEN 'super_admin' THEN 'super_admin'
    WHEN 'inspector' THEN 'inspector'
    WHEN 'clerk' THEN 'clerk'
    ELSE 'admin'
  END;

  UPDATE public.profiles
  SET display_name = COALESCE(NULLIF(TRIM(p_full_name), ''), display_name),
      role = v_norm_role,
      is_active = COALESCE(p_is_active, TRUE)
  WHERE LOWER(email) = v_clean_email;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION public.super_admin_sync_staff_profile(TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

NOTIFY pgrst, 'reload schema';
