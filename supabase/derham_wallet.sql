-- KURD HALO: secure Derham wallet + XP levels (1..500)
-- Run this entire file once in Supabase Dashboard > SQL Editor.
-- Client users can READ only their own wallet. They cannot mint/spend Derham or edit XP.
-- Real-money purchases are NOT enabled by this migration.

create table if not exists public.halo_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance bigint not null default 0 check (balance >= 0),
  xp bigint not null default 0 check (xp >= 0),
  level smallint not null default 1 check (level between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.halo_wallet_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount bigint not null,
  entry_type text not null check (entry_type in ('game_reward','purchase','spend','refund','admin_adjustment')),
  description text not null default '',
  reference_id text,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create index if not exists halo_wallet_ledger_user_created_idx
  on public.halo_wallet_ledger(user_id, created_at desc);

alter table public.halo_wallets enable row level security;
alter table public.halo_wallet_ledger enable row level security;

drop policy if exists "Users read own halo wallet" on public.halo_wallets;
create policy "Users read own halo wallet"
  on public.halo_wallets for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users read own halo ledger" on public.halo_wallet_ledger;
create policy "Users read own halo ledger"
  on public.halo_wallet_ledger for select
  to authenticated
  using (auth.uid() = user_id);

-- No INSERT/UPDATE/DELETE policies are created for clients intentionally.

create or replace function public.halo_set_level_from_xp(p_xp bigint)
returns smallint
language sql
immutable
as $$
  select least(500, (1 + floor(sqrt(greatest(p_xp, 0)::numeric / 100)))::smallint);
$$;

create or replace function public.halo_create_wallet_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.halo_wallets(user_id, balance, xp, level)
  values (new.id, 0, 0, 1)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists halo_on_auth_user_created on auth.users;
create trigger halo_on_auth_user_created
  after insert on auth.users
  for each row execute function public.halo_create_wallet_for_new_user();

-- Backfill wallets for accounts that already exist.
insert into public.halo_wallets(user_id)
select id from auth.users
on conflict (user_id) do nothing;

-- Only trusted server-side code using the service_role may award game rewards.
-- This RPC is deliberately unavailable to anon/authenticated browser clients.
create or replace function public.halo_grant_game_reward(
  p_user_id uuid,
  p_derham bigint,
  p_xp bigint,
  p_description text,
  p_reference_id text,
  p_idempotency_key text
)
returns public.halo_wallets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wallet public.halo_wallets;
begin
  if p_user_id is null or p_derham < 0 or p_xp < 0
     or p_derham > 100000 or p_xp > 100000
     or coalesce(length(p_idempotency_key), 0) < 8 then
    raise exception 'Invalid reward request';
  end if;

  insert into public.halo_wallets(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  -- Idempotency prevents the same match reward from being credited twice.
  insert into public.halo_wallet_ledger
    (user_id, amount, entry_type, description, reference_id, idempotency_key)
  values
    (p_user_id, p_derham, 'game_reward', coalesce(p_description,''), p_reference_id, p_idempotency_key)
  on conflict (user_id, idempotency_key) do nothing;

  if found then
    update public.halo_wallets
      set balance = balance + p_derham,
          xp = xp + p_xp,
          level = public.halo_set_level_from_xp(xp + p_xp),
          updated_at = now()
      where user_id = p_user_id
      returning * into v_wallet;
  else
    select * into v_wallet from public.halo_wallets where user_id = p_user_id;
  end if;

  return v_wallet;
end;
$$;

revoke all on function public.halo_grant_game_reward(uuid,bigint,bigint,text,text,text) from public, anon, authenticated;
grant execute on function public.halo_grant_game_reward(uuid,bigint,bigint,text,text,text) to service_role;

grant select on public.halo_wallets, public.halo_wallet_ledger to authenticated;
revoke insert, update, delete on public.halo_wallets, public.halo_wallet_ledger from anon, authenticated;

-- Initial test policy: new accounts start with 0 Derham and level 1.
