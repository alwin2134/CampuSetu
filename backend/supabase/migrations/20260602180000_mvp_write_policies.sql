-- MVP: allow all operations on events, buildings, and campuses for the admin map screen.
-- Ideally these should be restricted to authenticated admin users in production.

CREATE POLICY "Anyone can modify events for MVP." ON events FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Anyone can modify buildings for MVP." ON buildings FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Anyone can modify campuses for MVP." ON campuses FOR ALL USING (true) WITH CHECK (true);
