-- ================================================================
-- NHIA M&E Tools v79 — Admin Role & Team Setup Module
-- Run this AFTER teams_and_assignments_schema.sql
-- ================================================================

-- ── 1. Allow 'admin' as a role ───────────────────────────────────
alter table public.user_profiles drop constraint if exists user_profiles_role_check;
alter table public.user_profiles add constraint user_profiles_role_check
  check (role in ('admin', 'leader', 'member'));

-- ── 2. is_admin() helper ──────────────────────────────────────────
-- SECURITY DEFINER lets this function bypass RLS internally, which is
-- required here — a normal RLS policy on user_profiles that queries
-- user_profiles again causes infinite recursion. This function is the
-- safe way to check "is the calling user an admin?" from other policies.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.user_profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

grant execute on function public.is_admin() to authenticated;

-- ── 3. Admin RLS: full access to teams ───────────────────────────
create policy "Admins can create teams"
  on public.teams for insert
  with check (public.is_admin());

create policy "Admins can read all teams"
  on public.teams for select
  using (public.is_admin());

create policy "Admins can update teams"
  on public.teams for update
  using (public.is_admin());

create policy "Admins can delete teams"
  on public.teams for delete
  using (public.is_admin());

-- ── 4. Admin RLS: full access to user_profiles ───────────────────
-- (existing "Own profile readable" policy stays — this adds admin's
-- ability to see and edit EVERYONE's profile, needed to assign people
-- to teams and set their role)
create policy "Admins can read all profiles"
  on public.user_profiles for select
  using (public.is_admin());

create policy "Admins can update all profiles"
  on public.user_profiles for update
  using (public.is_admin());

create policy "Admins can insert profiles"
  on public.user_profiles for insert
  with check (public.is_admin());

-- ── 5. Admin RLS: full access to assignments (any team) ──────────
create policy "Admins can read all assignments"
  on public.assignments for select
  using (public.is_admin());

create policy "Admins can create assignments for any team"
  on public.assignments for insert
  with check (public.is_admin());

create policy "Admins can update any assignment"
  on public.assignments for update
  using (public.is_admin());

create policy "Admins can delete assignments"
  on public.assignments for delete
  using (public.is_admin());


-- ================================================================
-- BOOTSTRAP: make yourself the first Admin
-- (there's no way to do this from inside the app — it must be run
-- once, manually, here)
-- ================================================================
-- update public.user_profiles set role = 'admin' where id = 'YOUR-USER-UUID-HERE';
-- ================================================================
