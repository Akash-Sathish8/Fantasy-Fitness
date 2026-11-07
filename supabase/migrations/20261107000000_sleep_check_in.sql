-- Fantasy Fitness: sleep check-in
--
-- Until HealthKit is connected, the player ticks a box when they believe they slept
-- at least 7 hours. The server records that night as 7 hours, the Well-Rested
-- threshold, so the existing sleep trigger (Energy, Vitality, quests) runs unchanged.
-- One row per night, so a retried upload changes nothing. Safe to re-run.

create or replace function public.log_rested_night(p_night_of date) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not signed in';
  end if;
  perform public.assert_recent_date(p_night_of);
  insert into sleep_logs (user_id, night_of, hours)
  values (v_user, p_night_of, 7)
  on conflict (user_id, night_of) do nothing;
end;
$$;

revoke execute on function public.log_rested_night(date) from public, anon;
grant execute on function public.log_rested_night(date) to authenticated;
