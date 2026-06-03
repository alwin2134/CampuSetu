-- Indoor Navigation (Rooms, Floors, Altitude)

-- 1. Create the `rooms` table
DROP TABLE IF EXISTS rooms CASCADE;
CREATE TABLE IF NOT EXISTS rooms (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    building_id  UUID NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
    name         TEXT NOT NULL,
    room_type    TEXT DEFAULT 'classroom', -- e.g. classroom, auditorium, lab, office
    floor_level  INTEGER DEFAULT 0,
    latitude     DOUBLE PRECISION NOT NULL,
    longitude    DOUBLE PRECISION NOT NULL,
    altitude     DOUBLE PRECISION,
    created_at   TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Add floor_level and altitude to `campus_nodes`
ALTER TABLE campus_nodes ADD COLUMN IF NOT EXISTS floor_level INTEGER DEFAULT 0;
ALTER TABLE campus_nodes ADD COLUMN IF NOT EXISTS altitude DOUBLE PRECISION;

-- 3. Row Level Security for rooms
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public read rooms"  ON rooms FOR SELECT USING (true);
CREATE POLICY "public write rooms" ON rooms FOR ALL USING (true) WITH CHECK (true);
