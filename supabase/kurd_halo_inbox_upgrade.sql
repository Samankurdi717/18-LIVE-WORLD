-- KURD HALO Inbox upgrade for the current main/index.html
-- Private text messages, sharing existing feed videos, private gallery uploads,
-- recipient-only read receipts, and Supabase Realtime.
-- REVIEW this file in Supabase SQL Editor. It is NOT auto-applied.

begin;

do $preflight$
declare missing text[] := array[]::text[];
begin
  if to_regclass('public.profiles') is null then missing := array_append(missing,'public.profiles');
  else
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='id' and data_type='uuid') then missing := array_append(missing,'profiles.id uuid'); end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='display_name') then missing := array_append(missing,'profiles.display_name'); end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='avatar_url') then missing := array_append(missing,'profiles.avatar_url'); end if;
  end if;
  if to_regclass('public.videos') is null then missing := array_append(missing,'public.videos');
  else
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='videos' and column_name='id' and data_type='uuid') then missing := array_append(missing,'videos.id uuid'); end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='videos' and column_name='user_id' and data_type='uuid') then missing := array_append(missing,'videos.user_id uuid'); end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='videos' and column_name='storage_path') then missing := array_append(missing,'videos.storage_path'); end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='videos' and column_name='caption') then missing := array_append(missing,'videos.caption'); end if;
  end if;
  if to_regclass('public.user_follows') is null then missing := array_append(missing,'public.user_follows');
  else
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='user_follows' and column_name='follower_id' and data_type='uuid') then missing := array_append(missing,'user_follows.follower_id uuid'); end if;
    if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='user_follows' and column_name='following_id' and data_type='uuid') then missing := array_append(missing,'user_follows.following_id uuid'); end if;
  end if;
  if cardinality(missing)>0 then raise exception 'KURD HALO Inbox preflight failed: %',array_to_string(missing,', '); end if;
end
$preflight$;

create table if not exists public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  content text,
  video_id uuid references public.videos(id) on delete set null,
  media_path text,
  media_mime_type text,
  media_size_bytes bigint,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

alter table public.dm_messages add column if not exists content text;
alter table public.dm_messages add column if not exists video_id uuid references public.videos(id) on delete set null;
alter table public.dm_messages add column if not exists media_path text;
alter table public.dm_messages add column if not exists media_mime_type text;
alter table public.dm_messages add column if not exists media_size_bytes bigint;
alter table public.dm_messages add column if not exists created_at timestamptz not null default now();
alter table public.dm_messages add column if not exists read_at timestamptz;

do $dm_schema_preflight$
begin
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='dm_messages' and column_name='id' and data_type='uuid') then raise exception 'dm_messages.id must be uuid'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='dm_messages' and column_name='sender_id' and data_type='uuid' and is_nullable='NO') then raise exception 'dm_messages.sender_id must be a NOT NULL uuid'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='dm_messages' and column_name='recipient_id' and data_type='uuid' and is_nullable='NO') then raise exception 'dm_messages.recipient_id must be a NOT NULL uuid'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='dm_messages' and column_name='content' and data_type='text' and is_nullable='YES') then raise exception 'dm_messages.content must be nullable text so video-only messages can be sent'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='dm_messages' and column_name='video_id' and data_type='uuid') then raise exception 'dm_messages.video_id must be uuid'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='dm_messages' and column_name='media_path' and data_type='text') then raise exception 'dm_messages.media_path must be text'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='dm_messages' and column_name='media_mime_type' and data_type='text') then raise exception 'dm_messages.media_mime_type must be text'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='dm_messages' and column_name='media_size_bytes' and data_type='bigint') then raise exception 'dm_messages.media_size_bytes must be bigint'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='dm_messages' and column_name='created_at' and data_type='timestamp with time zone') then raise exception 'dm_messages.created_at must be timestamptz'; end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='dm_messages' and column_name='read_at' and data_type='timestamp with time zone') then raise exception 'dm_messages.read_at must be timestamptz'; end if;
  if exists (
    select 1 from public.dm_messages
    where sender_id is null or recipient_id is null or sender_id=recipient_id
       or (content is not null and length(content)>2000)
       or ((content is null or length(trim(content))=0) and video_id is null and media_path is null)
       or (media_path is null and (media_mime_type is not null or media_size_bytes is not null))
       or (media_path is not null and (
         media_mime_type is null or media_mime_type not in ('video/mp4','video/quicktime','video/webm','video/3gpp','video/x-m4v','video/3gpp2')
         or media_size_bytes is null or media_size_bytes not between 1 and 104857600
         or lower(media_path) !~ '^[0-9a-f-]{36}/[a-z0-9-]+\.(mp4|mov|webm|3gp|m4v|3g2)$'
       ))
  ) then raise exception 'Existing dm_messages rows do not satisfy Inbox payload rules; review them before applying this upgrade.'; end if;
end
$dm_schema_preflight$;

