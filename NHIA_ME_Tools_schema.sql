-- ================================================================
-- NHIA M&E Tools — Supabase SQL Schema
-- Run this in your Supabase project: SQL Editor → New Query → Run
-- ================================================================

-- ── 1. USER PROFILES ────────────────────────────────────────────
-- Extends Supabase Auth users with role and team assignment
create table if not exists public.user_profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role        text not null check (role in ('leader', 'member')),
  team_id     uuid,                        -- links members to a team leader's team
  created_at  timestamptz default now()
);

-- Row Level Security
alter table public.user_profiles enable row level security;

-- Users can read their own profile
create policy "Own profile readable"
  on public.user_profiles for select
  using (auth.uid() = id);

-- IT admin (service role) manages all profiles
-- (No insert/update policy needed for anon/authenticated — IT uses Supabase dashboard)


-- ── 2. ASSIGNMENTS ───────────────────────────────────────────────
create table if not exists public.assignments (
  id          uuid primary key default gen_random_uuid(),
  period      text not null,               -- e.g. "Q2 2026 – June"
  district    text not null,
  members     text,                        -- comma-separated names
  status      text not null default 'active'
                check (status in ('active', 'closed', 'reported')),
  team_id     uuid not null,
  created_by  uuid references auth.users(id),
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

alter table public.assignments enable row level security;

-- Team Leaders see only their team's assignments
create policy "Leaders see own team assignments"
  on public.assignments for select
  using (
    team_id = (select team_id from public.user_profiles where id = auth.uid())
  );

-- Team Members see assignments for their team
create policy "Members see own team assignments"
  on public.assignments for select
  using (
    team_id = (select team_id from public.user_profiles where id = auth.uid())
  );

-- Only Team Leaders can insert/update assignments
create policy "Leaders can create assignments"
  on public.assignments for insert
  with check (
    (select role from public.user_profiles where id = auth.uid()) = 'leader'
  );

create policy "Leaders can update assignments"
  on public.assignments for update
  using (
    (select role from public.user_profiles where id = auth.uid()) = 'leader'
    and team_id = (select team_id from public.user_profiles where id = auth.uid())
  );

-- Auto-update updated_at
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger assignments_updated_at
  before update on public.assignments
  for each row execute function public.set_updated_at();


-- ── 3. VISITS ────────────────────────────────────────────────────
create table if not exists public.visits (
  id              uuid primary key default gen_random_uuid(),
  assignment_id   uuid not null references public.assignments(id) on delete cascade,
  facility_name   text not null,
  visit_type      text not null check (visit_type in ('facility', 'district')),
  visit_date      date,
  notes           text,
  status          text not null default 'open'
                    check (status in ('open', 'closed')),
  created_by      uuid references auth.users(id),
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

alter table public.visits enable row level security;

-- All team members can see visits belonging to their team's assignments
create policy "Team can see visits"
  on public.visits for select
  using (
    assignment_id in (
      select id from public.assignments
      where team_id = (select team_id from public.user_profiles where id = auth.uid())
    )
  );

-- Only Team Leaders can insert visits
create policy "Leaders can add visits"
  on public.visits for insert
  with check (
    (select role from public.user_profiles where id = auth.uid()) = 'leader'
  );

-- Only Team Leaders can close visits
create policy "Leaders can update visits"
  on public.visits for update
  using (
    (select role from public.user_profiles where id = auth.uid()) = 'leader'
  );

create trigger visits_updated_at
  before update on public.visits
  for each row execute function public.set_updated_at();


-- ── 4. MODULE SCORES ─────────────────────────────────────────────
create table if not exists public.module_scores (
  id          uuid primary key default gen_random_uuid(),
  visit_id    uuid not null references public.visits(id) on delete cascade,
  module_id   text not null,               -- M1 … M6
  data        jsonb not null default '{}', -- indicator responses
  scored_by   uuid references auth.users(id),
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique (visit_id, module_id)             -- upsert key
);

alter table public.module_scores enable row level security;

-- All team members can read scores for their team's visits
create policy "Team can read scores"
  on public.module_scores for select
  using (
    visit_id in (
      select v.id from public.visits v
      join public.assignments a on a.id = v.assignment_id
      where a.team_id = (select team_id from public.user_profiles where id = auth.uid())
    )
  );

-- Any authenticated team member can insert/update scores
create policy "Members can save scores"
  on public.module_scores for insert
  with check (auth.uid() is not null);

create policy "Members can update scores"
  on public.module_scores for update
  using (auth.uid() is not null);

create trigger module_scores_updated_at
  before update on public.module_scores
  for each row execute function public.set_updated_at();


-- ── 5. REALTIME ──────────────────────────────────────────────────
-- Enable Realtime for live cross-device sync
alter publication supabase_realtime add table public.assignments;
alter publication supabase_realtime add table public.visits;
alter publication supabase_realtime add table public.module_scores;


-- ================================================================
-- SAMPLE DATA — optional, delete before production
-- ================================================================

-- Step 1: Create a user in Supabase Auth dashboard first,
--         then copy their UUID here.

-- insert into public.user_profiles (id, display_name, role, team_id)
-- values
--   ('TEAM-LEADER-UUID-HERE', 'Ama Owusu',   'leader', 'a1b2c3d4-0000-0000-0000-000000000001'),
--   ('TEAM-MEMBER-UUID-HERE', 'Kofi Mensah', 'member', 'a1b2c3d4-0000-0000-0000-000000000001');

-- ================================================================
-- DONE. Copy the Supabase URL and anon key from:
--   Project Settings → API
-- and paste them into index.html at the top of the <script> block.
-- ================================================================
