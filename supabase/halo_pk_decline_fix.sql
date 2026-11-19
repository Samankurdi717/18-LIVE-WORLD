-- KURD HALO PK invitation decline fix.
-- Run this migration in Supabase SQL Editor.
-- A recipient can decline only their own pending invitation.
create or replace function public.halo_pk_decline(p_battle_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  update public.halo_pk_battles
  set status = 'cancelled'
  where id = p_battle_id
    and opponent_user_id = auth.uid()
    and status = 'pending';

  if not found then
    raise exception 'Battle invitation is unavailable';
  end if;
end;
$$;

revoke all on function public.halo_pk_decline(uuid) from public;
grant execute on function public.halo_pk_decline(uuid) to authenticated;
