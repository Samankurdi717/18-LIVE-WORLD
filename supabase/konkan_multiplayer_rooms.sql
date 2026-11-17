-- KURD HALO — real 4-player Hawler KonKan room foundation
-- Run once in Supabase SQL Editor. This creates real authenticated rooms,
-- not locally generated invitation codes. Tile dealing is a separate next phase.

create table if not exists public.halo_konkan_rooms (
  id uuid primary key default gen_random_uuid(),
  room_code text not null unique,
  mode text not null check (mode in ('quick','private')),
  host_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'waiting' check (status in ('waiting','playing','finished','cancelled')),
  created_at timestamptz not null default now(),
  started_at timestamptz
);

create table if not exists public.halo_konkan_room_players (
  room_id uuid not null references public.halo_konkan_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  seat_no smallint not null check (seat_no between 1 and 4),
  team_no smallint not null check (team_no in (1,2)),
  joined_at timestamptz not null default now(),
  primary key (room_id,user_id),
  unique (room_id,seat_no)
);

create index if not exists halo_konkan_rooms_waiting_idx
  on public.halo_konkan_rooms(mode,created_at) where status='waiting';
create index if not exists halo_konkan_players_user_idx
  on public.halo_konkan_room_players(user_id,joined_at desc);

alter table public.halo_konkan_rooms enable row level security;
alter table public.halo_konkan_room_players enable row level security;

create or replace function public.halo_konkan_is_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path=public,auth as $
  select exists(
    select 1 from public.halo_konkan_room_players p
    where p.room_id=p_room_id and p.user_id=auth.uid()
  );
$;

drop policy if exists "KonKan room members can read room" on public.halo_konkan_rooms;
create policy "KonKan room members can read room"
on public.halo_konkan_rooms for select to authenticated
using (public.halo_konkan_is_member(id));

drop policy if exists "KonKan players can read room members" on public.halo_konkan_room_players;
create policy "KonKan players can read room members"
on public.halo_konkan_room_players for select to authenticated
using (public.halo_konkan_is_member(room_id));

create or replace function public.halo_konkan_make_code()
returns text language plpgsql volatile set search_path=public as $$
declare v_code text;
begin
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text),1,6));
    exit when not exists (select 1 from public.halo_konkan_rooms where room_code=v_code);
  end loop;
  return v_code;
end;
$$;

create or replace function public.halo_konkan_create_private_room()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  v_user uuid := auth.uid();
  v_room public.halo_konkan_rooms%rowtype;
begin
  if v_user is null then raise exception 'تکایە بچۆ ژوورەوە.'; end if;
  insert into public.halo_konkan_rooms(room_code,mode,host_id)
  values(public.halo_konkan_make_code(),'private',v_user)
  returning * into v_room;
  insert into public.halo_konkan_room_players(room_id,user_id,seat_no,team_no)
  values(v_room.id,v_user,1,1);
  return jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,'status',v_room.status,'seat_no',1);
end;
$$;

create or replace function public.halo_konkan_join_private_room(p_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  v_user uuid := auth.uid();
  v_room public.halo_konkan_rooms%rowtype;
  v_seat integer;
begin
  if v_user is null then raise exception 'تکایە بچۆ ژوورەوە.'; end if;
  select * into v_room from public.halo_konkan_rooms
   where room_code=upper(trim(p_code)) and mode='private' and status='waiting'
   for update;
  if not found then raise exception 'ژوورەکە نەدۆزرایەوە یان پڕە.'; end if;
  if exists(select 1 from public.halo_konkan_room_players where room_id=v_room.id and user_id=v_user) then
    select seat_no into v_seat from public.halo_konkan_room_players where room_id=v_room.id and user_id=v_user;
  else
    select coalesce(max(seat_no),0)+1 into v_seat from public.halo_konkan_room_players where room_id=v_room.id;
    if v_seat>4 then raise exception 'ژوورەکە پڕە؛ تەنها ٤ یاریزان.'; end if;
    insert into public.halo_konkan_room_players(room_id,user_id,seat_no,team_no)
    values(v_room.id,v_user,v_seat,case when v_seat in (1,4) then 1 else 2 end);
  end if;
  return jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,'status',v_room.status,'seat_no',v_seat);
end;
$$;

create or replace function public.halo_konkan_quick_match()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  v_user uuid := auth.uid();
  v_room public.halo_konkan_rooms%rowtype;
  v_seat integer;
begin
  if v_user is null then raise exception 'تکایە بچۆ ژوورەوە.'; end if;
  select r.* into v_room
    from public.halo_konkan_rooms r
   where r.mode='quick' and r.status='waiting'
     and not exists(select 1 from public.halo_konkan_room_players p where p.room_id=r.id and p.user_id=v_user)
     and (select count(*) from public.halo_konkan_room_players p where p.room_id=r.id)<4
   order by r.created_at
   for update skip locked limit 1;
  if not found then
    insert into public.halo_konkan_rooms(room_code,mode,host_id)
    values(public.halo_konkan_make_code(),'quick',v_user) returning * into v_room;
    v_seat:=1;
  else
    select coalesce(max(seat_no),0)+1 into v_seat from public.halo_konkan_room_players where room_id=v_room.id;
  end if;
  insert into public.halo_konkan_room_players(room_id,user_id,seat_no,team_no)
  values(v_room.id,v_user,v_seat,case when v_seat in (1,4) then 1 else 2 end);
  return jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,'status',v_room.status,'seat_no',v_seat);
end;
$$;

create or replace function public.halo_konkan_start_room(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  v_user uuid := auth.uid();
  v_room public.halo_konkan_rooms%rowtype;
  v_count integer;
begin
  if v_user is null then raise exception 'تکایە بچۆ ژوورەوە.'; end if;
  select * into v_room from public.halo_konkan_rooms where id=p_room_id for update;
  if not found then raise exception 'ژوورەکە نەدۆزرایەوە.'; end if;
  if v_room.host_id<>v_user then raise exception 'تەنها دروستکەری ژوور دەتوانێت یاری دەست پێ بکات.'; end if;
  select count(*) into v_count from public.halo_konkan_room_players where room_id=p_room_id;
  if v_count<>4 then raise exception 'یاری تەنها کاتێک دەست پێ دەکات کە ٤ یاریزانی ڕاستەقینە ئامادە بن.'; end if;
  update public.halo_konkan_rooms set status='playing',started_at=now() where id=p_room_id and status='waiting';
  return jsonb_build_object('room_id',p_room_id,'status','playing','players',v_count);
end;
$$;

revoke all on function public.halo_konkan_make_code() from public;
revoke all on function public.halo_konkan_is_member(uuid) from public;
grant execute on function public.halo_konkan_is_member(uuid) to authenticated;
revoke all on function public.halo_konkan_create_private_room() from public;
revoke all on function public.halo_konkan_join_private_room(text) from public;
revoke all on function public.halo_konkan_quick_match() from public;
revoke all on function public.halo_konkan_start_room(uuid) from public;
grant execute on function public.halo_konkan_create_private_room() to authenticated;
grant execute on function public.halo_konkan_join_private_room(text) to authenticated;
grant execute on function public.halo_konkan_quick_match() to authenticated;
grant execute on function public.halo_konkan_start_room(uuid) to authenticated;

do $$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='halo_konkan_rooms') then
    alter publication supabase_realtime add table public.halo_konkan_rooms;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='halo_konkan_room_players') then
    alter publication supabase_realtime add table public.halo_konkan_room_players;
  end if;
end $$;
