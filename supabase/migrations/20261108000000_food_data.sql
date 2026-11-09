-- Fantasy Fitness: food data
--
-- Meal and recipe macros come from food data the server wrote, never from numbers the
-- app sends. The Edge Functions in supabase/functions copy foods from USDA FoodData
-- Central (or, for a photo scan, save the model's per-100 g estimate) into `foods`. The
-- app sends food ids and grams, and the functions below do the multiplying.
--
-- Daily protein completes weekly quests, so players also lose the ability to write meal
-- macro columns directly; meals arrive through log_meal and log_food_meal only.
-- Safe to re-run.

-- Per-100 g nutrition. 'usda' rows are shared by everyone; an 'estimate' row came from
-- one player's photo scan and only that player can log it.
create table if not exists public.foods (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('usda', 'estimate')),
  fdc_id integer unique,
  data_type text,
  name text not null check (char_length(name) between 1 and 200),
  kcal_100g numeric(5, 1) not null check (kcal_100g between 0 and 900),
  protein_100g numeric(5, 2) not null check (protein_100g between 0 and 100),
  carbs_100g numeric(5, 2) not null check (carbs_100g between 0 and 100),
  fat_100g numeric(5, 2) not null check (fat_100g between 0 and 100),
  -- Household portions from USDA: [{"label": "1 medium breast", "grams": 120}]
  portions jsonb not null default '[]',
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  check ((source = 'usda') = (fdc_id is not null))
);

-- Players never read or write foods directly; they get food data from the Edge
-- Functions, which use the service role. New tables are granted to the API roles by
-- default, so take that back.
alter table public.foods enable row level security;
revoke all on public.foods from anon, authenticated;
grant select, insert, update on public.foods to service_role;

-- A recipe ingredient picked from the food search counts toward the recipe's macros.
-- Ingredients typed in as text keep only a name and amount and aren't counted.
alter table public.recipe_ingredients add column if not exists food_id uuid references public.foods (id);
alter table public.recipe_ingredients add column if not exists grams numeric(6, 1) check (grams > 0 and grams <= 5000);

-- What a plate meal was made of: [{"food_id": "...", "grams": 150}]
alter table public.meal_logs add column if not exists items jsonb;

-- Meals come in through log_meal (a recipe) or log_food_meal (a plate of foods), which
-- fill the macros themselves. Players keep the columns old builds sent directly.
revoke insert (name, calories, protein_g, carbs_g, fat_g) on public.meal_logs from authenticated;

-- Saves a plate of foods once. p_items: [{"food_id": "...", "grams": 150}]. The macros
-- are summed here from foods; the app's numbers are only a display copy.
create or replace function public.log_food_meal(p_id uuid, p_name text, p_items jsonb, p_eaten_on date)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_items integer;
  v_known integer;
  v_kcal integer;
  v_protein integer;
  v_carbs integer;
  v_fat integer;
  v_saved jsonb;
begin
  if v_user is null then
    raise exception 'Not signed in';
  end if;
  -- A retry of a meal that already arrived changes nothing.
  if exists (select 1 from meal_logs where id = p_id) then
    return;
  end if;
  perform public.assert_recent_date(p_eaten_on);
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 30 then
    raise exception 'A meal needs between 1 and 30 foods.';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) i
    where (i ->> 'grams') is null or round((i ->> 'grams')::numeric, 1) not between 1 and 2000
  ) then
    raise exception 'Each food must weigh between 1 and 2,000 g.';
  end if;

  with items as (
    select (i ->> 'food_id')::uuid as food_id, round((i ->> 'grams')::numeric, 1) as grams
    from jsonb_array_elements(p_items) i
  )
  select count(*), count(f.id),
         round(sum(f.kcal_100g * it.grams / 100))::integer,
         round(sum(f.protein_100g * it.grams / 100))::integer,
         round(sum(f.carbs_100g * it.grams / 100))::integer,
         round(sum(f.fat_100g * it.grams / 100))::integer,
         jsonb_agg(jsonb_build_object('food_id', it.food_id, 'grams', it.grams))
  into v_items, v_known, v_kcal, v_protein, v_carbs, v_fat, v_saved
  from items it
  left join foods f on f.id = it.food_id and (f.source = 'usda' or f.created_by = v_user);

  if v_known < v_items then
    raise exception 'One of those foods isn''t available. Remove it and log again.';
  end if;

  -- recipe_id stays null, so the fill_meal_macros trigger keeps these totals.
  insert into meal_logs (id, user_id, recipe_id, name, servings, calories, protein_g, carbs_g, fat_g, eaten_on, items)
  values (p_id, v_user, null, coalesce(nullif(trim(left(trim(p_name), 80)), ''), 'Plate'), 1,
          v_kcal, v_protein, v_carbs, v_fat, p_eaten_on, v_saved)
  on conflict (id) do nothing;
