-- KURD HALO: Award PK score from successfully sent virtual gifts.
-- The gift purchase, wallet changes, gift record, and PK score update run
-- in the same transaction. PK score increases by the gift coin price.
-- No direct client-supplied score is trusted.

create or replace function public.send_live_gift(
  p_live_session_id uuid,
  p_recipient_id uuid,
  p_category text,
  p_gift_name text
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_sender_id uuid := auth.uid();
  v_host_id uuid;
  v_price integer;
  v_points integer;
  v_sender_balance bigint;
  v_platform_share bigint;
  v_recipient_share bigint;
  v_pk public.halo_pk_battles%rowtype;
begin
  if v_sender_id is null then
    raise exception 'You must be logged in';
  end if;

  if p_recipient_id = v_sender_id then
    raise exception 'You cannot send a gift to yourself';
  end if;

  select user_id into v_host_id
  from public.live_sessions
  where id = p_live_session_id
    and status = 'live'
  for update;

  if v_host_id is null then
    raise exception 'Live session is not active';
  end if;

  if p_recipient_id <> v_host_id
     and not exists (
       select 1
       from public.live_guest_requests
       where live_session_id = p_live_session_id
         and user_id = p_recipient_id
         and status = 'approved'
     ) then
    raise exception 'Recipient is not an approved participant';
  end if;

  select coin_price, points
  into v_price, v_points
  from public.halo_gift_catalog
  where category = p_category
    and gift_name = p_gift_name
    and is_active = true;

  if v_price is null then
    raise exception 'Gift not found or inactive';
  end if;

  update public.halo_wallets
  set balance = balance - v_price,
      updated_at = now()
  where user_id = v_sender_id
    and balance >= v_price
  returning balance into v_sender_balance;

  if v_sender_balance is null then
    raise exception 'Insufficient wallet balance';
  end if;

  v_platform_share := round(v_price * 0.40);
  v_recipient_share := v_price - v_platform_share;

  update public.halo_wallets
  set balance = balance + v_recipient_share,
      updated_at = now()
  where user_id = p_recipient_id;

  if not found then
    raise exception 'Recipient wallet not found';
  end if;

  insert into public.halo_wallet_transactions
    (user_id, amount, transaction_type, note)
  values
    (v_sender_id, -v_price, 'gift_sent', p_gift_name),
    (p_recipient_id, v_recipient_share, 'gift_received', p_gift_name);

  insert into public.halo_platform_ledger
    (live_session_id, sender_id, recipient_id, gift_name, coin_amount)
  values
    (p_live_session_id, v_sender_id, p_recipient_id,
     p_gift_name, v_platform_share);

  insert into public.live_gifts
    (live_session_id, sender_id, recipient_id, gift_name,
     gift_emoji, coin_cost, points)
  select p_live_session_id, v_sender_id, p_recipient_id,
         p_gift_name, gift_emoji, v_price, v_points
  from public.halo_gift_catalog
  where category = p_category
    and gift_name = p_gift_name
    and is_active = true;

  -- If the gift is sent to one of the two PK hosts, add its coin price
  -- to that host's score. Guests and non-PK live sessions do not score.
  select *
  into v_pk
  from public.halo_pk_battles
  where status = 'active'
    and (
      (challenger_live_session_id = p_live_session_id
       and challenger_user_id = p_recipient_id)
      or
      (opponent_live_session_id = p_live_session_id
       and opponent_user_id = p_recipient_id)
    )
  for update;

  if found then
    if now() >= v_pk.ends_at then
      update public.halo_pk_battles
      set status = 'finished',
          winner_user_id = case
            when challenger_score > opponent_score then challenger_user_id
            when opponent_score > challenger_score then opponent_user_id
            else null
          end
      where id = v_pk.id;
    elsif p_recipient_id = v_pk.challenger_user_id then
      update public.halo_pk_battles
      set challenger_score = challenger_score + v_price
      where id = v_pk.id;
    elsif p_recipient_id = v_pk.opponent_user_id then
      update public.halo_pk_battles
      set opponent_score = opponent_score + v_price
      where id = v_pk.id;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'gift_name', p_gift_name,
    'price', v_price,
    'sender_balance', v_sender_balance,
    'recipient_earned', v_recipient_share,
    'platform_share', v_platform_share
  );
end;
$function$;
