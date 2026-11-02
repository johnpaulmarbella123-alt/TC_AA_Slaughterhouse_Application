-- Migration: Regular Customers & Dealers Registry, Marking Lock, and NMIC Reporting Configuration
-- Date: 2026-11-01

-- 1. Regular Dealers & Customers Registry
CREATE TABLE IF NOT EXISTS regular_dealers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_number INT NOT NULL,
    name TEXT NOT NULL,
    markings TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('market', 'barangay')),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    phone TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(category, dealer_number)
);

CREATE INDEX IF NOT EXISTS idx_regular_dealers_category ON regular_dealers(category);
CREATE INDEX IF NOT EXISTS idx_regular_dealers_markings ON regular_dealers(markings);

-- 2. Permanent assigned marking on profiles / customers
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS assigned_marking TEXT,
ADD COLUMN IF NOT EXISTS marking_locked BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS dealer_category TEXT DEFAULT 'barangay';

-- 3. Marking tag column on requests (if not present)
ALTER TABLE requests
ADD COLUMN IF NOT EXISTS customer_marking TEXT,
ADD COLUMN IF NOT EXISTS marking_locked BOOLEAN DEFAULT TRUE;

-- 4. NMIC Transmissions Log
CREATE TABLE IF NOT EXISTS nmic_transmissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_type TEXT NOT NULL, -- 'daily', 'monthly_log', 'nmis_weekly', 'nmis_posm_f034'
    period_label TEXT NOT NULL,
    recipient_email TEXT NOT NULL,
    transmittal_subject TEXT NOT NULL,
    transmittal_body TEXT,
    sent_by TEXT,
    status TEXT DEFAULT 'sent', -- 'sent', 'failed'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE regular_dealers ENABLE ROW LEVEL SECURITY;
ALTER TABLE nmic_transmissions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Allow authenticated read regular_dealers" ON regular_dealers FOR SELECT TO authenticated USING (true);
    CREATE POLICY "Allow authenticated insert/update regular_dealers" ON regular_dealers FOR ALL TO authenticated USING (true);
    CREATE POLICY "Allow public read regular_dealers" ON regular_dealers FOR SELECT TO anon USING (true);
    CREATE POLICY "Allow authenticated read nmic_transmissions" ON nmic_transmissions FOR SELECT TO authenticated USING (true);
    CREATE POLICY "Allow authenticated insert nmic_transmissions" ON nmic_transmissions FOR INSERT TO authenticated WITH CHECK (true);
EXCEPTION WHEN others THEN NULL;
END $$;

