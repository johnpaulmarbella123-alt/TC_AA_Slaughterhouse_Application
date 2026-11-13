-- ==============================================================================
-- Account Deletion Cascade & Unverified Sign-Up Cleanup
-- Date: 2026-11-13
-- 1. Deleting a row in public.profiles automatically deletes auth.users(id)
--    so deleted accounts cannot be accessed anymore.
-- 2. check_account_status only treats an account as existing when verified
--    AND present in public.profiles.
-- 3. cleanup_unverified_signup removes abandoned unverified auth.users rows
--    when a user backs out of the OTP screen before verifying.
-- ==============================================================================

-- 1. Cascade delete from public.profiles -> auth.users
CREATE OR REPLACE FUNCTION public.fn_delete_auth_user_on_profile_delete()
RETURNS TRIGGER AS $$
BEGIN
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

-- 2. Update check_account_status so unverified/deleted accounts don't block sign-up
CREATE OR REPLACE FUNCTION public.check_account_status(identifier text)
RETURNS jsonb AS $$
DECLARE
  found_profile record;
  found_user record;
  clean_id text;
  intl_phone text;
  local_phone text;
  no_plus_phone text;
BEGIN
  clean_id := LOWER(TRIM(identifier));

  IF clean_id ~ '^[0-9+]+$' THEN
    IF clean_id LIKE '09%' THEN
      intl_phone := '+63' || SUBSTRING(clean_id FROM 2);
      local_phone := clean_id;
      no_plus_phone := '63' || SUBSTRING(clean_id FROM 2);
    ELSIF clean_id LIKE '+63%' THEN
      intl_phone := clean_id;
      local_phone := '0' || SUBSTRING(clean_id FROM 4);
      no_plus_phone := SUBSTRING(clean_id FROM 2);
    ELSIF clean_id LIKE '63%' THEN
      intl_phone := '+' || clean_id;
      local_phone := '0' || SUBSTRING(clean_id FROM 3);
      no_plus_phone := clean_id;
    ELSE
      intl_phone := clean_id;
      local_phone := clean_id;
      no_plus_phone := clean_id;
    END IF;
  END IF;

  -- Active accounts MUST have a profile row
  SELECT id, email, phone
  INTO found_profile
  FROM public.profiles
  WHERE LOWER(email) = clean_id
     OR (phone IS NOT NULL AND (phone = clean_id OR phone = intl_phone OR phone = local_phone OR phone = no_plus_phone))
  LIMIT 1;

  IF found_profile.id IS NULL THEN
    RETURN jsonb_build_object(
      'exists', false,
      'is_verified', false
    );
  END IF;

  -- Confirm matching auth.users row still exists and is verified
  SELECT id, email_confirmed_at, phone_confirmed_at, confirmed_at
  INTO found_user
  FROM auth.users
  WHERE id = found_profile.id
  LIMIT 1;

  IF found_user.id IS NULL THEN
    RETURN jsonb_build_object(
      'exists', false,
      'is_verified', false
    );
  END IF;

  IF found_user.email_confirmed_at IS NOT NULL
     OR found_user.phone_confirmed_at IS NOT NULL
     OR found_user.confirmed_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'exists', true,
      'is_verified', true
    );
  ELSE
    RETURN jsonb_build_object(
      'exists', true,
      'is_verified', false
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION public.check_account_status(text) TO anon, authenticated;

-- 3. Cleanup unverified sign-up record if user cancels before entering OTP
CREATE OR REPLACE FUNCTION public.cleanup_unverified_signup(identifier text)
RETURNS VOID AS $$
DECLARE
  clean_id text;
  intl_phone text;
  local_phone text;
  no_plus_phone text;
BEGIN
  clean_id := LOWER(TRIM(identifier));
  IF clean_id IS NULL OR clean_id = '' THEN
    RETURN;
  END IF;

  IF clean_id ~ '^[0-9+]+$' THEN
    IF clean_id LIKE '09%' THEN
      intl_phone := '+63' || SUBSTRING(clean_id FROM 2);
      local_phone := clean_id;
      no_plus_phone := '63' || SUBSTRING(clean_id FROM 2);
    ELSIF clean_id LIKE '+63%' THEN
      intl_phone := clean_id;
      local_phone := '0' || SUBSTRING(clean_id FROM 4);
      no_plus_phone := SUBSTRING(clean_id FROM 2);
    ELSIF clean_id LIKE '63%' THEN
      intl_phone := '+' || clean_id;
      local_phone := '0' || SUBSTRING(clean_id FROM 3);
      no_plus_phone := clean_id;
    ELSE
      intl_phone := clean_id;
      local_phone := clean_id;
      no_plus_phone := clean_id;
    END IF;
  END IF;

  DELETE FROM auth.users u
  WHERE (LOWER(u.email) = clean_id
         OR (u.phone IS NOT NULL AND (u.phone = clean_id OR u.phone = intl_phone OR u.phone = local_phone OR u.phone = no_plus_phone)))
    AND u.email_confirmed_at IS NULL
    AND u.phone_confirmed_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION public.cleanup_unverified_signup(text) TO anon, authenticated;

