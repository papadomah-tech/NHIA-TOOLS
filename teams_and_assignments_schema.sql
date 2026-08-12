-- ================================================================
-- NHIA M&E Tools v79 — Teams & Assignments
-- Run this in Supabase SQL Editor, in addition to the existing
-- user_profiles / visit_syncs schema.
-- ================================================================

-- Safe to re-run: define set_updated_at() here too in case this
-- file is ever run standalone.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ── 1. TEAMS ─────────────────────────────────────────────────────
-- Gives each team_id a real, human-readable name (e.g. "Team Sekondi")
-- instead of a bare UUID. user_profiles.team_id points here.
create table if not exists public.teams (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  created_at timestamptz default now()
);

alter table public.teams enable row level security;

-- Everyone can see their own team's name (needed to show it on the
-- home screen header)
create policy "Users can read own team"
  on public.teams for select
  using (id = (select team_id from public.user_profiles where id = auth.uid()));

-- Admin creates/edits teams directly in the SQL Editor (service role
-- bypasses RLS), so no insert/update policy is needed for regular users.


-- ── 2. ASSIGNMENTS ───────────────────────────────────────────────
-- Server-synced so every team member sees the same list after login,
-- regardless of which device created it. Either the Admin (direct SQL)
-- or a Team Leader (in-app "New Assignment") can create one.
create table if not exists public.assignments (
  id             text primary key,        -- matches the client-generated id (e.g. 'a_172...')
  team_id        uuid not null references public.teams(id),
  team_name      text,                     -- free-text label chosen by the creator, e.g. "Team Vincent"
  leader         text,
  members        jsonb default '[]',
  district       text,
  region         text,
  start_date     date,
  end_date       date,
  facility_count int default 0,
  visit_ids      jsonb default '[]',
  do_visit_id    text,
  status         text default 'open' check (status in ('open','closed')),
  created_by     uuid references auth.users(id),
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);

alter table public.assignments enable row level security;

-- Team members only ever see their own team's assignments
create policy "Team can read own assignments"
  on public.assignments for select
  using (team_id = (select team_id from public.user_profiles where id = auth.uid()));

-- Only Team Leaders can create assignments from inside the app
create policy "Leaders can create assignments"
  on public.assignments for insert
  with check (
    team_id = (select team_id from public.user_profiles where id = auth.uid())
    and (select role from public.user_profiles where id = auth.uid()) = 'leader'
  );

-- Team Leaders can update assignments belonging to their own team
-- (adding visits, closing the assignment, etc.)
create policy "Leaders can update own team assignments"
  on public.assignments for update
  using (team_id = (select team_id from public.user_profiles where id = auth.uid()));

alter publication supabase_realtime add table public.assignments;

create trigger assignments_updated_at
  before update on public.assignments
  for each row execute function public.set_updated_at();


-- ================================================================
-- ADMIN WORKFLOW
-- ================================================================
-- 1. Create a team:
--    insert into public.teams (name) values ('Team Sekondi');
--
-- 2. Assign users to that team (run once per user, or update existing):
--    update public.user_profiles set team_id = 'TEAM-UUID-HERE' where id = 'USER-UUID-HERE';
--
-- 3. (Optional) Pre-create a monitoring assignment for that team:
--    insert into public.assignments (id, team_id, team_name, leader, members, district, region, start_date, facility_count, status, created_by)
--    values (
--      'a_' || extract(epoch from now())::bigint,
--      'TEAM-UUID-HERE',
--      'Team Sekondi',
--      'Ama Owusu',
--      '["Ama Owusu","Kofi Mensah","Yaw Boateng"]'::jsonb,
--      'Sekondi-Takoradi',
--      'Western',
--      current_date,
--      3,
--      'open',
--      null
--    );
-- ================================================================
