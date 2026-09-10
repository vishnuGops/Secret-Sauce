-- 1_sim_vocab.sql — GENERATED FILE. DO NOT EDIT BY HAND.
--
-- Source: simData/vocab.json  ·  Generator: tool/sim.dart
-- Regenerate with `melos run sim:gen`; `melos run sim:check` fails if this
-- file is stale.
--
-- Two pools, both indexed by rank:
--
--   sim.vocab_tag      ARRAY ORDER IS RANK. 2_sim_generate.sql draws a rank
--                      with sim.rand_zipf(), so the head lands on a large
--                      fraction of the population and the tail on one or two
--                      recipes. There is deliberately no `weight` column —
--                      two ways to say how common a tag is would drift apart.
--   sim.title_variant  the generic title templates, appended after a dish's
--                      own `variant_titles` and de-duplicated against them.
--                      Indexed by an owner's occurrence of that dish, which is
--                      what keeps `(owner_id, title)` unique (SDS §11.2, D4).
--
-- Everything lives in schema `sim`, never `public` (B026). Standalone and
-- idempotent: own tables with `if not exists`, upsert by rank, and a trim of
-- whatever the source file no longer holds.

create schema if not exists sim;

create table if not exists sim.vocab_tag (
  n          int primary key,
  name       text not null,
  categories text[] not null default '{}'
);

create table if not exists sim.title_variant (
  n        int primary key,
  template text not null
);

do $grants$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema sim from anon, authenticated';
    execute 'revoke all on all tables in schema sim from anon, authenticated';
  end if;
end $grants$;

-- --------------------------------------------------------------------------
-- 66 tags, in rank order. An empty `categories`
-- means the tag may land on any recipe.
-- --------------------------------------------------------------------------
insert into sim.vocab_tag (n, name, categories) values
  (1, $sv$quick$sv$, '{}'::text[]),
  (2, $sv$weeknight$sv$, '{}'::text[]),
  (3, $sv$easy$sv$, '{}'::text[]),
  (4, $sv$vegetarian$sv$, '{}'::text[]),
  (5, $sv$one-pot$sv$, array[$sv$Main$sv$, $sv$Soup$sv$, $sv$Side$sv$]::text[]),
  (6, $sv$comfort-food$sv$, '{}'::text[]),
  (7, $sv$make-ahead$sv$, '{}'::text[]),
  (8, $sv$family-favourite$sv$, '{}'::text[]),
  (9, $sv$budget$sv$, '{}'::text[]),
  (10, $sv$healthy$sv$, '{}'::text[]),
  (11, $sv$gluten-free$sv$, '{}'::text[]),
  (12, $sv$spicy$sv$, '{}'::text[]),
  (13, $sv$dairy-free$sv$, '{}'::text[]),
  (14, $sv$crowd-pleaser$sv$, '{}'::text[]),
  (15, $sv$leftovers$sv$, array[$sv$Main$sv$, $sv$Soup$sv$, $sv$Side$sv$]::text[]),
  (16, $sv$freezer-friendly$sv$, '{}'::text[]),
  (17, $sv$high-protein$sv$, '{}'::text[]),
  (18, $sv$vegan$sv$, '{}'::text[]),
  (19, $sv$baked$sv$, '{}'::text[]),
  (20, $sv$no-cook$sv$, array[$sv$Appetizer$sv$, $sv$Salad$sv$, $sv$Dessert$sv$, $sv$Drink$sv$, $sv$Snack$sv$, $sv$Sauce$sv$]::text[]),
  (21, $sv$grilled$sv$, array[$sv$Appetizer$sv$, $sv$Main$sv$, $sv$Side$sv$, $sv$Salad$sv$]::text[]),
  (22, $sv$slow-cooked$sv$, array[$sv$Main$sv$, $sv$Soup$sv$, $sv$Side$sv$]::text[]),
  (23, $sv$meal-prep$sv$, '{}'::text[]),
  (24, $sv$picnic$sv$, '{}'::text[]),
  (25, $sv$potluck$sv$, '{}'::text[]),
  (26, $sv$brunch$sv$, array[$sv$Breakfast$sv$, $sv$Main$sv$, $sv$Drink$sv$, $sv$Dessert$sv$]::text[]),
  (27, $sv$kid-friendly$sv$, '{}'::text[]),
  (28, $sv$low-carb$sv$, '{}'::text[]),
  (29, $sv$street-food$sv$, array[$sv$Appetizer$sv$, $sv$Main$sv$, $sv$Snack$sv$]::text[]),
  (30, $sv$sheet-pan$sv$, array[$sv$Main$sv$, $sv$Side$sv$]::text[]),
  (31, $sv$air-fryer$sv$, array[$sv$Appetizer$sv$, $sv$Main$sv$, $sv$Side$sv$, $sv$Snack$sv$]::text[]),
  (32, $sv$no-bake$sv$, array[$sv$Dessert$sv$, $sv$Snack$sv$]::text[]),
  (33, $sv$weekend-project$sv$, '{}'::text[]),
  (34, $sv$holiday$sv$, '{}'::text[]),
  (35, $sv$summer$sv$, '{}'::text[]),
  (36, $sv$winter$sv$, '{}'::text[]),
  (37, $sv$five-ingredient$sv$, '{}'::text[]),
  (38, $sv$pantry-staples$sv$, '{}'::text[]),
  (39, $sv$date-night$sv$, '{}'::text[]),
  (40, $sv$batch-cooking$sv$, '{}'::text[]),
  (41, $sv$roasted$sv$, array[$sv$Main$sv$, $sv$Side$sv$, $sv$Salad$sv$, $sv$Soup$sv$]::text[]),
  (42, $sv$stir-fried$sv$, array[$sv$Main$sv$, $sv$Side$sv$]::text[]),
  (43, $sv$braised$sv$, array[$sv$Main$sv$, $sv$Soup$sv$, $sv$Side$sv$]::text[]),
  (44, $sv$fermented$sv$, array[$sv$Side$sv$, $sv$Sauce$sv$, $sv$Drink$sv$, $sv$Snack$sv$]::text[]),
  (45, $sv$pickled$sv$, array[$sv$Appetizer$sv$, $sv$Side$sv$, $sv$Salad$sv$, $sv$Sauce$sv$]::text[]),
  (46, $sv$smoked$sv$, array[$sv$Appetizer$sv$, $sv$Main$sv$, $sv$Side$sv$, $sv$Sauce$sv$]::text[]),
  (47, $sv$nut-free$sv$, '{}'::text[]),
  (48, $sv$egg-free$sv$, '{}'::text[]),
  (49, $sv$low-sodium$sv$, '{}'::text[]),
  (50, $sv$lunchbox$sv$, array[$sv$Main$sv$, $sv$Side$sv$, $sv$Salad$sv$, $sv$Snack$sv$]::text[]),
  (51, $sv$one-pan$sv$, array[$sv$Breakfast$sv$, $sv$Main$sv$, $sv$Side$sv$]::text[]),
  (52, $sv$restaurant-style$sv$, '{}'::text[]),
  (53, $sv$late-night$sv$, array[$sv$Main$sv$, $sv$Snack$sv$, $sv$Dessert$sv$, $sv$Drink$sv$]::text[]),
  (54, $sv$autumn$sv$, '{}'::text[]),
  (55, $sv$spring$sv$, '{}'::text[]),
  (56, $sv$student-cooking$sv$, '{}'::text[]),
  (57, $sv$big-batch$sv$, '{}'::text[]),
  (58, $sv$heritage$sv$, '{}'::text[]),
  (59, $sv$sunday-roast$sv$, array[$sv$Main$sv$]::text[]),
  (60, $sv$camping$sv$, '{}'::text[]),
  (61, $sv$celebration$sv$, '{}'::text[]),
  (62, $sv$sourdough$sv$, array[$sv$Breakfast$sv$, $sv$Main$sv$, $sv$Side$sv$, $sv$Snack$sv$]::text[]),
  (63, $sv$wood-fired$sv$, array[$sv$Appetizer$sv$, $sv$Main$sv$, $sv$Side$sv$]::text[]),
  (64, $sv$sous-vide$sv$, array[$sv$Main$sv$, $sv$Side$sv$]::text[]),
  (65, $sv$foraged$sv$, '{}'::text[]),
  (66, $sv$competition-winner$sv$, '{}'::text[])
