-- Automatically enroll customers into public.regular_dealers as soon as they
-- confirm their permanent dealer role (barangay or market) in the mobile app.
-- Their Permanent Marking starts as 'PENDING' (displayed as '—') until their first request is marked.

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
      v_name := UPPER(COALESCE(NULLIF(TRIM(NEW.display_name), ''), NULLIF(TRIM(NEW.phone), ''), 'CUSTOMER'));

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
          gen_random_uuid(),
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
  AFTER INSERT OR UPDATE
  ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_enroll_dealer_on_role_confirm();

-- Idempotent backfill for any already role-confirmed customers not yet in regular_dealers
DO $$
BEGIN
  IF to_regclass('public.regular_dealers') IS NOT NULL THEN
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
    )
    SELECT
      gen_random_uuid(),
      COALESCE((SELECT MAX(dealer_number) FROM public.regular_dealers rd WHERE rd.category = LOWER(p.dealer_category)), 0)
        + ROW_NUMBER() OVER (PARTITION BY LOWER(p.dealer_category) ORDER BY p.created_at, p.id),
      UPPER(COALESCE(NULLIF(TRIM(p.display_name), ''), NULLIF(TRIM(p.phone), ''), 'CUSTOMER')),
      'PENDING',
      LOWER(p.dealer_category),
      p.phone,
      p.id,
      true,
      COALESCE(p.created_at, NOW())
    FROM public.profiles p
    WHERE COALESCE(p.role_confirmed, false) = true
      AND LOWER(COALESCE(p.dealer_category, '')) IN ('barangay', 'market')
      AND NOT EXISTS (
        SELECT 1 FROM public.regular_dealers rd
        WHERE rd.user_id = p.id
           OR (LOWER(TRIM(rd.name)) = LOWER(TRIM(COALESCE(NULLIF(TRIM(p.display_name), ''), NULLIF(TRIM(p.phone), ''), 'CUSTOMER')))
               AND rd.category = LOWER(p.dealer_category))
      );
  END IF;
END $$;
