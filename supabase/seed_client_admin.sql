-- ==============================================================================
-- Tabaco City AA Slaughterhouse Management System
-- CLIENT ADMIN PROVISIONING & HANDOVER SCRIPT
-- ==============================================================================
-- INSTRUCTIONS:
-- 1. Open your Supabase Project Dashboard (https://supabase.com/dashboard)
-- 2. Navigate to "SQL Editor" on the left sidebar
-- 3. Paste and run this script to create or update the official Client Admin.
-- ==============================================================================

DO $$
DECLARE
    -- Configure your client's initial credentials here:
    target_admin_email      TEXT := 'admin@tabaco.gov.ph';              -- Client's official email
    target_admin_password   TEXT := 'TabacoSlaughter2026!';          -- Client's strong temporary password
    target_admin_full_name  TEXT := 'City Slaughterhouse Administrator';
    
    new_admin_id            UUID := gen_random_uuid();
    encrypted_pass          TEXT;
BEGIN
    -- Enable pgcrypto extension if not already present
    CREATE EXTENSION IF NOT EXISTS pgcrypto;

    -- Encrypt the password using Blowfish (Supabase Auth standard)
    encrypted_pass := crypt(target_admin_password, gen_salt('bf'));

    -- Check if the user already exists in auth.users
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE LOWER(email) = LOWER(target_admin_email)) THEN
        -- Insert new authenticated user with role: 'admin'
        INSERT INTO auth.users (
            id,
            instance_id,
            email,
            encrypted_password,
            email_confirmed_at,
            raw_app_meta_data,
            raw_user_meta_data,
            created_at,
            updated_at,
            role,
            aud,
            confirmation_token
        ) VALUES (
            new_admin_id,
            '00000000-0000-0000-0000-000000000000',
            target_admin_email,
            encrypted_pass,
            NOW(),
            '{"provider":"email","providers":["email"]}'::jsonb,
            jsonb_build_object(
                'role', 'admin',
                'full_name', target_admin_full_name
            ),
            NOW(),
            NOW(),
            'authenticated',
            'authenticated',
            ''
        );

        RAISE NOTICE 'Created new Administrator account for %', target_admin_email;
    ELSE
        -- User exists: Update their password and ensure admin role
        UPDATE auth.users
        SET 
            encrypted_password = encrypted_pass,
            email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
            raw_user_meta_data = jsonb_build_object(
                'role', 'admin',
                'full_name', target_admin_full_name
            ),
            updated_at = NOW()
        WHERE LOWER(email) = LOWER(target_admin_email);

        RAISE NOTICE 'Updated existing account % with Admin role and new password.', target_admin_email;
    END IF;

    -- Ensure profiles table has the admin role if table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'profiles') THEN
        INSERT INTO public.profiles (id, email, display_name, role)
        SELECT id, email, target_admin_full_name, 'admin'
        FROM auth.users
        WHERE LOWER(email) = LOWER(target_admin_email)
        ON CONFLICT (id) DO UPDATE
        SET role = 'admin', display_name = EXCLUDED.display_name;
    END IF;

END $$;

