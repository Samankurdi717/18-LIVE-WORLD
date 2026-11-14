-- KURD HALO PK Battle: database foundation
-- Run this entire file once in Supabase SQL Editor.
-- Scores are virtual points only; this feature has no cash-out or real-money wagering.

create table if not exists public.halo_pk_battles (
  id uuid primary key default gen_random_uuid(),
  challenger_user_id uuid not null references auth.users(id) on delete cascade,
  challenger_live_session_id uuid not null references public.live_sessions(id) on delete cascade,
  opponent_user_id uuid not null references auth.users(id) on delete cascade,
  opponent_live_session_id uuid references public.live_sessions(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending','active','finished','cancelled')),
  challenger_score bigint not null default 0 check (challenger_score >= 0),
  opponent_score bigint not null default 0 check (opponent_score >= 0),
  starts_at timestamptz,
  ends_at timestamptz,
  winner_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint halo_pk_different_users check (challenger_user_id <> opponent_user_id)
);

create index if not exists halo_pk_battles_challenger_idx
  on public.halo_pk_battles(challenger_user_id, status, created_at desc);
create index if not exists halo_pk_battles_opponent_idx
  on public.halo_pk_battles(opponent_user_id, status, created_at desc);

alter table public.halo_pk_battles enable row level security;

drop policy if exists "PK participants can read their battles" on public.halo_pk_battles;
create policy "PK participants can read their battles"
on public.halo_pk_battles for select to authenticated
using (auth.uid() = challenger_user_id or auth.uid() = opponent_user_id);

-- No direct INSERT/UPDATE/DELETE policies: changes go through checked RPC functions.

create or replace function public.halo_pk_challenge(
  p_live_session_id uuid,
  p_opponent_user_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_battle_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if p_opponent_user_id = auth.uid() then raise exception 'You cannot challenge yourself'; end if;

  if not exists (
    select 1 from public.live_sessions
    where id = p_live_session_id and user_id = auth.uid() and status = 'live'
  ) then raise exception 'Your live session is not active'; end if;

  if exists (
    select 1 from public.halo_pk_battles
    where status in ('pending','active')
      and (challenger_user_id in (auth.uid(), p_opponent_user_id)
        or opponent_user_id in (auth.uid(), p_opponent_user_id))
  ) then raise exception 'One of the users already has a pending or active battle'; end if;

  insert into public.halo_pk_battles(
    challenger_user_id, challenger_live_session_id, opponent_user_id
  ) values (auth.uid(), p_live_session_id, p_opponent_user_id)
  returning id into v_battle_id;

  return v_battle_id;
end;
$$;

create or replace function public.halo_pk_accept(
  p_battle_id uuid,
  p_live_session_id uuid
) returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;

  if not exists (
    select 1 from public.live_sessions
    where id = p_live_session_id and user_id = auth.uid() and status = 'live'
  ) then raise exception 'Your live session is not active'; end if;

  update public.halo_pk_battles
  set opponent_live_session_id = p_live_session_id,
      status = 'active',
      starts_at = now(),
      ends_at = now() + interval '5 minutes'
  where id = p_battle_id
    and opponent_user_id = auth.uid()
    and status = 'pending';

  if not found then raise exception 'Battle invitation is unavailable'; end if;
end;
$$;

create or replace function public.halo_pk_add_points(
  p_battle_id uuid,
  p_points integer
) returns table (
  challenger_score bigint,
  opponent_score bigint,
  status text,
  winner_user_id uuid
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_battle public.halo_pk_battles%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if p_points is null or p_points < 1 or p_points > 1000 then
    raise exception 'Points must be between 1 and 1000';
  end if;

  select * into v_battle
  from public.halo_pk_battles
  where id = p_battle_id
  for update;

  if not found then raise exception 'Battle not found'; end if;
  if v_battle.status <> 'active' then raise exception 'Battle is not active'; end if;
  if now() >= v_battle.ends_at then
    update public.halo_pk_battles
    set status = 'finished',
        winner_user_id = case
          when challenger_score > opponent_score then challenger_user_id
          when opponent_score > challenger_score then opponent_user_id
          else null
        end
    where id = p_battle_id;
  else
    if auth.uid() = v_battle.challenger_user_id then
      update public.halo_pk_battles
      set challenger_score = challenger_score + p_points
      where id = p_battle_id;
    elsif auth.uid() = v_battle.opponent_user_id then
      update public.halo_pk_battles
      set opponent_score = opponent_score + p_points
      where id = p_battle_id;
    else
      raise exception 'You are not a battle participant';
    end if;
  end if;

  return query
  select b.challenger_score, b.opponent_score, b.status, b.winner_user_id
  from public.halo_pk_battles b where b.id = p_battle_id;
end;
$$;

create or replace function public.halo_pk_finish(p_battle_id uuid)
returns table (
  challenger_score bigint,
  opponent_score bigint,
  status text,
  winner_user_id uuid
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;

  update public.halo_pk_battles b
  set status = 'finished',
      winner_user_id = case
        when b.challenger_score > b.opponent_score then b.challenger_user_id
        when b.opponent_score > b.challenger_score then b.opponent_user_id
        else null
      end
  where b.id = p_battle_id
    and b.status = 'active'
    and now() >= b.ends_at
    and (auth.uid() = b.challenger_user_id or auth.uid() = b.opponent_user_id);

  return query
  select b.challenger_score, b.opponent_score, b.status, b.winner_user_id
  from public.halo_pk_battles b where b.id = p_battle_id;
end;
$$;

revoke all on function public.halo_pk_challenge(uuid, uuid) from public;
revoke all on function public.halo_pk_accept(uuid, uuid) from public;
revoke all on function public.halo_pk_add_points(uuid, integer) from public;
revoke all on function public.halo_pk_finish(uuid) from public;

grant execute on function public.halo_pk_challenge(uuid, uuid) to authenticated;
grant execute on function public.halo_pk_accept(uuid, uuid) to authenticated;
grant execute on function public.halo_pk_add_points(uuid, integer) to authenticated;
grant execute on function public.halo_pk_finish(uuid) to authenticated;

grant select on public.halo_pk_battles to authenticated;
