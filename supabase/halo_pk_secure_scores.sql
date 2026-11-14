-- KURD HALO security hardening: PK scores must come only from verified gifts.
-- The frontend does not call halo_pk_add_points; gift scoring is handled
-- transactionally by send_live_gift() in halo_pk_gift_scoring.sql.
-- Run this migration in Supabase SQL Editor.

revoke all on function public.halo_pk_add_points(uuid, integer)
  from public, anon, authenticated;

comment on function public.halo_pk_add_points(uuid, integer) is
  'Disabled for client roles. PK scores are awarded only by the verified send_live_gift() transaction.';
