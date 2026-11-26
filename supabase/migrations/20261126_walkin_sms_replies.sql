-- Migration: Two-Way Walk-In Customer SMS Replies table + Realtime
-- Date: 2026-11-26
-- Purpose: Stores incoming SMS replies from walk-in livestock dealers (via TextBee
--          MESSAGE_RECEIVED webhook or manual staff log) so Inspectors and Admins
--          can view customer responses live in Slaughter & Inspection.

CREATE TABLE IF NOT EXISTS public.walkin_sms_replies (
    id BIGSERIAL PRIMARY KEY,
    request_id BIGINT REFERENCES public.requests(id) ON DELETE CASCADE,
    sender_phone TEXT NOT NULL,
    message TEXT NOT NULL,
    parsed_action TEXT DEFAULT 'reply', -- 'confine', 'take_back', 'reply'
    source TEXT DEFAULT 'textbee_webhook', -- 'textbee_webhook', 'manual_log'
    received_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_walkin_sms_replies_request_id
    ON public.walkin_sms_replies(request_id, received_at DESC);

ALTER TABLE public.walkin_sms_replies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow staff manage walkin_sms_replies" ON public.walkin_sms_replies;
CREATE POLICY "Allow staff manage walkin_sms_replies"
ON public.walkin_sms_replies FOR ALL
TO authenticated
USING (public.is_staff())
WITH CHECK (public.is_staff());

-- Enable Supabase Realtime so Inspector & Admin consoles receive replies in <1s
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'walkin_sms_replies'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.walkin_sms_replies;
    END IF;
END $$;
