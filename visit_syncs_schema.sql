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

-- ================================================================
-- v79.1 — Atomic merge RPC for concurrent multi-officer editing
-- ================================================================
-- Problem this solves: a plain upsert() replaces the whole `modules`
-- JSONB column, so if two officers on different modules sync around
-- the same moment, whichever upload lands last silently wipes out
-- the other officer's work. This function merges at the database
-- level using jsonb `||`, keyed one module at a time, so each
-- officer's upload only ever touches the module(s) they authored —
-- other modules already on the server are preserved untouched.
create or replace function public.merge_visit_modules(
  p_visit_id    text,
  p_team_id     uuid,
  p_synced_by   uuid,
  p_setup       jsonb,
  p_new_modules jsonb,   -- only the module(s) this device actually edited
  p_scores      jsonb,   -- only the score(s) for those same module(s)
  p_summary     jsonb,
  p_device_id   text
) returns void
language plpgsql
security definer
as $$
begin
  insert into public.visit_syncs (visit_id, team_id, synced_by, setup, modules, scores, summary, device_id, synced_at)
  values (p_visit_id, p_team_id, p_synced_by, coalesce(p_setup,'{}'::jsonb), coalesce(p_new_modules,'{}'::jsonb), coalesce(p_scores,'{}'::jsonb), coalesce(p_summary,'{}'::jsonb), p_device_id, now())
  on conflict (visit_id) do update
  set modules   = coalesce(visit_syncs.modules, '{}'::jsonb) || coalesce(excluded.modules, '{}'::jsonb),
      scores    = coalesce(visit_syncs.scores,  '{}'::jsonb) || coalesce(excluded.scores,  '{}'::jsonb),
      setup     = coalesce(visit_syncs.setup,   '{}'::jsonb) || coalesce(excluded.setup,   '{}'::jsonb),
      summary   = excluded.summary,
      synced_by = excluded.synced_by,
      device_id = excluded.device_id,
      synced_at = now();
end;
$$;

grant execute on function public.merge_visit_modules to authenticated;
