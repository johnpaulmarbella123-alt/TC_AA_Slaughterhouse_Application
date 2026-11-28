-- ==============================================================================
-- Dealer Role Change Requests (Barangay <-> Market 2-Step Verification)
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-28
--
-- 1. Customers locked as Barangay Dealer or Market Dealer can submit a role
--    change request to Admin (reviewed inside Meat Dealers Directory).
-- 2. Admin approves (`approved_awaiting_verification`), which unlocks the
--    customer's formal Role Verification form in the Mobile App.
-- 3. Once the customer completes formal verification (entering new location /
--    stall & uploading the required document), `complete_dealer_role_switch`
--    atomically marks the request `completed` and updates `profiles` +
--    `regular_dealers`.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.dealer_role_change_requests (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  customer_name TEXT NOT NULL DEFAULT '',
  from_role TEXT NOT NULL CHECK (from_role IN ('barangay', 'market')),
  requested_role TEXT NOT NULL CHECK (requested_role IN ('barangay', 'market')),
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved_awaiting_verification', 'completed', 'rejected')),
  admin_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_dealer_role_change_user
  ON public.dealer_role_change_requests (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_dealer_role_change_status
  ON public.dealer_role_change_requests (status, created_at DESC);

ALTER TABLE public.dealer_role_change_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view own role change requests" ON public.dealer_role_change_requests;
CREATE POLICY "Customers can view own role change requests"
  ON public.dealer_role_change_requests
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "Customers can create own role change requests" ON public.dealer_role_change_requests;
CREATE POLICY "Customers can create own role change requests"
  ON public.dealer_role_change_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id AND from_role <> requested_role);

DROP POLICY IF EXISTS "Admins can update role change requests" ON public.dealer_role_change_requests;
CREATE POLICY "Admins can update role change requests"
  ON public.dealer_role_change_requests
  FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Atomic RPC called when the customer finishes formal Role Verification after Admin approval
CREATE OR REPLACE FUNCTION public.complete_dealer_role_switch(
  p_request_id BIGINT,
  p_new_role TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
  v_req RECORD;
  v_norm_role TEXT;
BEGIN
  v_norm_role := LOWER(TRIM(COALESCE(p_new_role, '')));
  IF v_norm_role NOT IN ('barangay', 'market') THEN
    RAISE EXCEPTION 'Invalid target dealer role.';
  END IF;

  SELECT * INTO v_req
  FROM public.dealer_role_change_requests
  WHERE id = p_request_id
    AND user_id = auth.uid()
    AND status = 'approved_awaiting_verification'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  UPDATE public.dealer_role_change_requests
  SET status = 'completed',
      verified_at = NOW()
  WHERE id = p_request_id;

  UPDATE public.profiles
  SET dealer_category = v_norm_role,
      role_confirmed = TRUE
  WHERE id = auth.uid();

  -- Keep Meat Dealers Directory (`regular_dealers`) in sync if dealer has an entry
  BEGIN
    UPDATE public.regular_dealers
    SET category = v_norm_role
    WHERE user_id = auth.uid()
       OR (
         COALESCE(TRIM(v_req.customer_name), '') <> ''
         AND LOWER(TRIM(name)) = LOWER(TRIM(v_req.customer_name))
       );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION public.complete_dealer_role_switch(BIGINT, TEXT) TO authenticated;

-- Enable Supabase Realtime so Admin Meat Dealers Directory & Mobile App sync live
ALTER TABLE public.dealer_role_change_requests REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'dealer_role_change_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.dealer_role_change_requests;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
