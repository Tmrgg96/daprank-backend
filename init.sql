-- DaPrank Backend Schema
-- Migrated from Supabase

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_credits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE,
    credits INTEGER DEFAULT 1,
    subscription_status TEXT DEFAULT 'inactive',
    subscription_type TEXT,
    subscription_expires_at TIMESTAMP,
    last_credit_reset TIMESTAMP DEFAULT now(),
    free_generations_used INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now(),
    CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS prank_templates (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    image_name TEXT NOT NULL,
    prompt TEXT,
    is_active BOOLEAN DEFAULT true,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_prank_templates_active_sort
    ON prank_templates (is_active, sort_order);

CREATE INDEX IF NOT EXISTS idx_user_credits_expires_active
    ON user_credits (subscription_expires_at)
    WHERE subscription_status = 'active' AND subscription_expires_at IS NOT NULL;

-- Trigger: auto-update updated_at
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_credits_updated_at ON user_credits;
CREATE TRIGGER trg_user_credits_updated_at
    BEFORE UPDATE ON user_credits
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Function: ensure user_credits row exists
CREATE OR REPLACE FUNCTION ensure_user_credits(p_user_id UUID)
RETURNS user_credits LANGUAGE plpgsql AS $$
DECLARE
  row user_credits;
BEGIN
  SELECT * INTO row FROM user_credits WHERE user_id = p_user_id;
  IF row IS NULL THEN
    INSERT INTO user_credits(user_id) VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;
    SELECT * INTO row FROM user_credits WHERE user_id = p_user_id;
  END IF;
  RETURN row;
END;
$$;

-- Function: can_generate
CREATE OR REPLACE FUNCTION can_generate(p_user_id UUID)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  row user_credits;
  now_ts TIMESTAMPTZ := now();
  sub_active BOOLEAN;
  credits_left INTEGER;
  reason_text TEXT := NULL;
  allowed BOOLEAN := FALSE;
  watermark BOOLEAN := TRUE;
BEGIN
  row := ensure_user_credits(p_user_id);

  IF row.subscription_expires_at IS NOT NULL AND row.subscription_expires_at <= now_ts THEN
    UPDATE user_credits SET subscription_status = 'inactive', credits = 0 WHERE id = row.id;
    row.subscription_status := 'inactive';
    row.credits := 0;
  END IF;

  sub_active := (row.subscription_status = 'active');
  credits_left := COALESCE(row.credits, 0);

  IF credits_left > 0 THEN
    allowed := TRUE;
  ELSE
    allowed := FALSE;
    reason_text := 'no_credits';
  END IF;

  watermark := FALSE;

  RETURN jsonb_build_object(
    'allowed', allowed,
    'watermark', watermark,
    'reason', reason_text,
    'free_left', GREATEST(0, 1 - row.free_generations_used),
    'credits', credits_left,
    'subscription_active', sub_active
  );
END;
$$;

-- Function: consume_generation
CREATE OR REPLACE FUNCTION consume_generation(p_user_id UUID)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  row user_credits;
  check_json JSONB;
  allowed BOOLEAN;
  is_free_generation BOOLEAN;
  sub_active BOOLEAN;
BEGIN
  check_json := can_generate(p_user_id);
  allowed := (check_json->>'allowed')::BOOLEAN;
  IF NOT allowed THEN RETURN check_json; END IF;

  row := ensure_user_credits(p_user_id);
  is_free_generation := (row.subscription_status != 'active' AND row.free_generations_used = 0);

  IF row.credits > 0 THEN
    UPDATE user_credits SET
      credits = credits - 1,
      free_generations_used = CASE WHEN is_free_generation THEN free_generations_used + 1 ELSE free_generations_used END
    WHERE id = row.id;
  END IF;

  sub_active := (row.subscription_status = 'active');
  RETURN jsonb_set(check_json, '{credits}', to_jsonb(GREATEST(0, row.credits - 1)))
    || jsonb_build_object('watermark', NOT sub_active);
END;
$$;

-- Function: apply_subscription_change
CREATE OR REPLACE FUNCTION apply_subscription_change(
  p_user_id UUID, p_status TEXT, p_type TEXT, p_expires_at TIMESTAMPTZ
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  pkg_credits INTEGER := 0;
BEGIN
  IF p_type = 'monthly' THEN pkg_credits := 100;
  ELSIF p_type = 'yearly' THEN pkg_credits := 1200; END IF;

  INSERT INTO user_credits(user_id, subscription_status, subscription_type,
    subscription_expires_at, credits, last_credit_reset, free_generations_used)
  VALUES (p_user_id, p_status, p_type, p_expires_at,
    CASE WHEN p_status = 'active' THEN pkg_credits ELSE 0 END, now(), 1)
  ON CONFLICT (user_id) DO UPDATE SET
    subscription_status = EXCLUDED.subscription_status,
    subscription_type = EXCLUDED.subscription_type,
    subscription_expires_at = EXCLUDED.subscription_expires_at,
    credits = CASE WHEN EXCLUDED.subscription_status = 'active' THEN pkg_credits ELSE 0 END,
    last_credit_reset = EXCLUDED.last_credit_reset,
    updated_at = now();
END;
$$;

-- Function: reset_expired_and_refresh_active (daily cron)
CREATE OR REPLACE FUNCTION reset_expired_and_refresh_active()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE user_credits SET subscription_status = 'inactive', credits = 0
  WHERE subscription_status = 'active'
    AND subscription_expires_at IS NOT NULL
    AND subscription_expires_at <= now();
END;
$$;
