-- Native UUID support is used (gen_random_uuid())

-- Table: campuses
CREATE TABLE campuses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Table: buildings
CREATE TABLE buildings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campus_id UUID NOT NULL REFERENCES campuses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Table: floors
CREATE TABLE floors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    building_id UUID NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
    floor_number INTEGER NOT NULL,
    map_image_url TEXT,
    scale_factor FLOAT DEFAULT 1.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Table: nodes (for navigation graph)
CREATE TABLE nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    floor_id UUID NOT NULL REFERENCES floors(id) ON DELETE CASCADE,
    x_coordinate FLOAT NOT NULL,
    y_coordinate FLOAT NOT NULL,
    node_type TEXT NOT NULL, -- e.g., 'corridor', 'stairs', 'elevator', 'room_entry'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Table: edges (for navigation graph)
CREATE TABLE edges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    target_node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    distance FLOAT NOT NULL,
    is_accessible BOOLEAN DEFAULT true, -- accessible for wheelchairs etc.
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Table: rooms
CREATE TABLE rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    floor_id UUID NOT NULL REFERENCES floors(id) ON DELETE CASCADE,
    node_id UUID REFERENCES nodes(id) ON DELETE SET NULL, -- Closest entry node
    room_name TEXT NOT NULL,
    room_type TEXT, -- e.g., 'classroom', 'lab', 'office', 'admin'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Table: facilities
CREATE TABLE facilities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    floor_id UUID NOT NULL REFERENCES floors(id) ON DELETE CASCADE,
    node_id UUID REFERENCES nodes(id) ON DELETE SET NULL, -- Closest entry node
    name TEXT NOT NULL,
    type TEXT NOT NULL, -- e.g., 'washroom', 'drinking_water', 'vending_machine'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Indexes for performance
CREATE INDEX idx_buildings_campus_id ON buildings(campus_id);
CREATE INDEX idx_floors_building_id ON floors(building_id);
CREATE INDEX idx_nodes_floor_id ON nodes(floor_id);
CREATE INDEX idx_edges_source_node_id ON edges(source_node_id);
CREATE INDEX idx_edges_target_node_id ON edges(target_node_id);
CREATE INDEX idx_rooms_floor_id ON rooms(floor_id);
CREATE INDEX idx_facilities_floor_id ON facilities(floor_id);

-- Row Level Security (RLS)
-- By default, public read access is allowed since this is a public navigation app.
-- Write operations will require admin privileges (to be defined later via Auth).

ALTER TABLE campuses ENABLE ROW LEVEL SECURITY;
ALTER TABLE buildings ENABLE ROW LEVEL SECURITY;
ALTER TABLE floors ENABLE ROW LEVEL SECURITY;
ALTER TABLE nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE edges ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE facilities ENABLE ROW LEVEL SECURITY;

-- Create Policies for Public Read
CREATE POLICY "Public profiles are viewable by everyone." ON campuses FOR SELECT USING (true);
CREATE POLICY "Public buildings are viewable by everyone." ON buildings FOR SELECT USING (true);
CREATE POLICY "Public floors are viewable by everyone." ON floors FOR SELECT USING (true);
CREATE POLICY "Public nodes are viewable by everyone." ON nodes FOR SELECT USING (true);
CREATE POLICY "Public edges are viewable by everyone." ON edges FOR SELECT USING (true);
CREATE POLICY "Public rooms are viewable by everyone." ON rooms FOR SELECT USING (true);
CREATE POLICY "Public facilities are viewable by everyone." ON facilities FOR SELECT USING (true);
