-- Fantasy Fitness: gear combat bonuses
--
-- Gear's dungeon bonuses were only text ("+5 dungeon attack"). These columns hold the same
-- numbers so the battle can use them. In-game only: gear never changes real performance or
-- exam results. Keep each item's effect text and bonus columns in step. Safe to re-run.

alter table public.items
  add column if not exists attack_bonus integer not null default 0 check (attack_bonus between 0 and 50);
alter table public.items
  add column if not exists defense_bonus integer not null default 0 check (defense_bonus between 0 and 50);

update public.items i
set attack_bonus = v.attack_bonus, defense_bonus = v.defense_bonus
from (values
  ('iron-helm',      0, 2),
  ('leather-jerkin', 0, 2),
  ('oak-longsword',  3, 0),
  ('moss-hood',      0, 3),
  ('studded-vest',   0, 4),
  ('ash-spear',      5, 0),
  ('ranger-cowl',    0, 5),
  ('chainmail',      0, 6),
  ('war-hammer',     7, 0),
  ('wyrm-helm',      0, 8),
  ('rune-axe',       9, 0)
) as v (id, attack_bonus, defense_bonus)
where i.id = v.id;
