-- Fantasy Fitness: offline-first uploads
--
-- The app saves workouts and meals on the phone and uploads them later, possibly more
-- than once if a connection drops mid-request. These functions make those uploads safe
-- to retry: the phone creates the id, and a repeat of the same id changes nothing and
-- returns the original result. Safe to re-run.

alter table public.workouts add column if not exists xp_gained integer;
alter table public.workouts add column if not exists loot_item_ids text[] not null default '{}';

-- Offline logs arrive late, but not from a device clock moved to farm old quests.
create or replace function public.assert_recent_date(p_date date) returns void
language plpgsql stable as $$
begin
  if p_date not between current_date - 30 and current_date + 1 then
    raise exception 'That log is dated too far from today to be counted.';
  end if;
end;
$$;

-- Saves a whole workout in one transaction and pays out once. A retry of the same id
-- returns the stored payout. xp_gained covers the workout plus any quest it completed,
-- and item_ids lists the loot from those quests.
create or replace function public.submit_workout(
  p_id uuid,
  p_workout_date date,
  p_started_at timestamptz,
  p_is_exam boolean,
  p_sets jsonb,
  p_quest_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_workout workouts;
  v_xp_before integer;
  v_xp_after integer;
  v_items text[];
  v_set_count integer;
begin
  if v_user is null then
    raise exception 'Not signed in';
  end if;
  perform public.assert_recent_date(p_workout_date);
  if jsonb_typeof(p_sets) <> 'array' or jsonb_array_length(p_sets) not between 1 and 500 then
    raise exception 'A workout needs between 1 and 500 sets';
  end if;

  insert into workouts (id, user_id, quest_id, workout_date, started_at, is_exam)
  values (p_id, v_user, p_quest_id, p_workout_date, least(p_started_at, now()), p_is_exam)
  on conflict (id) do nothing;

  -- The row lock makes a simultaneous retry wait, then see the finished workout.
  select * into v_workout from workouts where id = p_id and user_id = v_user for update;
  if not found then
    raise exception 'Workout not found';
  end if;

  if v_workout.completed_at is not null then
    select count(*) into v_set_count from workout_sets where workout_id = p_id;
    return jsonb_build_object(
      'xp_gained', coalesce(v_workout.xp_gained, 0),
      'sets', v_set_count,
      'item_ids', to_jsonb(v_workout.loot_item_ids)
    );
  end if;

  insert into workout_sets (id, workout_id, exercise, weight_lb, reps, performed_at)
  select (s->>'id')::uuid, p_id, s->>'exercise', (s->>'weight_lb')::numeric, (s->>'reps')::integer,
         least((s->>'performed_at')::timestamptz, now())
  from jsonb_array_elements(p_sets) s
  on conflict (id) do nothing;

  select xp into v_xp_before from profiles where id = v_user;
  perform public.complete_workout(p_id);
  select xp into v_xp_after from profiles where id = v_user;

  -- Everything in this transaction shares now(), so this is exactly what it granted.
  select coalesce(array_agg(item_id), '{}') into v_items
  from inventory
  where user_id = v_user and source = 'quest' and acquired_at = now();

  update workouts set xp_gained = v_xp_after - v_xp_before, loot_item_ids = v_items where id = p_id;

  select count(*) into v_set_count from workout_sets where workout_id = p_id;
  return jsonb_build_object(
    'xp_gained', v_xp_after - v_xp_before,
    'sets', v_set_count,
    'item_ids', to_jsonb(v_items)
  );
end;
$$;

-- Saves a meal once. Macros are filled from the recipe by the meal_logs trigger.
create or replace function public.log_meal(p_id uuid, p_recipe_id uuid, p_servings numeric, p_eaten_on date)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not signed in';
  end if;
  perform public.assert_recent_date(p_eaten_on);
  insert into meal_logs (id, user_id, recipe_id, servings, eaten_on)
  values (p_id, v_user, p_recipe_id, p_servings, p_eaten_on)
  on conflict (id) do nothing;
end;
$$;

revoke execute on function public.assert_recent_date(date) from public, anon, authenticated;
revoke execute on function public.submit_workout(uuid, date, timestamptz, boolean, jsonb, uuid) from public, anon;
revoke execute on function public.log_meal(uuid, uuid, numeric, date) from public, anon;
grant execute on function public.submit_workout(uuid, date, timestamptz, boolean, jsonb, uuid) to authenticated;
grant execute on function public.log_meal(uuid, uuid, numeric, date) to authenticated;
