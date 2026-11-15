-- Automatically enroll customers into public.regular_dealers as soon as they
-- confirm their permanent dealer role (barangay or market) in the mobile app.
-- Their Permanent Marking starts as 'PENDING' until their first request is marked.

CREATE OR REPLACE FUNCTION public.auto_enroll_dealer_on_role_confirm()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_category text;
  v_name text;
  v_next_number integer;
BEGIN
  IF COALESCE(NEW.role_confirmed, false) = true
     AND LOWER(COALESCE(NEW.dealer_category, '')) IN ('barangay', 'market') THEN

    -- Only insert if public.regular_dealers table exists
    IF to_regclass('public.regular_dealers') IS NOT NULL THEN
      v_category := LOWER(NEW.dealer_category);
      v_name := UPPER(COALESCE(NULLIF(TRIM(NEW.full_name), ''), NULLIF(TRIM(NEW.phone), ''), 'CUSTOMER'));

      IF NOT EXISTS (
        SELECT 1 FROM public.regular_dealers
        WHERE user_id = NEW.id
           OR (LOWER(TRIM(name)) = LOWER(TRIM(v_name)) AND category = v_category)
      ) THEN
        SELECT COALESCE(MAX(dealer_number), 0) + 1
          INTO v_next_number
          FROM public.regular_dealers
         WHERE category = v_category;

        INSERT INTO public.regular_dealers (
          id,
          dealer_number,
          name,
          markings,
          category,
          phone,
          user_id,
          is_active,
          created_at
        ) VALUES (
          'dlr-' || EXTRACT(EPOCH FROM NOW())::bigint::text || '-' || SUBSTRING(NEW.id::text FROM 1, 6),
          v_next_number,
          v_name,
          'PENDING',
          v_category,
          NEW.phone,
          NEW.id,
          true,
          COALESCE(NEW.created_at, NOW())
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_enroll_dealer_on_role_confirm ON public.profiles;
CREATE TRIGGER trg_auto_enroll_dealer_on_role_confirm
  AFTER INSERT OR UPDATE OF role_confirmed, dealer_category, full_name, phone
  ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_enroll_dealer_on_role_confirm();
