-- ==============================================================================
-- Customer Account Warnings & Restorable Deleted Accounts Archive
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-27
--
-- 1. Adds warning tracking columns to `public.profiles` so Admins must issue
--    at least one warning before deactivating a customer account.
-- 2. Creates `public.deleted_customer_accounts` to archive deleted customer
--    records cleanly for future restoration when requested with valid reason.
-- 3. Replaces the destructive auth-wipe trigger with safe archive + ban RPCs
--    (`admin_archive_and_delete_customer` and `admin_restore_deleted_customer`).
-- ==============================================================================

-- 1. Warning tracking columns on public.profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS warning_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_warning_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_warning_reason TEXT;

-- 2. Dedicated archive table for deleted customer accounts
CREATE TABLE IF NOT EXISTS public.deleted_customer_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  original_user_id UUID NOT NULL,
  display_name TEXT,
  email TEXT,
  phone TEXT,
  role TEXT DEFAULT 'customer',
  dealer_category TEXT,
  municipality TEXT,
  barangay TEXT,
  market_name TEXT,
  stall_number TEXT,
  address TEXT,
  warning_count INT NOT NULL DEFAULT 0,
  last_warning_reason TEXT,
  profile_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  deletion_reason TEXT NOT NULL DEFAULT 'Deleted by Admin',
  deleted_by TEXT,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  restored_at TIMESTAMPTZ,
  restored_by TEXT,
  restoration_reason TEXT
);

CREATE INDEX IF NOT EXISTS idx_deleted_customer_accounts_user_id
  ON public.deleted_customer_accounts (original_user_id);

CREATE INDEX IF NOT EXISTS idx_deleted_customer_accounts_active_archive
  ON public.deleted_customer_accounts (deleted_at DESC)
  WHERE restored_at IS NULL;

ALTER TABLE public.deleted_customer_accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins manage deleted_customer_accounts" ON public.deleted_customer_accounts;
CREATE POLICY "Admins manage deleted_customer_accounts"
  ON public.deleted_customer_accounts
  FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- 3. Drop the old destructive trigger so archiving from profiles does not wipe auth.users
DROP TRIGGER IF EXISTS trg_profiles_delete_auth_user ON public.profiles;

-- 4. Archive & Delete Customer Account RPC (preserves auth.users banned so it can be restored)
CREATE OR REPLACE FUNCTION public.admin_archive_and_delete_customer(
  target_user_id UUID,
  p_deletion_reason TEXT DEFAULT 'Deleted by Admin',
  p_deleted_by TEXT DEFAULT 'Admin'
)
RETURNS UUID AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_archive_id UUID;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: Only administrators can delete customer accounts.';
  END IF;

  SELECT * INTO v_profile
  FROM public.profiles
  WHERE id = target_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer profile not found.';
  END IF;

  IF LOWER(COALESCE(v_profile.role, '')) IN ('admin', 'clerk', 'inspector', 'cashier', 'staff') THEN
    RAISE EXCEPTION 'Protected account: Staff and Admin accounts cannot be deleted from Customer Accounts.';
  END IF;

  -- Archive full profile snapshot into public.deleted_customer_accounts
  INSERT INTO public.deleted_customer_accounts (
    original_user_id,
    display_name,
    email,
    phone,
    role,
    dealer_category,
    municipality,
    barangay,
    market_name,
    stall_number,
    address,
    warning_count,
    last_warning_reason,
    profile_snapshot,
    deletion_reason,
    deleted_by,
    deleted_at
  )
  VALUES (
    v_profile.id,
    v_profile.display_name,
    v_profile.email,
    v_profile.phone,
    COALESCE(v_profile.role, 'customer'),
    v_profile.dealer_category,
    v_profile.municipality,
    v_profile.barangay,
    v_profile.market_name,
    v_profile.stall_number,
    v_profile.address,
    COALESCE(v_profile.warning_count, 0),
    v_profile.last_warning_reason,
    to_jsonb(v_profile),
    COALESCE(NULLIF(TRIM(p_deletion_reason), ''), 'Deleted by Admin'),
    COALESCE(NULLIF(TRIM(p_deleted_by), ''), 'Admin'),
    NOW()
  )
  RETURNING id INTO v_archive_id;

  -- Remove from active public.profiles
  DELETE FROM public.profiles WHERE id = target_user_id;

  -- Revoke active sessions and ban auth login until restored
  DELETE FROM auth.sessions WHERE user_id = target_user_id;
  UPDATE auth.users
  SET banned_until = '2099-12-31T23:59:59Z'::timestamptz
  WHERE id = target_user_id;

  RETURN v_archive_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION public.admin_archive_and_delete_customer(UUID, TEXT, TEXT) TO authenticated;

-- 5. Restore Deleted Customer Account RPC
CREATE OR REPLACE FUNCTION public.admin_restore_deleted_customer(
  p_archive_id UUID,
  p_restoration_reason TEXT DEFAULT 'Restored by Admin upon valid customer request',
  p_restored_by TEXT DEFAULT 'Admin'
)
RETURNS VOID AS $$
DECLARE
  v_arch public.deleted_customer_accounts%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: Only administrators can restore deleted customer accounts.';
  END IF;

  SELECT * INTO v_arch
  FROM public.deleted_customer_accounts
  WHERE id = p_archive_id AND restored_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Archived customer record not found or already restored.';
  END IF;

  -- Re-insert customer row into public.profiles as active
  INSERT INTO public.profiles (
    id,
    display_name,
    email,
    phone,
    role,
    dealer_category,
    municipality,
    barangay,
    market_name,
    stall_number,
    address,
    is_active,
    deactivated_at,
    deactivation_reason,
    warning_count,
    last_warning_reason
  )
  VALUES (
    v_arch.original_user_id,
    v_arch.display_name,
    v_arch.email,
    v_arch.phone,
    COALESCE(v_arch.role, 'customer'),
    v_arch.dealer_category,
    v_arch.municipality,
    v_arch.barangay,
    v_arch.market_name,
    v_arch.stall_number,
    v_arch.address,
    TRUE,
    NULL,
    NULL,
    COALESCE(v_arch.warning_count, 0),
    v_arch.last_warning_reason
  )
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    is_active = TRUE,
    deactivated_at = NULL,
    deactivation_reason = NULL;

  -- Unban Supabase Auth login so customer can sign back in with original credentials
  UPDATE auth.users
  SET banned_until = NULL
  WHERE id = v_arch.original_user_id;

  -- Mark archive entry as restored for full audit trail
  UPDATE public.deleted_customer_accounts
  SET restored_at = NOW(),
      restored_by = COALESCE(NULLIF(TRIM(p_restored_by), ''), 'Admin'),
      restoration_reason = COALESCE(NULLIF(TRIM(p_restoration_reason), ''), 'Restored by Admin')
  WHERE id = p_archive_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION public.admin_restore_deleted_customer(UUID, TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
