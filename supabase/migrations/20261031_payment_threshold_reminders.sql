-- Migration: Payment Threshold Reminders, Post-Payment Reference, & Meat Release Verification
-- Run this in Supabase SQL Editor if columns are not yet present.

-- 1. Authorized Representative & Dual-Identity Tracking on requests
ALTER TABLE requests 
ADD COLUMN IF NOT EXISTS authorized_person_name TEXT,
ADD COLUMN IF NOT EXISTS authorized_person_contact TEXT,
ADD COLUMN IF NOT EXISTS authorized_person_id_type TEXT,
ADD COLUMN IF NOT EXISTS authorized_person_id_num TEXT,
ADD COLUMN IF NOT EXISTS authorized_person_relationship TEXT,
ADD COLUMN IF NOT EXISTS claimant_type TEXT,
ADD COLUMN IF NOT EXISTS claimant_id_type TEXT,
ADD COLUMN IF NOT EXISTS claimant_id_num TEXT,
ADD COLUMN IF NOT EXISTS dispatcher_staff_id TEXT,
ADD COLUMN IF NOT EXISTS pickup_deadline TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS payment_reminder_sent BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS claiming_reminder_sent BOOLEAN DEFAULT FALSE;

-- 2. Transaction Reference & Payment Completion Details on payments
ALTER TABLE payments
ADD COLUMN IF NOT EXISTS transaction_ref TEXT,
ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

