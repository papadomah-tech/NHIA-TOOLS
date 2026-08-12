-- ================================================================
-- NHIA M&E Tools v79 — Additional table for visit sync
-- Run this in Supabase SQL Editor in addition to the existing schema
-- ================================================================

create table if not exists public.visit_syncs (
  visit_id    text primary key,
  team_id     uuid,
  synced_by   uuid references auth.users(id),
  setup       jsonb default '{}',
  modules     jsonb default '{}',
  scores      jsonb default '{}',
  summary     jsonb default '{}',
  device_id   text,
  synced_at   timestamptz default now(),
  updated_at  timestamptz default now()
);

alter table public.visit_syncs enable row level security;

-- Team members can read visits synced by their team
create policy "Team can read syncs"
  on public.visit_syncs for select
  using (
    team_id = (select team_id from public.user_profiles where id = auth.uid())
  );

-- Any authenticated user can insert/update their own visits
create policy "Users can upsert own visits"
  on public.visit_syncs for insert
  with check (auth.uid() is not null);

create policy "Users can update own visits"
  on public.visit_syncs for update
  using (synced_by = auth.uid());

-- Enable Realtime
alter publication supabase_realtime add table public.visit_syncs;

-- Auto-update updated_at
create trigger visit_syncs_updated_at
  before update on public.visit_syncs
  for each row execute function public.set_updated_at();
