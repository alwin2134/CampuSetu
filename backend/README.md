# Backend Database Setup (Phase 2)

This directory contains the database schema and storage setup scripts for the Smart Campus Navigation System. 
We are using **Supabase** (PostgreSQL) as our backend.

## Structure
- `supabase/migrations/20260602140600_initial_schema.sql`: Contains table definitions, relationships, indexes, and Row Level Security (RLS) policies for the navigation domain.
- `supabase/migrations/20260602140601_storage_setup.sql`: Configures the Supabase Storage bucket for uploading and serving floor map images.

## Testing Locally

If you want to test the database schema locally before deploying to the cloud, you can use the Supabase CLI.

### Prerequisites
1. Install [Docker](https://docs.docker.com/get-docker/).
2. Install [Supabase CLI](https://supabase.com/docs/guides/cli#installation).

### Steps
1. Navigate to the root directory of this project in your terminal.
2. Run `supabase init` (if not already initialized).
3. Run `supabase start`. This will download the necessary Docker images and start a local Supabase environment.
4. The local environment will automatically apply the migration files located in `supabase/migrations`.
5. Once started, you can access the local Supabase Studio (dashboard) at `http://localhost:54323` (or the URL provided in the terminal output) to explore your newly created tables, RLS policies, and storage buckets.

To stop the local instance:
```bash
supabase stop
```

To deploy to production:
```bash
supabase link --project-ref your-project-id
supabase db push
```
