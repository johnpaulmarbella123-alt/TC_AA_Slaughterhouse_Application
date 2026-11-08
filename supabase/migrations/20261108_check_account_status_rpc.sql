-- ==============================================================================
-- Real-Time Account Verification Status Check RPC
-- Target System: Tabaco City Slaughterhouse Management System (TCAASlaughter_App)
-- Date: 2026-11-08
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.check_account_status(identifier text)
RETURNS jsonb AS $$
DECLARE
    found_user record;
    clean_id text;
    intl_phone text;
    local_phone text;
BEGIN
    clean_id := LOWER(TRIM(identifier));
    
    -- Format phone variants if input looks like a phone number
    IF clean_id ~ '^[0-9+]+$' THEN
        IF clean_id LIKE '09%' THEN
            intl_phone := '+63' || SUBSTRING(clean_id FROM 2);
            local_phone := clean_id;
        ELSIF clean_id LIKE '+63%' THEN
            intl_phone := clean_id;
            local_phone := '0' || SUBSTRING(clean_id FROM 4);
        ELSE
            intl_phone := clean_id;
            local_phone := clean_id;
        END IF;
    END IF;

    -- Look up in auth.users
    SELECT id, email, phone, email_confirmed_at, phone_confirmed_at, confirmed_at
    INTO found_user
    FROM auth.users
    WHERE LOWER(email) = clean_id
       OR (phone IS NOT NULL AND (phone = clean_id OR phone = intl_phone OR phone = local_phone))
    LIMIT 1;

    IF found_user.id IS NULL THEN
        -- Also check profiles table
        SELECT id, email, phone
        INTO found_user
        FROM public.profiles
        WHERE LOWER(email) = clean_id
           OR (phone IS NOT NULL AND (phone = clean_id OR phone = intl_phone OR phone = local_phone))
        LIMIT 1;

        IF found_user.id IS NULL THEN
            RETURN jsonb_build_object(
                'exists', false,
                'is_verified', false
            );
        END IF;
    END IF;

    -- Check if email or phone is verified
    IF found_user.email_confirmed_at IS NOT NULL 
       OR found_user.phone_confirmed_at IS NOT NULL 
       OR found_user.confirmed_at IS NOT NULL THEN
        RETURN jsonb_build_object(
            'exists', true,
            'is_verified', true
        );
    ELSE
        RETURN jsonb_build_object(
            'exists', true,
            'is_verified', false
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.check_account_status(text) TO anon, authenticated;

