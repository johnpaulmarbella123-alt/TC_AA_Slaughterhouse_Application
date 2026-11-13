-- ==============================================================================
-- Admin Customer Accounts Management & New Registration Bell Notification
-- Date: 2026-11-13
-- 1. Adds is_active, deactivated_at, deactivation_reason to public.profiles.
-- 2. Adds trigger to notify Admin Bell whenever a new mobile customer registers.
-- 3. Ensures staff/Admin can read, deactivate/reactivate, and delete customers.
-- ==============================================================================

-- 1. Add account status & role columns safely
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMPTZ;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS deactivation_reason TEXT;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS dealer_category TEXT;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS role_confirmed BOOLEAN DEFAULT false;

-- 2. Staff/Admin RLS policy on profiles for viewing, deactivating, and deleting customers
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_staff') THEN
    DROP POLICY IF EXISTS "Staff manage profiles" ON public.profiles;
    CREATE POLICY "Staff manage profiles"
      ON public.profiles FOR ALL
      TO authenticated
      USING (public.is_staff())
      WITH CHECK (public.is_staff());
  END IF;
END $$;

-- 3. Trigger: notify Admin Bell when a new mobile customer registers
CREATE OR REPLACE FUNCTION public.fn_profiles_notify_admin_new_customer()
RETURNS TRIGGER AS $$
DECLARE
  v_role    TEXT := LOWER(COALESCE(NEW.role, 'customer'));
  v_name    TEXT := COALESCE(NULLIF(TRIM(NEW.display_name), ''), 'New Customer');
  v_contact TEXT := COALESCE(NULLIF(TRIM(NEW.phone), ''), NULLIF(TRIM(NEW.email), ''), 'Mobile App');
  v_dkey    TEXT := 'cust_' || NEW.id || '_registered';
BEGIN
  IF v_role NOT IN ('admin', 'inspector', 'cashier', 'clerk', 'staff') THEN
    INSERT INTO public.staff_notifications (
      target_role, type, title, message, dedup_key
    ) VALUES (
      'Admin',
      'new_customer',
      'New Mobile Customer Registered',
      v_name || ' (' || v_contact || ') just signed up on the mobile app.',
      v_dkey
    )
    ON CONFLICT (dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'fn_profiles_notify_admin_new_customer failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_profiles_notify_admin_new_customer ON public.profiles;
CREATE TRIGGER trg_profiles_notify_admin_new_customer
  AFTER INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.fn_profiles_notify_admin_new_customer();

