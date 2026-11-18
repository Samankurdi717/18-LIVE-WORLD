-- KURD HALO: enforce a maximum of six approved live-stage guests.
-- Run once in Supabase SQL Editor. Existing approved guests are not removed.
create or replace function public.enforce_halo_live_guest_limit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_approved_count integer;
begin
  if new.status <> 'approved' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'approved'
     and old.live_session_id = new.live_session_id then
    return new;
  end if;

  -- Serialize approvals for the same live session to prevent two hosts/actions
  -- from approving the sixth and seventh guest at the same time.
  perform pg_advisory_xact_lock(
    hashtextextended(new.live_session_id::text, 0)
  );

  select count(*)
    into v_approved_count
    from public.live_guest_requests
   where live_session_id = new.live_session_id
     and status = 'approved'
     and (tg_op = 'INSERT' or id <> new.id);

  if v_approved_count >= 6 then
    raise exception 'This live stage already has six approved guests';
  end if;

  return new;
end;
$$;

drop trigger if exists halo_live_guest_limit_trigger
  on public.live_guest_requests;

create trigger halo_live_guest_limit_trigger
before insert or update on public.live_guest_requests
for each row
execute function public.enforce_halo_live_guest_limit();
