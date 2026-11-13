-- ==============================================================================
-- Full-Workflow Staff Notification Bell (Admin / Clerk / Inspector)
-- Date: 2026-11-13
-- Covers the complete operational handoff pipeline:
--   1. New Request (pending)                         -> Clerk (+ Admin)
--   2. Separate Facility Walk-In (slaughter_started) -> Inspector (+ Admin)
--   3. Clerk Verifies Docs (doc_verified)            -> Inspector (+ Admin)
--   4. Inspector Completes Process (releasable / mic_generated / payment_pending) -> Clerk (+ Admin)
--   5. Payment Settled (paid)                        -> Clerk (+ Admin)
--   6. Inspection Flagged / Condemned                -> Admin
-- Includes dedup_key to prevent duplicate notifications and backfills open items.
-- ==============================================================================

-- 1. Ensure helper function is_staff() exists
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND LOWER(COALESCE(role, '')) IN ('admin', 'inspector', 'cashier', 'clerk', 'staff')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- 2. Ensure table & columns exist
CREATE TABLE IF NOT EXISTS public.staff_notifications (
  id           BIGSERIAL PRIMARY KEY,
  target_role  TEXT NOT NULL CHECK (target_role IN ('Clerk', 'Inspector', 'Admin')),
  type         TEXT NOT NULL,
  title        TEXT NOT NULL,
  message      TEXT NOT NULL,
  request_id   BIGINT REFERENCES public.requests(id) ON DELETE CASCADE,
  reference_no TEXT,
  dedup_key    TEXT,
  read_by      TEXT[] NOT NULL DEFAULT '{}',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Upgrade existing table if created by earlier migration
ALTER TABLE public.staff_notifications
  ADD COLUMN IF NOT EXISTS dedup_key TEXT;

ALTER TABLE public.staff_notifications
  DROP CONSTRAINT IF EXISTS staff_notifications_target_role_check;

ALTER TABLE public.staff_notifications
  ADD CONSTRAINT staff_notifications_target_role_check
  CHECK (target_role IN ('Clerk', 'Inspector', 'Admin'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_notif_dedup_key
  ON public.staff_notifications (dedup_key)
  WHERE dedup_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_staff_notif_role_created
  ON public.staff_notifications (target_role, created_at DESC);

ALTER TABLE public.staff_notifications ENABLE ROW LEVEL SECURITY;

-- 3. Open RLS policies for staff web portal queries
DROP POLICY IF EXISTS "Staff read staff_notifications" ON public.staff_notifications;
CREATE POLICY "Staff read staff_notifications"
  ON public.staff_notifications FOR SELECT
  TO authenticated, anon
  USING (true);

DROP POLICY IF EXISTS "Staff insert staff_notifications" ON public.staff_notifications;
CREATE POLICY "Staff insert staff_notifications"
  ON public.staff_notifications FOR INSERT
  TO authenticated, anon
  WITH CHECK (true);

DROP POLICY IF EXISTS "Staff update staff_notifications" ON public.staff_notifications;
CREATE POLICY "Staff update staff_notifications"
  ON public.staff_notifications FOR UPDATE
  TO authenticated, anon
  USING (true)
  WITH CHECK (true);

-- 4. Trigger: create staff notifications across all workflow handoffs
CREATE OR REPLACE FUNCTION public.fn_requests_staff_notify()
RETURNS TRIGGER AS $$
DECLARE
  ref  TEXT := 'MI-' || EXTRACT(YEAR FROM COALESCE(NEW.created_at, now()))::INT || '-' || LPAD(NEW.id::TEXT, 3, '0');
  cust TEXT := COALESCE(NULLIF(TRIM(NEW.customer_name), ''), 'A customer');
  dkey TEXT;
BEGIN
  -- 1) New online/walk-in request awaiting receiving review -> Clerk
  IF TG_OP = 'INSERT' AND COALESCE(NEW.status, 'pending') = 'pending' THEN
    dkey := 'req_' || NEW.id || '_new_request';
    INSERT INTO public.staff_notifications (target_role, type, title, message, request_id, reference_no, dedup_key)
    VALUES ('Clerk', 'new_request', 'New Slaughter Request',
            cust || ' submitted ' || ref || ' — awaiting receiving review.',
            NEW.id, ref, dkey)
    ON CONFLICT (dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;

  -- 2) Walk-in routed directly to Separate Facility -> Inspector
  ELSIF (TG_OP = 'INSERT' AND NEW.status = 'slaughter_started')
     OR (TG_OP = 'UPDATE' AND NEW.status = 'slaughter_started'
         AND COALESCE(OLD.status, '') IN ('pending', 'approved')) THEN
    dkey := 'req_' || NEW.id || '_separate_facility';
    INSERT INTO public.staff_notifications (target_role, type, title, message, request_id, reference_no, dedup_key)
    VALUES ('Inspector', 'separate_facility', 'Ready for Slaughter & Inspection',
            ref || ' (' || cust || ') routed to floor — ready for inspection.',
            NEW.id, ref, dkey)
    ON CONFLICT (dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;

  -- 3) Clerk verified documents -> Inspector
  ELSIF TG_OP = 'UPDATE'
        AND NEW.status = 'doc_verified'
        AND OLD.status IS DISTINCT FROM 'doc_verified' THEN
    dkey := 'req_' || NEW.id || '_doc_verified';
    INSERT INTO public.staff_notifications (target_role, type, title, message, request_id, reference_no, dedup_key)
    VALUES ('Inspector', 'doc_verified', 'Ready for Ante-Mortem',
            ref || ' (' || cust || ') documents verified by clerk — ready for inspection.',
            NEW.id, ref, dkey)
    ON CONFLICT (dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;

  -- 4) Inspector completed slaughter/post-mortem -> Clerk (Billing & Payment)
  ELSIF TG_OP = 'UPDATE'
        AND NEW.status IN ('releasable', 'mic_generated', 'payment_pending')
        AND OLD.status IS DISTINCT FROM NEW.status
        AND COALESCE(OLD.status, '') NOT IN ('releasable', 'mic_generated', 'payment_pending', 'paid', 'released', 'completed') THEN
    dkey := 'req_' || NEW.id || '_ready_for_payment';
    INSERT INTO public.staff_notifications (target_role, type, title, message, request_id, reference_no, dedup_key)
    VALUES ('Clerk', 'ready_for_payment', 'Ready for Billing & Payment',
            ref || ' (' || cust || ') passed inspection — ready for cashiering & payment.',
            NEW.id, ref, dkey)
    ON CONFLICT (dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;

  -- 5) Payment settled -> Clerk (Meat Releasing)
  ELSIF TG_OP = 'UPDATE'
        AND NEW.status = 'paid'
        AND OLD.status IS DISTINCT FROM 'paid' THEN
    dkey := 'req_' || NEW.id || '_ready_for_release';
    INSERT INTO public.staff_notifications (target_role, type, title, message, request_id, reference_no, dedup_key)
    VALUES ('Clerk', 'ready_for_release', 'Payment Confirmed — Ready for Release',
            ref || ' (' || cust || ') payment settled — ready for meat releasing.',
            NEW.id, ref, dkey)
    ON CONFLICT (dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;

  -- 6) Flagged / failed / condemned -> Admin oversight
  ELSIF TG_OP = 'UPDATE'
        AND NEW.status IN ('anti_mortem_failed', 'post_mortem_failed', 'condemned', 'delay_error')
        AND OLD.status IS DISTINCT FROM NEW.status THEN
    dkey := 'req_' || NEW.id || '_flagged_' || NEW.status;
    INSERT INTO public.staff_notifications (target_role, type, title, message, request_id, reference_no, dedup_key)
    VALUES ('Admin', 'inspection_flagged', 'Inspection Flagged',
            ref || ' (' || cust || ') marked as ' || REPLACE(NEW.status, '_', ' ') || '.',
            NEW.id, ref, dkey)
    ON CONFLICT (dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'fn_requests_staff_notify failed: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_requests_staff_notify ON public.requests;
CREATE TRIGGER trg_requests_staff_notify
  AFTER INSERT OR UPDATE OF status ON public.requests
  FOR EACH ROW EXECUTE FUNCTION public.fn_requests_staff_notify();

-- 5. Atomic "mark as read" (acknowledge) helper
CREATE OR REPLACE FUNCTION public.mark_staff_notifications_read(p_ids BIGINT[], p_email TEXT)
RETURNS VOID AS $$
  UPDATE public.staff_notifications
     SET read_by = array_append(read_by, lower(p_email))
   WHERE id = ANY(p_ids)
     AND NOT (lower(p_email) = ANY(read_by));
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.mark_staff_notifications_read(BIGINT[], TEXT) TO authenticated, anon;

-- 6. Realtime publication
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.staff_notifications;
EXCEPTION WHEN duplicate_object THEN NULL;
          WHEN undefined_object THEN NULL;
END $$;

-- 7. Backfill currently open requests so existing pending tasks appear immediately
INSERT INTO public.staff_notifications (target_role, type, title, message, request_id, reference_no, dedup_key, created_at)
SELECT
  CASE
    WHEN r.status = 'pending' THEN 'Clerk'
    WHEN r.status = 'doc_verified' THEN 'Inspector'
    WHEN r.status IN ('releasable', 'mic_generated', 'payment_pending') THEN 'Clerk'
    WHEN r.status = 'paid' THEN 'Clerk'
  END AS target_role,
  CASE
    WHEN r.status = 'pending' THEN 'new_request'
    WHEN r.status = 'doc_verified' THEN 'doc_verified'
    WHEN r.status IN ('releasable', 'mic_generated', 'payment_pending') THEN 'ready_for_payment'
    WHEN r.status = 'paid' THEN 'ready_for_release'
  END AS type,
  CASE
    WHEN r.status = 'pending' THEN 'New Slaughter Request'
    WHEN r.status = 'doc_verified' THEN 'Ready for Ante-Mortem'
    WHEN r.status IN ('releasable', 'mic_generated', 'payment_pending') THEN 'Ready for Billing & Payment'
    WHEN r.status = 'paid' THEN 'Payment Confirmed — Ready for Release'
  END AS title,
  CASE
    WHEN r.status = 'pending' THEN COALESCE(NULLIF(TRIM(r.customer_name), ''), 'A customer') || ' submitted MI-' || EXTRACT(YEAR FROM COALESCE(r.created_at, now()))::INT || '-' || LPAD(r.id::TEXT, 3, '0') || ' — awaiting receiving review.'
    WHEN r.status = 'doc_verified' THEN 'MI-' || EXTRACT(YEAR FROM COALESCE(r.created_at, now()))::INT || '-' || LPAD(r.id::TEXT, 3, '0') || ' (' || COALESCE(NULLIF(TRIM(r.customer_name), ''), 'A customer') || ') documents verified by clerk — ready for inspection.'
    WHEN r.status IN ('releasable', 'mic_generated', 'payment_pending') THEN 'MI-' || EXTRACT(YEAR FROM COALESCE(r.created_at, now()))::INT || '-' || LPAD(r.id::TEXT, 3, '0') || ' (' || COALESCE(NULLIF(TRIM(r.customer_name), ''), 'A customer') || ') passed inspection — ready for cashiering & payment.'
    WHEN r.status = 'paid' THEN 'MI-' || EXTRACT(YEAR FROM COALESCE(r.created_at, now()))::INT || '-' || LPAD(r.id::TEXT, 3, '0') || ' (' || COALESCE(NULLIF(TRIM(r.customer_name), ''), 'A customer') || ') payment settled — ready for meat releasing.'
  END AS message,
  r.id,
  'MI-' || EXTRACT(YEAR FROM COALESCE(r.created_at, now()))::INT || '-' || LPAD(r.id::TEXT, 3, '0'),
  CASE
    WHEN r.status = 'pending' THEN 'req_' || r.id || '_new_request'
    WHEN r.status = 'doc_verified' THEN 'req_' || r.id || '_doc_verified'
    WHEN r.status IN ('releasable', 'mic_generated', 'payment_pending') THEN 'req_' || r.id || '_ready_for_payment'
    WHEN r.status = 'paid' THEN 'req_' || r.id || '_ready_for_release'
  END AS dedup_key,
  COALESCE(r.created_at, now())
FROM public.requests r
WHERE r.status IN ('pending', 'doc_verified', 'releasable', 'mic_generated', 'payment_pending', 'paid')
ON CONFLICT (dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;
