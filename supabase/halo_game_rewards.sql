-- KURD HALO: verified game-result reward settlement foundation
-- Run once in Supabase SQL Editor after derham_wallet.sql.
-- IMPORTANT: this does NOT make rewards available yet. A trusted game server must
-- create a completed match row only after independently validating the game result.

create table if not exists public.halo_game_matches (
  id uuid primary key default gen_random_uuid(),
  game_code text not null,
  status text not null default 'pending'
    check (status in ('pending','completed','cancelled')),
  winner_user_id uuid references auth.users(id) on delete set null,
  derham_reward bigint not null default 0 check (derham_reward between 0 and 100000),
  xp_reward bigint not null default 0 check (xp_reward between 0 and 100000),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  settled_at timestamptz
);

create index if not exists halo_game_matches_status_created_idx
  on public.halo_game_matches(status, created_at desc);

alter table public.halo_game_matches enable row level security;
-- Deliberately create NO client policies and grant NO client write access.
revoke all on public.halo_game_matches from anon, authenticated;
grant select on public.halo_game_matches to service_role;
grant insert, update, delete on public.halo_game_matches to service_role;

create or replace function public.halo_settle_verified_game(p_match_id uuid)
returns public.halo_wallets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match public.halo_game_matches;
  v_wallet public.halo_wallets;
  v_key text;
begin
  if p_match_id is null then
    raise exception 'Match ID is required';
  end if;

  select * into v_match
  from public.halo_game_matches
  where id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found';
  end if;

  if v_match.status <> 'completed'
     or v_match.winner_user_id is null
     or v_match.completed_at is null then
    raise exception 'Match result is not verified and completed';
  end if;

  if v_match.derham_reward < 0 or v_match.derham_reward > 100000
     or v_match.xp_reward < 0 or v_match.xp_reward > 100000 then
    raise exception 'Reward is outside allowed limits';
  end if;

  v_key := 'match:' || v_match.id::text;

  -- A settled match cannot pay twice, even if this function is retried.
  if v_match.settled_at is not null then
    select * into v_wallet
    from public.halo_wallets
    where user_id = v_match.winner_user_id;
    return v_wallet;
  end if;

  insert into public.halo_wallets(user_id)
  values (v_match.winner_user_id)
  on conflict (user_id) do nothing;

  insert into public.halo_wallet_ledger
    (user_id, amount, entry_type, description, reference_id, idempotency_key)
  values
    (v_match.winner_user_id, v_match.derham_reward, 'game_reward',
     'پاداش یاریی تەواوکراو', v_match.id::text, v_key)
  on conflict (user_id, idempotency_key) do nothing;

  if found then
    update public.halo_wallets
      set balance = balance + v_match.derham_reward,
          xp = xp + v_match.xp_reward,
          level = public.halo_set_level_from_xp(xp + v_match.xp_reward),
          updated_at = now()
      where user_id = v_match.winner_user_id
      returning * into v_wallet;
  else
    select * into v_wallet
    from public.halo_wallets
    where user_id = v_match.winner_user_id;
  end if;

  update public.halo_game_matches
    set settled_at = now()
    where id = v_match.id;

  return v_wallet;
end;
$$;

revoke all on function public.halo_settle_verified_game(uuid)
  from public, anon, authenticated;
grant execute on function public.halo_settle_verified_game(uuid)
  to service_role;