on conflict (n) do update set
  name = excluded.name, categories = excluded.categories;

-- --------------------------------------------------------------------------
-- 40 generic title templates.
-- --------------------------------------------------------------------------
insert into sim.title_variant (n, template) values
  (1, $sv${title}$sv$),
  (2, $sv$Weeknight {title}$sv$),
  (3, $sv$My {title}$sv$),
  (4, $sv$Grandmother's {title}$sv$),
  (5, $sv${title}, Simplified$sv$),
  (6, $sv$Slow {title}$sv$),
  (7, $sv${title} for Two$sv$),
  (8, $sv${title} for a Crowd$sv$),
  (9, $sv$Quick {title}$sv$),
  (10, $sv$Sunday {title}$sv$),
  (11, $sv${title} with a Twist$sv$),
  (12, $sv$Family {title}$sv$),
  (13, $sv$Spicy {title}$sv$),
  (14, $sv$Everyday {title}$sv$),
  (15, $sv${title}, Made Ahead$sv$),
  (16, $sv$One-Pot {title}$sv$),
  (17, $sv${title} the Long Way$sv$),
  (18, $sv$Budget {title}$sv$),
  (19, $sv${title}, Lightened Up$sv$),
  (20, $sv$Festival {title}$sv$),
  (21, $sv$Late-Night {title}$sv$),
  (22, $sv${title} from Memory$sv$),
  (23, $sv$Improved {title}$sv$),
  (24, $sv${title}, Second Attempt$sv$),
  (25, $sv$Midweek {title}$sv$),
  (26, $sv$Restaurant-Style {title}$sv$),
  (27, $sv$Better {title}$sv$),
  (28, $sv${title}, Party Size$sv$),
  (29, $sv$Rainy-Day {title}$sv$),
  (30, $sv${title} on a Budget$sv$),
  (31, $sv$Foolproof {title}$sv$),
  (32, $sv${title}, No Fuss$sv$),
  (33, $sv$Holiday {title}$sv$),
  (34, $sv$Market {title}$sv$),
  (35, $sv${title} After Work$sv$),
  (36, $sv$Home-Style {title}$sv$),
  (37, $sv${title}, Take Three$sv$),
  (38, $sv$Sunday-Best {title}$sv$),
  (39, $sv$Pantry {title}$sv$),
  (40, $sv$Freezer {title}$sv$)
on conflict (n) do update set template = excluded.template;

-- Both pools are dense from 1, so a shorter source file is a
-- trim and the upserts above have rewritten the rest.
delete from sim.vocab_tag where n > 66;
delete from sim.title_variant where n > 40;

do $notice$ begin
  raise notice 'Vocabulary loaded (% tags, % title variants)',
  (select count(*) from sim.vocab_tag),
  (select count(*) from sim.title_variant);
end $notice$;

