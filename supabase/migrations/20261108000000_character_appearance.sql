-- Fantasy Fitness: character appearance
--
-- The player's look: body frame, skin tone, hairstyle and hair color. Purely cosmetic.
-- The app owns the list of options and the art for them; the server only checks the
-- values are well formed, so a new hairstyle ships without a migration. The app shows
-- its default for anything it doesn't recognize. Safe to re-run.

alter table public.profiles
  add column if not exists body_type text not null default 'narrow'
    check (body_type ~ '^[a-z0-9-]{1,32}$'),
  add column if not exists skin_tone smallint not null default 2
    check (skin_tone between 0 and 31),
  add column if not exists hair_style text not null default 'short'
    check (hair_style ~ '^[a-z0-9-]{1,32}$'),
  add column if not exists hair_color smallint not null default 1
    check (hair_color between 0 and 31);

-- Players change their own look directly ("Update own profile" limits it to their row).
grant update (body_type, skin_tone, hair_style, hair_color) on public.profiles to authenticated;
