-- Fantasy Fitness: meal photo scans
--
-- The scan-meal Edge Function sends a meal photo to a vision model, which costs money on
-- every call. Each scan is recorded here before the call, so a player gets a limited
-- number a day and the whole game has a daily ceiling that protects the API key. Rows
-- also keep token counts, to see what scans really cost. Photos are never stored.
-- Safe to re-run.

-- status: 'started' while the scan runs; then 'ok', 'not_food', 'refused' (the model
-- declined), 'rejected' (the API turned the photo down, e.g. not a readable image) or
-- 'failed' (the API was down or busy, its answer was unusable, or our side broke).
create table if not exists public.meal_scans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  status text not null default 'started',
  model text,
  input_tokens integer,
  output_tokens integer,
  item_count integer,
  latency_ms integer
);

alter table public.meal_scans drop constraint if exists meal_scans_status_check;
alter table public.meal_scans add constraint meal_scans_status_check
  check (status in ('started', 'ok', 'not_food', 'refused', 'rejected', 'failed'));

create index if not exists meal_scans_user_recent on public.meal_scans (user_id, created_at desc);
create index if not exists meal_scans_recent on public.meal_scans (created_at desc);

-- Only the Edge Function (service role) touches scans.
alter table public.meal_scans enable row level security;
revoke all on public.meal_scans from anon, authenticated;
grant select, insert, update on public.meal_scans to service_role;

-- Starts a scan if the player and the game are both under their caps for the last 24
-- hours. A 'failed' scan counts toward neither cap: it wasn't the player's doing, and the
-- API mostly doesn't charge for those. Everything else counts, including photos the API
-- turned down, so junk uploads can't use up the game-wide budget for free.
-- Returns {"allowed": bool, "scan_id": uuid or null, "used": n, "reason": "player" | "everyone" | null}.
create or replace function public.begin_meal_scan(p_user uuid, p_user_cap integer, p_global_cap integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_used integer;
  v_everyone integer;
  v_id uuid;
begin
  -- One decision at a time per player, so two quick taps can't both slip under the cap.
  perform pg_advisory_xact_lock(hashtext('meal_scan:' || p_user::text));

  select count(*) into v_used
  from meal_scans
  where user_id = p_user and created_at > now() - interval '24 hours' and status <> 'failed';
  select count(*) into v_everyone
  from meal_scans
  where created_at > now() - interval '24 hours' and status <> 'failed';

  if v_used >= p_user_cap then
    return jsonb_build_object('allowed', false, 'scan_id', null, 'used', v_used, 'reason', 'player');
  end if;
  if v_everyone >= p_global_cap then
    return jsonb_build_object('allowed', false, 'scan_id', null, 'used', v_used, 'reason', 'everyone');
  end if;

  insert into meal_scans (user_id) values (p_user) returning id into v_id;
  return jsonb_build_object('allowed', true, 'scan_id', v_id, 'used', v_used + 1, 'reason', null);
end;
$$;

revoke execute on function public.begin_meal_scan(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.begin_meal_scan(uuid, integer, integer) to service_role;
