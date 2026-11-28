-- ==============================================================================
-- Customer FCM Device Push Tokens Table
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-28
--
-- Stores Firebase Cloud Messaging (FCM) device tokens per customer account so
-- the `send-push-notification` Supabase Edge Function can deliver real-time
-- push notifications and launcher app icon badges even when the app is closed.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.user_push_tokens (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL DEFAULT 'android',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_push_tokens_user_id
  ON public.user_push_tokens (user_id);

ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own push tokens" ON public.user_push_tokens;
CREATE POLICY "Users can view own push tokens"
  ON public.user_push_tokens
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own push tokens" ON public.user_push_tokens;
CREATE POLICY "Users can insert own push tokens"
  ON public.user_push_tokens
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own push tokens" ON public.user_push_tokens;
CREATE POLICY "Users can update own push tokens"
  ON public.user_push_tokens
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own push tokens" ON public.user_push_tokens;
CREATE POLICY "Users can delete own push tokens"
  ON public.user_push_tokens
  FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- Safely register or reassign an FCM device token to the currently signed-in user.
-- Using SECURITY DEFINER avoids RLS 42501 conflicts when a different customer
-- account previously logged in on the same physical Android/iOS device.
CREATE OR REPLACE FUNCTION public.register_user_push_token(
  p_fcm_token TEXT,
  p_platform TEXT DEFAULT 'android'
)
RETURNS VOID AS $$
DECLARE
  v_uid UUID;
  v_token TEXT;
  v_platform TEXT;
BEGIN
  v_uid := auth.uid();
  v_token := TRIM(COALESCE(p_fcm_token, ''));
  v_platform := LOWER(TRIM(COALESCE(p_platform, 'android')));
  IF v_uid IS NULL OR v_token = '' THEN
    RETURN;
  END IF;
  IF v_platform NOT IN ('android', 'ios', 'web') THEN
    v_platform := 'android';
  END IF;

  INSERT INTO public.user_push_tokens (user_id, fcm_token, platform, updated_at)
  VALUES (v_uid, v_token, v_platform, NOW())
  ON CONFLICT (fcm_token) DO UPDATE
  SET user_id = EXCLUDED.user_id,
      platform = EXCLUDED.platform,
      updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

GRANT EXECUTE ON FUNCTION public.register_user_push_token(TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
