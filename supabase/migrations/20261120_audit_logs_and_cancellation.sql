-- ==============================================================================
-- Audit Trail Logs & Customer Self-Cancellation Migration
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-20
--
-- Creates:
-- 1. public.audit_logs (immutable staff activity trail; staff INSERT, admin SELECT)
-- 2. cancellation_reason & cancelled_at columns on public.requests
-- 3. Customer self-cancellation RLS policy for pending / pending_intake / approved
-- ==============================================================================

-- 1. Ensure helper functions exist safely
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = (select auth.uid())
          AND LOWER(COALESCE(role, '')) = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = (select auth.uid())
          AND LOWER(COALESCE(role, '')) IN ('admin', 'inspector', 'cashier', 'clerk')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public;

-- 2. Immutable Audit Trail Table
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    actor_id UUID NULL,
    actor_email TEXT NOT NULL DEFAULT '',
    actor_name TEXT NOT NULL DEFAULT 'System',
    actor_role TEXT NOT NULL DEFAULT 'Staff',
    action TEXT NOT NULL,
    module TEXT NOT NULL,
    target_id TEXT NULL,
    target_ref TEXT NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_module ON public.audit_logs (module);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs (action);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow staff insert audit_logs" ON public.audit_logs;
DROP POLICY IF EXISTS "Allow admin select audit_logs" ON public.audit_logs;

-- Staff (Admin, Clerk, Inspector, Cashier) can append audit records
CREATE POLICY "Allow staff insert audit_logs"
ON public.audit_logs FOR INSERT
TO authenticated
WITH CHECK (public.is_staff());

-- Only Administrators can view the audit trail (no UPDATE or DELETE policies -> immutable)
CREATE POLICY "Allow admin select audit_logs"
ON public.audit_logs FOR SELECT
TO authenticated
USING (public.is_admin());

-- 3. Customer Self-Cancellation Columns on public.requests
ALTER TABLE public.requests
    ADD COLUMN IF NOT EXISTS cancellation_reason TEXT,
    ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- Allow authenticated customers to cancel their own pending or approved requests
DROP POLICY IF EXISTS "Allow customers cancel own pending or approved requests" ON public.requests;
CREATE POLICY "Allow customers cancel own pending or approved requests"
ON public.requests FOR UPDATE
TO authenticated
USING (
    user_id = (select auth.uid())
    AND LOWER(COALESCE(status, '')) IN ('pending', 'pending_intake', 'approved')
)
WITH CHECK (
    user_id = (select auth.uid())
    AND LOWER(COALESCE(status, '')) = 'cancelled'
);
