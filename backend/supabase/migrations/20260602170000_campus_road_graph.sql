-- Campus road graph: outdoor nodes (waypoints) and edges (road segments)

CREATE TABLE IF NOT EXISTS campus_nodes (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campus_id    UUID REFERENCES campuses(id) ON DELETE SET NULL,
    latitude     DOUBLE PRECISION NOT NULL,
    longitude    DOUBLE PRECISION NOT NULL,
    node_type    TEXT DEFAULT 'waypoint',
    name         TEXT,
    created_at   TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS campus_edges (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_node_id   UUID NOT NULL REFERENCES campus_nodes(id) ON DELETE CASCADE,
    target_node_id   UUID NOT NULL REFERENCES campus_nodes(id) ON DELETE CASCADE,
    distance_metres  DOUBLE PRECISION,
    is_accessible    BOOLEAN DEFAULT true,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Row level security
ALTER TABLE campus_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE campus_edges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public read nodes"  ON campus_nodes FOR SELECT USING (true);
CREATE POLICY "public write nodes" ON campus_nodes FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "public read edges"  ON campus_edges FOR SELECT USING (true);
CREATE POLICY "public write edges" ON campus_edges FOR ALL USING (true) WITH CHECK (true);
