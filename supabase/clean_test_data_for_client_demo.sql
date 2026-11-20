-- ==============================================================================
-- CLEAN TEST DATA FOR CLIENT DEMO - EXACT 3 ADMIN/STAFF USERS ONLY
-- Target System: Tabaco City "AA" Slaughterhouse Management System
-- Date: 2026-11-18
--
-- EXACT THREE USERS PRESERVED:
-- 1. Admin:     tcaaslaughterhouse@gmail.com
-- 2. Clerk:     jonathanbino63@gmail.com
-- 3. Inspector: andriebarasona46@gmail.com
--
-- EVERYTHING ELSE (test customers, old dummy accounts, payments, requests,
-- notifications, alerts) WILL BE REMOVED.
-- Official Regular Dealers Directory and System Settings are PRESERVED.
-- ==============================================================================

BEGIN;

-- 1. Safely unlink test users from regular_dealers so the official directory is preserved
UPDATE public.regular_dealers
SET user_id = NULL
WHERE user_id IS NOT NULL
  AND user_id NOT IN (
    SELECT id FROM auth.users
    WHERE LOWER(COALESCE(email, '')) IN (
        'tcaaslaughterhouse@gmail.com',
        'jonathanbino63@gmail.com',
        'andriebarasona46@gmail.com'
    )
  );

-- 2. Clear payments first (foreign key dependency to requests)
DELETE FROM public.payments;

-- 3. Clear all slaughter requests
DELETE FROM public.requests;

-- 4. Clear all customer notifications
DELETE FROM public.notifications;

-- 5. Clear all staff notifications (resets Admin Panel bell badge to 0)
DELETE FROM public.staff_notifications;

-- 6. Clear NMIC transmittal logs
DELETE FROM public.nmic_transmissions;

-- 7. Reset operational temporary queues in system_settings
UPDATE public.system_settings
SET value = '[]'::jsonb, updated_at = NOW()
WHERE key IN ('ante_mortem_alerts', 'walk_in_directory');

UPDATE public.system_settings
SET value = '{}'::jsonb, updated_at = NOW()
WHERE key IN ('pickup_penalty_tracking', 'walk_in_claims', 'authorized_representatives');

-- 8. Delete all profiles EXCEPT the 3 official staff (Admin, Clerk, Inspector)
DELETE FROM public.profiles
WHERE LOWER(COALESCE(email, '')) NOT IN (
    'tcaaslaughterhouse@gmail.com',
    'jonathanbino63@gmail.com',
    'andriebarasona46@gmail.com'
);

-- Ensure the 3 official accounts have their exact correct roles
UPDATE public.profiles
SET role = 'admin'
WHERE LOWER(COALESCE(email, '')) = 'tcaaslaughterhouse@gmail.com';

UPDATE public.profiles
SET role = 'clerk'
WHERE LOWER(COALESCE(email, '')) = 'jonathanbino63@gmail.com';

UPDATE public.profiles
SET role = 'inspector'
WHERE LOWER(COALESCE(email, '')) = 'andriebarasona46@gmail.com';

-- 9. Delete auth sessions, identities, and factors for all other users
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

-- 10. Delete all other users from auth.users EXCEPT the exact three
DELETE FROM auth.users
WHERE LOWER(COALESCE(email, '')) NOT IN (
    'tcaaslaughterhouse@gmail.com',
    'jonathanbino63@gmail.com',
    'andriebarasona46@gmail.com'
);

COMMIT;
