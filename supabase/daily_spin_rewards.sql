-- KURD HALO: secure daily spin rewards (one claim per Baghdad calendar day)
-- Run after derham_wallet.sql and halo_game_rewards.sql.

create table if not exists public.halo_daily_spins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reward_date date not null,
  reward_amount bigint not null check (reward_amount in (5,10,20,50,100)),
  created_at timestamptz not null default now(),
  unique(user_id, reward_date)
);

create index if not exists halo_daily_spins_user_date_idx
  on public.halo_daily_spins(user_id, reward_date desc);

alter table public.halo_daily_spins enable row level security;
revoke all on public.halo_daily_spins from anon, authenticated;
grant select on public.halo_daily_spins to authenticated;
drop policy if exists "Users read own daily spins" on public.halo_daily_spins;
create policy "Users read own daily spins"
  on public.halo_daily_spins for select
  to authenticated using (auth.uid() = user_id);

alter table public.halo_wallet_ledger
  drop constraint if exists halo_wallet_ledger_entry_type_check;
alter table public.halo_wallet_ledger
  add constraint halo_wallet_ledger_entry_type_check
  check (entry_type in ('game_reward','daily_reward','purchase','spend','refund','admin_adjustment'));

create or replace function public.halo_claim_daily_spin(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Baghdad')::date;
  v_reward bigint;
  v_spin public.halo_daily_spins;
  v_wallet public.halo_wallets;
  v_roll numeric := random() * 100;
begin
  if p_user_id is null or not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'Invalid user';
  end if;

  -- Weighted odds: 5=45%, 10=30%, 20=15%, 50=8%, 100=2%.
  v_reward := case
    when v_roll < 45 then 5
    when v_roll < 75 then 10
    when v_roll < 90 then 20
    when v_roll < 98 then 50
    else 100
  end;

  insert into public.halo_daily_spins(user_id, reward_date, reward_amount)
  values (p_user_id, v_today, v_reward)
  on conflict (user_id, reward_date) do nothing
  returning * into v_spin;

  if not found then
    raise exception 'DAILY_SPIN_ALREADY_CLAIMED';
  end if;

  insert into public.halo_wallets(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  insert into public.halo_wallet_ledger
    (user_id, amount, entry_type, description, reference_id, idempotency_key)
  values
    (p_user_id, v_reward, 'daily_reward', 'پاداشی خولی شانسیی ڕۆژانە',
     v_spin.id::text, 'daily-spin:' || v_today::text);

  update public.halo_wallets
  set balance = balance + v_reward, updated_at = now()
  where user_id = p_user_id
  returning * into v_wallet;

  return jsonb_build_object(
    'reward', v_reward,
    'balance', v_wallet.balance,
    'reward_date', v_today,
    'claimed', true
  );
end;
$$;

revoke all on function public.halo_claim_daily_spin(uuid) from public, anon, authenticated;
grant execute on function public.halo_claim_daily_spin(uuid) to service_role;
