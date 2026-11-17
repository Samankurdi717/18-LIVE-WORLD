-- KURD HALO multilingual group quiz
-- Run once in Supabase SQL Editor. This creates the group competition backend.
create extension if not exists pgcrypto;

create table if not exists public.kh_quiz_questions (
  question_id smallint primary key,
  correct_option smallint not null check (correct_option between 0 and 3)
);
insert into public.kh_quiz_questions(question_id,correct_option) values
 (0,0),(1,1),(2,2),(3,0),(4,1),(5,2),(6,0),(7,3),(8,1),(9,0),(10,2)
on conflict (question_id) do update set correct_option=excluded.correct_option;

create table if not exists public.kh_quiz_rooms (
  id uuid primary key default gen_random_uuid(),
  room_code text not null unique,
  host_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'waiting' check(status in ('waiting','active','finished')),
  question_order smallint[] not null default '{}',
  question_index integer not null default 0,
  question_started_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.kh_quiz_players (
  room_id uuid not null references public.kh_quiz_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  nickname text not null default 'Player',
  language text not null check(language in ('ku','fa','ar','en')),
  score integer not null default 0 check(score >= 0),
  joined_at timestamptz not null default now(),
  primary key(room_id,user_id)
);

create table if not exists public.kh_quiz_answers (
  room_id uuid not null references public.kh_quiz_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  question_index integer not null,
  selected_option smallint not null check(selected_option between 0 and 3),
  is_correct boolean not null,
  points integer not null default 0 check(points in (0,10)),
  answered_at timestamptz not null default now(),
  primary key(room_id,user_id,question_index)
);

create or replace function public.kh_quiz_is_member(p_room_id uuid)
returns boolean language sql stable security definer set search_path=public
as $$
  select exists(select 1 from public.kh_quiz_players p
    where p.room_id=p_room_id and p.user_id=auth.uid());
$$;

alter table public.kh_quiz_rooms enable row level security;
alter table public.kh_quiz_players enable row level security;
alter table public.kh_quiz_answers enable row level security;
alter table public.kh_quiz_questions enable row level security;

drop policy if exists kh_quiz_room_member_read on public.kh_quiz_rooms;
create policy kh_quiz_room_member_read on public.kh_quiz_rooms
for select to authenticated using (public.kh_quiz_is_member(id));

drop policy if exists kh_quiz_players_member_read on public.kh_quiz_players;
create policy kh_quiz_players_member_read on public.kh_quiz_players
for select to authenticated using (public.kh_quiz_is_member(room_id));

drop policy if exists kh_quiz_answers_member_read on public.kh_quiz_answers;
create policy kh_quiz_answers_member_read on public.kh_quiz_answers
for select to authenticated using (public.kh_quiz_is_member(room_id));

drop policy if exists kh_quiz_questions_read on public.kh_quiz_questions;
create policy kh_quiz_questions_read on public.kh_quiz_questions
for select to authenticated using (true);

create or replace function public.kh_quiz_create_room(p_language text,p_nickname text)
returns table(room_id uuid,room_code text)
language plpgsql security definer set search_path=public
as $$
declare v_room_id uuid; v_code text;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if p_language not in ('ku','fa','ar','en') then raise exception 'Invalid language'; end if;
 v_code:=upper(substr(encode(gen_random_bytes(8),'hex'),1,6));
 insert into public.kh_quiz_rooms(room_code,host_id) values(v_code,auth.uid()) returning id into v_room_id;
 insert into public.kh_quiz_players(room_id,user_id,nickname,language)
 values(v_room_id,auth.uid(),left(coalesce(nullif(trim(p_nickname),''),'Player'),40),p_language);
 return query select v_room_id,v_code;
end $$;

create or replace function public.kh_quiz_join_room(p_code text,p_language text,p_nickname text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare v_room public.kh_quiz_rooms%rowtype; v_count integer;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if p_language not in ('ku','fa','ar','en') then raise exception 'Invalid language'; end if;
 select * into v_room from public.kh_quiz_rooms where room_code=upper(trim(p_code)) for update;
 if not found then raise exception 'Room not found'; end if;
 if v_room.status<>'waiting' then raise exception 'This room has already started'; end if;
 select count(*) into v_count from public.kh_quiz_players where room_id=v_room.id;
 if v_count>=100 then raise exception 'Room is full'; end if;
 insert into public.kh_quiz_players(room_id,user_id,nickname,language)
 values(v_room.id,auth.uid(),left(coalesce(nullif(trim(p_nickname),''),'Player'),40),p_language)
 on conflict(room_id,user_id) do update set language=excluded.language,nickname=excluded.nickname;
 return v_room.id;
end $$;

create or replace function public.kh_quiz_start_room(p_room_id uuid,p_question_order smallint[])
returns void language plpgsql security definer set search_path=public
as $$
declare v_host uuid; v_count integer;
begin
 select host_id into v_host from public.kh_quiz_rooms where id=p_room_id and status='waiting' for update;
 if not found or v_host<>auth.uid() then raise exception 'Only the room host can start'; end if;
 select count(*) into v_count from public.kh_quiz_players where room_id=p_room_id;
 if v_count<2 then raise exception 'At least two players are required'; end if;
 if coalesce(array_length(p_question_order,1),0)<>11 then raise exception 'Question list is invalid'; end if;
 if (select count(distinct x) from unnest(p_question_order) x where x between 0 and 10)<>11 then
   raise exception 'Question order must contain all 11 questions once';
 end if;
 update public.kh_quiz_rooms set status='active',question_order=p_question_order,
 question_index=0,question_started_at=now() where id=p_room_id;
end $$;

create or replace function public.kh_quiz_submit_answer(p_room_id uuid,p_question_index integer,p_selected_option smallint)
returns table(is_correct boolean,correct_option smallint,points_awarded integer)
language plpgsql security definer set search_path=public
as $$
declare v_room public.kh_quiz_rooms%rowtype; v_qid smallint; v_correct smallint; v_ok boolean; v_points integer;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 select * into v_room from public.kh_quiz_rooms where id=p_room_id;
 if not found or v_room.status<>'active' then raise exception 'Round is not active'; end if;
 if not public.kh_quiz_is_member(p_room_id) then raise exception 'Not a room member'; end if;
 if p_question_index<>v_room.question_index then raise exception 'This question has expired'; end if;
 if now()>v_room.question_started_at+interval '12 seconds' then raise exception 'Time is over'; end if;
 v_qid:=v_room.question_order[v_room.question_index+1];
 select q.correct_option into v_correct from public.kh_quiz_questions q where q.question_id=v_qid;
 v_ok:=(p_selected_option=v_correct); v_points:=case when v_ok then 10 else 0 end;
 insert into public.kh_quiz_answers(room_id,user_id,question_index,selected_option,is_correct,points)
 values(p_room_id,auth.uid(),p_question_index,p_selected_option,v_ok,v_points)
 on conflict(room_id,user_id,question_index) do nothing;
 if not found then
   update public.kh_quiz_players set score=score+v_points where room_id=p_room_id and user_id=auth.uid();
 end if;
 return query select v_ok,v_correct,v_points;
end $$;

create or replace function public.kh_quiz_next_question(p_room_id uuid)
returns table(status text,question_index integer,question_started_at timestamptz)
language plpgsql security definer set search_path=public
as $$
declare v public.kh_quiz_rooms%rowtype;
begin
 select * into v from public.kh_quiz_rooms where id=p_room_id for update;
 if not found or v.host_id<>auth.uid() then raise exception 'Only the room host can advance'; end if;
 if v.status<>'active' then raise exception 'Round is not active'; end if;
 if now()<v.question_started_at+interval '12 seconds' then raise exception 'Wait for the 12-second timer'; end if;
 if v.question_index>=array_length(v.question_order,1)-1 then
   update public.kh_quiz_rooms set status='finished' where id=p_room_id;
 else
   update public.kh_quiz_rooms set question_index=question_index+1,question_started_at=now() where id=p_room_id;
 end if;
 return query select r.status,r.question_index,r.question_started_at from public.kh_quiz_rooms r where r.id=p_room_id;
end $$;

grant execute on function public.kh_quiz_create_room(text,text) to authenticated;
grant execute on function public.kh_quiz_join_room(text,text,text) to authenticated;
grant execute on function public.kh_quiz_start_room(uuid,smallint[]) to authenticated;
grant execute on function public.kh_quiz_submit_answer(uuid,integer,smallint) to authenticated;
grant execute on function public.kh_quiz_next_question(uuid) to authenticated;
grant select on public.kh_quiz_rooms,public.kh_quiz_players,public.kh_quiz_answers,public.kh_quiz_questions to authenticated;

do $$
begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='kh_quiz_rooms') then
  alter publication supabase_realtime add table public.kh_quiz_rooms;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='kh_quiz_players') then
  alter publication supabase_realtime add table public.kh_quiz_players;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='kh_quiz_answers') then
  alter publication supabase_realtime add table public.kh_quiz_answers;
 end if;
end $$;
