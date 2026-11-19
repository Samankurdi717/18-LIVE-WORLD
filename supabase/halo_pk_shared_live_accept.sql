-- KURD HALO: PK uses the challenger's existing Agora live session.
-- Run this migration in Supabase SQL Editor before deploying the matching frontend.
-- The opponent must first join the challenger's channel and be approved as a live guest.
-- Both participants then share one live_session_id; gift scoring distinguishes them by recipient user_id.

create or replace function public.halo_pk_accept(
  p_battle_id uuid,
  p_live_session_id uuid
) returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_battle public.halo_pk_battles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  select *
    into v_battle
    from public.halo_pk_battles
   where id = p_battle_id
     and opponent_user_id = auth.uid()
     and status = 'pending'
   for update;

  if not found then
    raise exception 'Battle invitation is unavailable';
  end if;

  if v_battle.challenger_live_session_id <> p_live_session_id then
    raise exception 'This is not the challengers live session';
  end if;

  if not exists (
    select 1
      from public.live_sessions s
     where s.id = p_live_session_id
       and s.user_id = v_battle.challenger_user_id
       and s.status = 'live'
  ) then
    raise exception 'Challenger live session is not active';
  end if;

  if not exists (
    select 1
      from public.live_guest_requests g
     where g.live_session_id = p_live_session_id
       and g.user_id = auth.uid()
       and g.status = 'approved'
  ) then
    raise exception 'The live host has not approved your guest seat';
  end if;

  update public.halo_pk_battles
     set opponent_live_session_id = p_live_session_id,
         status = 'active',
         starts_at = now(),
         ends_at = now() + interval '5 minutes'
   where id = p_battle_id;
end;
$$;

revoke all on function public.halo_pk_accept(uuid, uuid) from public;
grant execute on function public.halo_pk_accept(uuid, uuid) to authenticated;
