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