alter table public.dm_messages drop constraint if exists dm_no_self_message;
alter table public.dm_messages add constraint dm_no_self_message check (sender_id<>recipient_id);
alter table public.dm_messages drop constraint if exists dm_content_length;
alter table public.dm_messages add constraint dm_content_length check (content is null or length(content)<=2000);
-- Remove the original text-or-feed-video constraint so gallery-only messages are valid.
alter table public.dm_messages drop constraint if exists dm_has_content_or_video;
alter table public.dm_messages drop constraint if exists dm_has_content_video_or_media;
alter table public.dm_messages add constraint dm_has_content_video_or_media check (
  (content is not null and length(trim(content))>0) or video_id is not null or media_path is not null
);
alter table public.dm_messages drop constraint if exists dm_media_metadata_consistent;
alter table public.dm_messages add constraint dm_media_metadata_consistent check (
  (media_path is null and media_mime_type is null and media_size_bytes is null)
  or (media_path is not null and media_mime_type is not null and media_size_bytes is not null
      and media_mime_type in ('video/mp4','video/quicktime','video/webm','video/3gpp','video/x-m4v','video/3gpp2')
      and media_size_bytes between 1 and 104857600
      and lower(media_path) ~ '^[0-9a-f-]{36}/[a-z0-9-]+\.(mp4|mov|webm|3gp|m4v|3g2)$')
);

create index if not exists dm_messages_sender_created_idx on public.dm_messages(sender_id,created_at desc);
create index if not exists dm_messages_recipient_created_idx on public.dm_messages(recipient_id,created_at desc);
create index if not exists dm_messages_unread_recipient_idx on public.dm_messages(recipient_id,created_at desc) where read_at is null;
create index if not exists dm_messages_media_path_idx on public.dm_messages(media_path) where media_path is not null;

alter table public.dm_messages enable row level security;
revoke all on public.dm_messages from public,anon,authenticated;
grant select,insert on public.dm_messages to authenticated;

do $drop_dm_policies$
declare p record;
begin
  for p in select policyname from pg_policies where schemaname='public' and tablename='dm_messages'
  loop execute format('drop policy if exists %I on public.dm_messages',p.policyname); end loop;
end
$drop_dm_policies$;

create policy "dm participants can read messages"
  on public.dm_messages for select to authenticated
  using (auth.uid()=sender_id or auth.uid()=recipient_id);

create policy "users can send direct messages"
  on public.dm_messages for insert to authenticated
  with check (
    auth.uid()=sender_id and sender_id<>recipient_id
    and ((content is not null and length(trim(content))>0) or video_id is not null or media_path is not null)
    and (content is null or length(content)<=2000)
    and (
      media_path is null or (
        media_path like auth.uid()::text||'/%'
        and cardinality(storage.foldername(media_path))=1
        and media_mime_type is not null and media_size_bytes is not null
        and media_mime_type in ('video/mp4','video/quicktime','video/webm','video/3gpp','video/x-m4v','video/3gpp2')
        and media_size_bytes between 1 and 104857600
        and lower(media_path) ~ '^[0-9a-f-]{36}/[a-z0-9-]+\.(mp4|mov|webm|3gp|m4v|3g2)$'
      )
    )
  );

create or replace function public.mark_dm_read(p_sender_id uuid)
returns integer language plpgsql security definer set search_path=public
as $function$
declare updated_count integer;
begin
  update public.dm_messages set read_at=now()
  where recipient_id=auth.uid() and sender_id=p_sender_id and read_at is null;
  get diagnostics updated_count=row_count;
  return updated_count;
end
$function$;
revoke all on function public.mark_dm_read(uuid) from public,anon;
grant execute on function public.mark_dm_read(uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('dm-videos','dm-videos',false,104857600,
  array['video/mp4','video/quicktime','video/webm','video/3gpp','video/x-m4v','video/3gpp2']::text[])
on conflict(id) do update set name=excluded.name,public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

alter table storage.objects enable row level security;
drop policy if exists "dm videos participants can read" on storage.objects;
create policy "dm videos participants can read" on storage.objects for select to authenticated
using (bucket_id='dm-videos' and exists(
  select 1 from public.dm_messages m where m.media_path=storage.objects.name
  and (m.sender_id=auth.uid() or m.recipient_id=auth.uid())
));
drop policy if exists "dm videos users upload to own folder" on storage.objects;
create policy "dm videos users upload to own folder" on storage.objects for insert to authenticated
with check (bucket_id='dm-videos' and (storage.foldername(name))[1]=auth.uid()::text
  and cardinality(storage.foldername(name))=1
  and lower(name) ~ '^[0-9a-f-]{36}/[a-z0-9-]+\.(mp4|mov|webm|3gp|m4v|3g2)$');
drop policy if exists "dm videos owner can delete unlinked uploads" on storage.objects;
create policy "dm videos owner can delete unlinked uploads" on storage.objects for delete to authenticated
using (bucket_id='dm-videos' and (storage.foldername(name))[1]=auth.uid()::text
  and cardinality(storage.foldername(name))=1
  and not exists(select 1 from public.dm_messages m where m.media_path=storage.objects.name));

do $realtime$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='dm_messages') then
      execute 'alter publication supabase_realtime add table public.dm_messages';
    end if;
  else
    raise notice 'supabase_realtime publication not found; enable public.dm_messages Realtime in Supabase Dashboard.';
  end if;
end
$realtime$;

commit;
