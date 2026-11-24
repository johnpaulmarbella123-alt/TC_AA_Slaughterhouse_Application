-- ==============================================================================
-- FINAL DEFENSE DATABASE RESET — TABACO CITY "AA" SLAUGHTERHOUSE SYSTEM
-- Date: 2026-11-22
--
-- CLEARS ALL operational & test data + resets ID sequences to 1
-- (first demo request = MI-2026-001, first Official Receipt = OR-2026-000001).
--
-- STRICTLY PRESERVES:
-- 1. Admin:     tcaaslaughterhouse@gmail.com (role = 'admin')
-- 2. Clerk:     jonathanbino63@gmail.com     (role = 'clerk')
-- 3. Inspector: andriebarasona46@gmail.com   (role = 'inspector')
-- 4. Core system_settings (fees, schedule, staff_accounts, appearance, nmic_settings)
-- ==============================================================================

BEGIN;

-- 1. Clear operational tables & restart identity sequences to 1
TRUNCATE TABLE
    public.payments,
    public.slaughter_inspection,
    public.requests,
    public.staff_notifications
RESTART IDENTITY CASCADE;

-- 2. Clear remaining operational/test tables
DELETE FROM public.notifications;
DELETE FROM public.reports;
DELETE FROM public.reviews;
DELETE FROM public.audit_logs;
DELETE FROM public.nmic_transmissions;
DELETE FROM public.regular_dealers;

-- 3. Reset temporary / cached operational keys in system_settings
UPDATE public.system_settings
SET value = '[]'::jsonb, updated_at = NOW()
WHERE key IN ('regular_dealers', 'ante_mortem_alerts', 'walk_in_directory');

UPDATE public.system_settings
SET value = '{}'::jsonb, updated_at = NOW()
WHERE key IN ('pickup_penalty_tracking', 'walk_in_claims', 'authorized_representatives');

-- 4. Delete all test customer profiles (keep only the 3 official staff)
DELETE FROM public.profiles
WHERE id NOT IN (
    SELECT id FROM auth.users
    WHERE LOWER(COALESCE(email, '')) IN (
        'tcaaslaughterhouse@gmail.com',
        'jonathanbino63@gmail.com',
        'andriebarasona46@gmail.com'
    )
);

-- 5. Delete auth identities, sessions, and users for all test customer accounts
DELETE FROM auth.identities
WHERE user_id IN (
    SELECT id FROM auth.users
    WHERE LOWER(COALESCE(email, '')) NOT IN (
        'tcaaslaughterhouse@gmail.com',
        'jonathanbino63@gmail.com',
        'andriebarasona46@gmail.com'
    )
);

DELETE FROM auth.sessions
WHERE user_id IN (
    SELECT id FROM auth.users
    WHERE LOWER(COALESCE(email, '')) NOT IN (
        'tcaaslaughterhouse@gmail.com',
        'jonathanbino63@gmail.com',
        'andriebarasona46@gmail.com'
    )
);

DELETE FROM auth.users
WHERE LOWER(COALESCE(email, '')) NOT IN (
    'tcaaslaughterhouse@gmail.com',
    'jonathanbino63@gmail.com',
    'andriebarasona46@gmail.com'
);

-- 6. Guarantee all 3 official staff profiles exist with exact RLS roles
INSERT INTO public.profiles (id, email, display_name, role)
SELECT
    u.id,
    u.email,
    CASE LOWER(COALESCE(u.email, ''))
        WHEN 'tcaaslaughterhouse@gmail.com' THEN 'Abattoir Administrator'
        WHEN 'jonathanbino63@gmail.com'     THEN 'Receiving Clerk'
        WHEN 'andriebarasona46@gmail.com'   THEN 'Meat Inspector'
        ELSE u.email
    END,
    CASE LOWER(COALESCE(u.email, ''))
        WHEN 'tcaaslaughterhouse@gmail.com' THEN 'admin'
        WHEN 'jonathanbino63@gmail.com'     THEN 'clerk'
        WHEN 'andriebarasona46@gmail.com'   THEN 'inspector'
        ELSE 'customer'
    END
FROM auth.users u
WHERE LOWER(COALESCE(u.email, '')) IN (
    'tcaaslaughterhouse@gmail.com',
    'jonathanbino63@gmail.com',
    'andriebarasona46@gmail.com'
)
ON CONFLICT (id) DO UPDATE
SET
    email = EXCLUDED.email,
    role  = EXCLUDED.role;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- 7. Verification Summary (confirm 0 operational rows + exact 3 staff profiles)
SELECT
    (SELECT COUNT(*) FROM public.requests)            AS requests_cnt,
    (SELECT COUNT(*) FROM public.payments)            AS payments_cnt,
    (SELECT COUNT(*) FROM public.slaughter_inspection) AS inspections_cnt,
    (SELECT COUNT(*) FROM public.reports)             AS reports_cnt,
    (SELECT COUNT(*) FROM public.reviews)             AS reviews_cnt,
    (SELECT COUNT(*) FROM public.audit_logs)          AS audit_logs_cnt,
    (SELECT COUNT(*) FROM public.regular_dealers)     AS dealers_cnt,
    (SELECT COUNT(*) FROM public.profiles)            AS profiles_cnt,
    (SELECT COUNT(*) FROM auth.users)                 AS auth_users_cnt;
