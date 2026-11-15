-- Clean up any existing duplicate staff_notifications rows and replace the partial
-- unique index with a standard UNIQUE constraint so PostgREST ON CONFLICT works.

DELETE FROM public.staff_notifications a
USING public.staff_notifications b
WHERE a.id > b.id
  AND a.request_id IS NOT NULL
  AND a.request_id = b.request_id
  AND a.type = b.type
  AND a.target_role = b.target_role;

DROP INDEX IF EXISTS public.idx_staff_notif_dedup_key;

ALTER TABLE public.staff_notifications
  DROP CONSTRAINT IF EXISTS uq_staff_notif_dedup_key;

ALTER TABLE public.staff_notifications
  ADD CONSTRAINT uq_staff_notif_dedup_key UNIQUE (dedup_key);
