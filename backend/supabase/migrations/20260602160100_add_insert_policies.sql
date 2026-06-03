-- Migration: Create events table + all missing columns + RLS policies for writes
-- ⚠️  Run this ENTIRE script in Supabase SQL Editor → New Query → Run

-- ── 1. Create events table (if it doesn't exist) ──────────────────────────
CREATE TABLE IF NOT EXISTS events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    description TEXT,
    latitude    DOUBLE PRECISION NOT NULL,
    longitude   DOUBLE PRECISION NOT NULL,
    event_time  TIMESTAMP WITH TIME ZONE,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ── 2. Add lat/lng columns to campuses & buildings (safe, idempotent) ──────
ALTER TABLE campuses
  ADD COLUMN IF NOT EXISTS latitude  DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

ALTER TABLE buildings
  ADD COLUMN IF NOT EXISTS latitude  DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- ── 3. Enable RLS on events ────────────────────────────────────────────────
ALTER TABLE events ENABLE ROW LEVEL SECURITY;

-- ── 4. Read policies (public) ──────────────────────────────────────────────
DROP POLICY IF EXISTS "Public events are viewable by everyone." ON events;
CREATE POLICY "Public events are viewable by everyone." ON events
  FOR SELECT USING (true);

-- ── 5. Write policies (open for now — lock down with auth later) ───────────
-- Events
DROP POLICY IF EXISTS "Allow insert on events" ON events;
CREATE POLICY "Allow insert on events" ON events
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Allow update on events" ON events;
CREATE POLICY "Allow update on events" ON events
  FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Allow delete on events" ON events;
CREATE POLICY "Allow delete on events" ON events
  FOR DELETE USING (true);

-- Campuses
DROP POLICY IF EXISTS "Allow insert on campuses" ON campuses;
CREATE POLICY "Allow insert on campuses" ON campuses
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Allow update on campuses" ON campuses;
CREATE POLICY "Allow update on campuses" ON campuses
  FOR UPDATE USING (true);

-- Buildings
DROP POLICY IF EXISTS "Allow insert on buildings" ON buildings;
CREATE POLICY "Allow insert on buildings" ON buildings
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Allow update on buildings" ON buildings;
CREATE POLICY "Allow update on buildings" ON buildings
  FOR UPDATE USING (true);
