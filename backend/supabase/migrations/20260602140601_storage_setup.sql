-- Create a storage bucket for map images
insert into storage.buckets (id, name, public)
values ('floor-maps', 'floor-maps', true);


-- Public access to read map images
create policy "Public Map View"
on storage.objects for select
using ( bucket_id = 'floor-maps' );

-- Admins can insert/update maps (Using a placeholder policy for now, assuming authenticated users are admins for MVP)
create policy "Authenticated users can upload maps"
on storage.objects for insert
to authenticated
with check ( bucket_id = 'floor-maps' );

create policy "Authenticated users can update maps"
on storage.objects for update
to authenticated
using ( bucket_id = 'floor-maps' );

create policy "Authenticated users can delete maps"
on storage.objects for delete
to authenticated
using ( bucket_id = 'floor-maps' );
