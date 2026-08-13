-- ================================================================
-- NHIA M&E Tools v79 — Digital Signatures
-- Run this after admin_role_schema.sql
-- ================================================================

alter table public.user_profiles add column if not exists signature_data text;

-- Lets a user save/replace ONLY their own signature — deliberately a
-- narrow RPC rather than a general "update own profile" RLS policy,
-- so this can never be used to change one's own role or team_id.
create or replace function public.save_my_signature(p_signature_data text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  update public.user_profiles
  set signature_data = p_signature_data
  where id = auth.uid();
end;
$$;

grant execute on function public.save_my_signature(text) to authenticated;

-- Lets any authenticated user look up a SIGNATURE + display name by
-- name (case-insensitive), so a report can embed the correct saved
-- signature for whichever officer/leader is named on it — without
-- granting broad read access to everyone's full profile.
create or replace function public.get_signature_by_name(p_name text)
returns table (display_name text, signature_data text)
language sql
security definer
set search_path = public
as $$
  select display_name, signature_data
  from public.user_profiles
  where lower(display_name) = lower(trim(p_name))
    and signature_data is not null
  limit 1;
$$;

grant execute on function public.get_signature_by_name(text) to authenticated;

-- ================================================================
-- Observation Sheet sync (previously built but never actually sent
-- to the server — buildSyncPayload constructed it, but the RPC call
-- never included it as a parameter, so it silently stayed local-only
-- on whichever device created it). Needed now so an on-the-spot
-- Officer in Charge signature is reliably backed up and visible to
-- the rest of the team, not stuck on one device.
-- ================================================================
alter table public.visit_syncs add column if not exists obs_sheet jsonb default '{}';

-- Must DROP the old 8-parameter version first — adding a 9th parameter
-- changes the function's signature, so "create or replace" would create
-- a second, ambiguous overload instead of replacing it.
drop function if exists public.merge_visit_modules(text,uuid,uuid,jsonb,jsonb,jsonb,jsonb,text);

create or replace function public.merge_visit_modules(
  p_visit_id    text,
  p_team_id     uuid,
  p_synced_by   uuid,
  p_setup       jsonb,
  p_new_modules jsonb,
  p_scores      jsonb,
  p_summary     jsonb,
  p_device_id   text,
  p_obs_sheet   jsonb default null
) returns void
language plpgsql
security definer
as $$
begin
  insert into public.visit_syncs (visit_id, team_id, synced_by, setup, modules, scores, summary, device_id, obs_sheet, synced_at)
  values (p_visit_id, p_team_id, p_synced_by, coalesce(p_setup,'{}'::jsonb), coalesce(p_new_modules,'{}'::jsonb), coalesce(p_scores,'{}'::jsonb), coalesce(p_summary,'{}'::jsonb), p_device_id, coalesce(p_obs_sheet,'{}'::jsonb), now())
  on conflict (visit_id) do update
  set modules   = coalesce(visit_syncs.modules, '{}'::jsonb) || coalesce(excluded.modules, '{}'::jsonb),
      scores    = coalesce(visit_syncs.scores,  '{}'::jsonb) || coalesce(excluded.scores,  '{}'::jsonb),
      setup     = coalesce(visit_syncs.setup,   '{}'::jsonb) || coalesce(excluded.setup,   '{}'::jsonb),
      obs_sheet = case when p_obs_sheet is not null
                       then coalesce(visit_syncs.obs_sheet, '{}'::jsonb) || p_obs_sheet
                       else visit_syncs.obs_sheet end,
      summary   = excluded.summary,
      synced_by = excluded.synced_by,
      device_id = excluded.device_id,
      synced_at = now();
end;
$$;

grant execute on function public.merge_visit_modules to authenticated;
