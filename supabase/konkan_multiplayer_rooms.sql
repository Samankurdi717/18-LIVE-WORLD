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
    values(v_room.id,v_user,v_seat,case when v_seat in (1,3) then 1 else 2 end);
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
   limit 1 for update skip locked;
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


-- Server-authoritative first-round tile dealing. Each player can read only their own hand.
create table if not exists public.halo_konkan_rounds (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.halo_konkan_rooms(id) on delete cascade,
  round_no integer not null default 1,
  cap jsonb not null,
  joker_identity jsonb not null,
  captain_id uuid not null references auth.users(id),
  current_turn_id uuid not null references auth.users(id),
  draw_count integer not null default 48,
  status text not null default 'playing' check (status in ('playing','finished','cancelled')),
  created_at timestamptz not null default now()
);
create unique index if not exists halo_konkan_one_active_round_idx
  on public.halo_konkan_rounds(room_id) where status='playing';

create table if not exists public.halo_konkan_round_hands (
  round_id uuid not null references public.halo_konkan_rounds(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  tiles jsonb not null default '[]'::jsonb,
  primary key(round_id,user_id)
);

create table if not exists public.halo_konkan_round_private (
  round_id uuid primary key references public.halo_konkan_rounds(id) on delete cascade,
  draw_pile jsonb not null default '[]'::jsonb,
  discard_pile jsonb not null default '[]'::jsonb,
  reshuffles integer not null default 0
);

alter table public.halo_konkan_rounds enable row level security;
alter table public.halo_konkan_round_hands enable row level security;
alter table public.halo_konkan_round_private enable row level security;

drop policy if exists "KonKan members can read round" on public.halo_konkan_rounds;
create policy "KonKan members can read round"
on public.halo_konkan_rounds for select to authenticated
using (public.halo_konkan_is_member(room_id));

drop policy if exists "Players can read only their own KonKan hand" on public.halo_konkan_round_hands;
create policy "Players can read only their own KonKan hand"
on public.halo_konkan_round_hands for select to authenticated
using (user_id=auth.uid() and exists (
  select 1 from public.halo_konkan_rounds r
  where r.id=round_id and public.halo_konkan_is_member(r.room_id)
));

-- No client-side SELECT policy is intentionally created for round_private.
-- The draw pile and discard pile are accessed only by future secure RPC actions.

create or replace function public.halo_konkan_start_round(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  v_user uuid := auth.uid();
  v_room public.halo_konkan_rooms%rowtype;
  v_count integer;
  v_players uuid[];
  v_seats integer[];
  v_cap jsonb;
  v_joker_color text;
  v_joker_number integer;
  v_deck jsonb;
  v_tile jsonb;
  v_hand jsonb;
  v_round_id uuid;
  v_captain uuid;
  v_captain_seat integer;
  v_player uuid;
  v_player_seat integer;
  v_deal_count integer;
  v_i integer;
  v_j integer;
  v_len integer;
  v_cap_index integer;
begin
  if v_user is null then raise exception 'تکایە بچۆ ژوورەوە.'; end if;
  select * into v_room from public.halo_konkan_rooms where id=p_room_id for update;
  if not found then raise exception 'ژوورەکە نەدۆزرایەوە.'; end if;
  if v_room.host_id<>v_user then raise exception 'تەنها دروستکەری ژوور دەتوانێت یاری دەست پێ بکات.'; end if;
  select count(*) into v_count from public.halo_konkan_room_players where room_id=p_room_id;
  if v_count<>4 then raise exception 'یاری تەنها کاتێک دەست پێ دەکات کە ٤ یاریزانی ڕاستەقینە ئامادە بن.'; end if;
  if exists(select 1 from public.halo_konkan_rounds where room_id=p_room_id and status='playing') then
    raise exception 'ئەم ژوورە یارییەکی چالاکی هەیە.';
  end if;

  -- Build 104 numbered tiles (two copies of each number/color) plus two Antique tiles.
  select jsonb_agg(x.tile order by random()) into v_deck
  from (
    select jsonb_build_object('id',c.color||'-'||n||'-'||cp,'kind','number','color',c.color,'number',n,'copy',cp) as tile
    from unnest(array['red','black','blue','yellow']) as c(color)
    cross join generate_series(1,13) as n
    cross join generate_series(0,1) as cp
    union all
    select jsonb_build_object('id','antique-0','kind','antique','value',null)
    union all
    select jsonb_build_object('id','antique-1','kind','antique','value',null)
  ) x;

  select (e.ordinality-1)::integer into v_cap_index
  from jsonb_array_elements(v_deck) with ordinality as e(value,ordinality)
  where e.value->>'kind'='number' order by e.ordinality desc limit 1;
  v_cap:=v_deck->v_cap_index;
  v_deck:=v_deck-v_cap_index;
  v_joker_color:=v_cap->>'color';
  if v_joker_color is null then raise exception 'کاپی نادروست هەڵبژێردرا.'; end if;
  v_joker_number:=case when (v_cap->>'number')::integer=1 then 13 else (v_cap->>'number')::integer-1 end;

  -- Convert the two matching natural tiles into the two real Jokers.
  for v_i in 0..jsonb_array_length(v_deck)-1 loop
    v_tile:=v_deck->v_i;
    if v_tile->>'kind'='number' and v_tile->>'color'=v_joker_color
       and (v_tile->>'number')::integer=v_joker_number then
      v_tile:=jsonb_build_object('id',v_tile->>'id','kind','joker',
        'originalColor',v_joker_color,'originalNumber',v_joker_number);
      v_deck:=jsonb_set(v_deck,array[v_i::text],v_tile,false);
    end if;
  end loop;

  -- First round captain is random. Deal order follows the anti-clockwise seat order.
  select user_id,seat_no into v_captain,v_captain_seat
  from public.halo_konkan_room_players where room_id=p_room_id order by random() limit 1;

  insert into public.halo_konkan_rounds(room_id,round_no,cap,joker_identity,captain_id,current_turn_id,draw_count)
  values(p_room_id,1,v_cap,jsonb_build_object('color',v_joker_color,'number',v_joker_number),v_captain,v_captain,48)
  returning id into v_round_id;

  for v_player,v_player_seat in
    select user_id,seat_no from public.halo_konkan_room_players
    where room_id=p_room_id
    order by ((seat_no-v_captain_seat+4)%4)
  loop
    v_deal_count:=case when v_player=v_captain then 15 else 14 end;
    v_hand:='[]'::jsonb;
    for v_j in 1..v_deal_count loop
      v_len:=jsonb_array_length(v_deck);
      v_tile:=v_deck->(v_len-1);
      v_deck:=v_deck-(v_len-1);
      v_hand:=v_hand||jsonb_build_array(v_tile);
    end loop;
    insert into public.halo_konkan_round_hands(round_id,user_id,tiles)
    values(v_round_id,v_player,v_hand);
  end loop;

  insert into public.halo_konkan_round_private(round_id,draw_pile)
  values(v_round_id,v_deck);
  update public.halo_konkan_rooms set status='playing',started_at=now() where id=p_room_id;
  return jsonb_build_object(
    'round_id',v_round_id,
    'cap',v_cap,
    'joker_identity',jsonb_build_object('color',v_joker_color,'number',v_joker_number),
    'captain_id',v_captain,
    'draw_count',jsonb_array_length(v_deck),
    'status','playing'
  );
end;
$$;

revoke all on function public.halo_konkan_start_round(uuid) from public;
grant execute on function public.halo_konkan_start_round(uuid) to authenticated;

do $$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='halo_konkan_rounds') then
    alter publication supabase_realtime add table public.halo_konkan_rounds;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='halo_konkan_round_hands') then
    alter publication supabase_realtime add table public.halo_konkan_round_hands;
  end if;
end $$;
