-- Table: events
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    latitude FLOAT NOT NULL,
    longitude FLOAT NOT NULL,
    event_time TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Row Level Security (RLS)
ALTER TABLE events ENABLE ROW LEVEL SECURITY;

-- Create Policy for Public Read
CREATE POLICY "Public events are viewable by everyone." ON events FOR SELECT USING (true);

-- Create Policy for Public Insert (MVP Admin hack: allowing anyone to insert for now, ideally restrict to auth roles later)
CREATE POLICY "Anyone can insert events for MVP." ON events FOR INSERT WITH CHECK (true);