end;
$$;

-- Creates a recipe and its ingredients in one transaction, then works out its macros.
-- p_ingredients: [{"name": "...", "amount": "..."}] for a typed-in ingredient, or
-- [{"name": "...", "food_id": "...", "grams": 150}] for one picked from the food search.
-- Per-serving macros count the picked ingredients only; with none, they stay null
-- ("Macros pending"). Security definer because players can't write the macro columns.
create or replace function public.create_recipe(
  p_name text, p_meal_type public.meal_type, p_minutes integer, p_servings integer, p_ingredients jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null then
    raise exception 'Not signed in';
  end if;
  if jsonb_typeof(p_ingredients) is distinct from 'array' or jsonb_array_length(p_ingredients) > 40 then
    raise exception 'A recipe can have up to 40 ingredients.';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_ingredients) i
    where ((i ->> 'food_id') is null) <> ((i ->> 'grams') is null)
       or round((i ->> 'grams')::numeric, 1) not between 1 and 5000
  ) then
    raise exception 'Each counted ingredient needs between 1 and 5,000 g.';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_ingredients) i
    left join foods f on f.id = (i ->> 'food_id')::uuid and (f.source = 'usda' or f.created_by = v_user)
    where (i ->> 'food_id') is not null and f.id is null
  ) then
    raise exception 'One of those ingredients isn''t available. Remove it and save again.';
  end if;

  insert into recipes (author_id, name, meal_type, minutes, servings)
  values (v_user, trim(p_name), p_meal_type, p_minutes, p_servings)
  returning id into v_id;

  insert into recipe_ingredients (recipe_id, position, name, amount, food_id, grams)
  select v_id, (i.ordinality - 1)::integer, trim(left(trim(i.value ->> 'name'), 80)),
         case
           when (i.value ->> 'grams') is not null
             then trim_scale(round((i.value ->> 'grams')::numeric, 1))::text || ' g'
           else coalesce(i.value ->> 'amount', '')
         end,
         (i.value ->> 'food_id')::uuid,
         round((i.value ->> 'grams')::numeric, 1)
  from jsonb_array_elements(p_ingredients) with ordinality as i(value, ordinality);

  update recipes r
  set calories = t.kcal, protein_g = t.protein, carbs_g = t.carbs, fat_g = t.fat
  from (
    select count(*) as linked,
           round(sum(f.kcal_100g * ri.grams / 100) / p_servings)::integer as kcal,
           round(sum(f.protein_100g * ri.grams / 100) / p_servings)::integer as protein,
           round(sum(f.carbs_100g * ri.grams / 100) / p_servings)::integer as carbs,
           round(sum(f.fat_100g * ri.grams / 100) / p_servings)::integer as fat
    from recipe_ingredients ri
    join foods f on f.id = ri.food_id
    where ri.recipe_id = v_id
  ) t
  where r.id = v_id and t.linked > 0;

  return v_id;
end;
$$;

revoke execute on function public.log_food_meal(uuid, text, jsonb, date) from public, anon;
revoke execute on function public.create_recipe(text, public.meal_type, integer, integer, jsonb) from public, anon;
grant execute on function public.log_food_meal(uuid, text, jsonb, date) to authenticated;
grant execute on function public.create_recipe(text, public.meal_type, integer, integer, jsonb) to authenticated;
