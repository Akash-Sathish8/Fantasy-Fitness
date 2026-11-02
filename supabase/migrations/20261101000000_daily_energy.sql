-- Fantasy Fitness: daily Energy and starting values
--
-- New players start with 4 Energy, and every player starts each day with at least
-- 4 (Energy saved above 4 is kept, up to max_energy). Every dungeon run costs 1 Energy.
-- Real activity and sleep still add Energy on top during the day.

alter table public.profiles alter column energy set default 4;
alter table public.profiles add column if not exists last_energy_reset date;

update public.profiles set energy = greatest(energy, 4) where energy < 4;
update public.dungeons set energy_cost = 1 where energy_cost <> 1;

create or replace function public.generate_quests(p_today date) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_class guild_class;
  v_week_start date := p_today - (extract(isodow from p_today)::integer - 1);  -- Monday
  v_count integer;
  t quest_templates;
begin
  if v_user is null then
    raise exception 'Not signed in';
  end if;
  -- The app sends the player's local date. Allow for time zones but not a device
  -- clock that's been moved to farm new days.
  if p_today not between current_date - 1 and current_date + 1 then
    raise exception 'Your device date looks wrong. Set it to automatic and try again.';
  end if;

  -- Start of a new day: top Energy up to 4.
  update profiles
  set energy = least(max_energy, greatest(energy, 4)),
      last_energy_reset = p_today
  where id = v_user and (last_energy_reset is null or last_energy_reset < p_today);

  select guild_class into v_class from profiles where id = v_user and has_completed_onboarding;
  if v_class is null then
    return;
  end if;

  -- Daily: rotate through the class's daily templates (includes rest days).
  if not exists (select 1 from quests where user_id = v_user and kind = 'daily' and starts_on = p_today) then
    select count(*) into v_count from quest_templates
    where kind = 'daily' and (guild_class is null or guild_class = v_class);
    if v_count > 0 then
      select * into t from quest_templates
      where kind = 'daily' and (guild_class is null or guild_class = v_class)
      order by sort_order, id
      offset ((p_today - date '2026-01-05') % v_count + v_count) % v_count
      limit 1;
      perform public.instantiate_quest(v_user, t, p_today, p_today);
    end if;
  end if;

  if not exists (select 1 from quests where user_id = v_user and kind = 'weekly' and starts_on = v_week_start) then
    select * into t from quest_templates
    where kind = 'weekly' and (guild_class is null or guild_class = v_class)
    order by guild_class nulls last, sort_order, id
    limit 1;
    if found then
      perform public.instantiate_quest(v_user, t, v_week_start, v_week_start + 6);
    end if;
  end if;

  -- Story: the next arc the player hasn't finished, four weeks long.
  if not exists (
    select 1 from quests
    where user_id = v_user and kind = 'story' and completed_at is null and ends_on >= p_today
  ) then
    select * into t from quest_templates tt
    where tt.kind = 'story' and (tt.guild_class is null or tt.guild_class = v_class)
      and not exists (
        select 1 from quests q where q.user_id = v_user and q.template_id = tt.id and q.completed_at is not null)
    order by tt.sort_order, tt.id
    limit 1;
    if found then
      perform public.instantiate_quest(v_user, t, p_today, p_today + 27);
    end if;
  end if;

  perform public.refresh_quests(v_user);
end;
$$;
