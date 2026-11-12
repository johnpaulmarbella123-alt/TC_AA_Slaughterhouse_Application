-- ==============================================================================
-- Staff Notification Bell (Admin / Clerk / Inspector dashboards)
-- Date: 2026-11-12
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

-- 2. Create staff_notifications table
CREATE TABLE IF NOT EXISTS public.staff_notifications (
  id           BIGSERIAL PRIMARY KEY,
  target_role  TEXT NOT NULL CHECK (target_role IN ('Clerk', 'Inspector')),
  type         TEXT NOT NULL,                 -- 'new_request' | 'doc_verified'
  title        TEXT NOT NULL,
  message      TEXT NOT NULL,
  request_id   BIGINT REFERENCES public.requests(id) ON DELETE CASCADE,
  reference_no TEXT,
  read_by      TEXT[] NOT NULL DEFAULT '{}',  -- lower-cased staff emails
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_staff_notif_role_created
  ON public.staff_notifications (target_role, created_at DESC);

ALTER TABLE public.staff_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff read staff_notifications" ON public.staff_notifications;
CREATE POLICY "Staff read staff_notifications"
  ON public.staff_notifications FOR SELECT
  TO authenticated
  USING (public.is_staff());

DROP POLICY IF EXISTS "Staff update staff_notifications" ON public.staff_notifications;
CREATE POLICY "Staff update staff_notifications"
  ON public.staff_notifications FOR UPDATE
  TO authenticated
  USING (public.is_staff())
  WITH CHECK (public.is_staff());

-- 3. Trigger: create staff notifications from request lifecycle changes
CREATE OR REPLACE FUNCTION public.fn_requests_staff_notify()
RETURNS TRIGGER AS $$
DECLARE
  ref  TEXT := 'MI-' || EXTRACT(YEAR FROM now())::INT || '-' || LPAD(NEW.id::TEXT, 3, '0');
  cust TEXT := COALESCE(NULLIF(TRIM(NEW.customer_name), ''), 'A customer');
BEGIN
  IF TG_OP = 'INSERT' AND COALESCE(NEW.status, 'pending') = 'pending' THEN
    INSERT INTO public.staff_notifications (target_role, type, title, message, request_id, reference_no)
    VALUES ('Clerk', 'new_request', 'New Slaughter Request',
            cust || ' submitted ' || ref || ' — awaiting receiving review.',
            NEW.id, ref);
  ELSIF TG_OP = 'UPDATE'
        AND NEW.status = 'doc_verified'
        AND OLD.status IS DISTINCT FROM 'doc_verified' THEN
    INSERT INTO public.staff_notifications (target_role, type, title, message, request_id, reference_no)
    VALUES ('Inspector', 'doc_verified', 'Ready for Ante-Mortem',
            ref || ' (' || cust || ') documents verified by clerk — ready for inspection.',
            NEW.id, ref);
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

-- 4. Atomic "mark as read" helper
CREATE OR REPLACE FUNCTION public.mark_staff_notifications_read(p_ids BIGINT[], p_email TEXT)
RETURNS VOID AS $$
  UPDATE public.staff_notifications
     SET read_by = array_append(read_by, lower(p_email))
   WHERE id = ANY(p_ids)
     AND NOT (lower(p_email) = ANY(read_by));
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.mark_staff_notifications_read(BIGINT[], TEXT) TO authenticated;

-- 5. Realtime publication
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.staff_notifications;
EXCEPTION WHEN duplicate_object THEN NULL;
          WHEN undefined_object THEN NULL;
END $$;
