-- corpus_import_fixture.sql — the corpus importer, end to end, on a committed
-- fixture. Phase 35c.
--
-- `tool/corpus_import.dart` (JSON -> `select import_recipe(...)` SQL) and
-- `import_recipe(jsonb)` (that SQL -> rows) were proven only by having been run
-- once over the real corpus. This file imports `corpus/_fixtures/` — a handful
-- of SYNTHETIC records in the harvester's shape, each one there to exercise one
-- rule — and asserts what landed, field by field. Then it applies the same
-- files again and asserts that nothing changed, because idempotency is the
-- property every resume of a real import leans on.
--
-- It reads the generated SQL, not the fixture JSON, so generate first:
--
--   dart run tool/corpus_import.dart gen --corpus=corpus/_fixtures \
--     --out=corpus/_import_fixture --batch=3
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/corpus_import_fixture.sql
--
-- `--batch=3` is part of the contract: five documents make exactly two files,
-- so the writer's flush-the-remainder path is covered and the two `\ir` lines
-- below both have something to read. A different batch size is a missing file
-- here, which fails loudly rather than asserting over half the fixture.
--
-- Everything runs as postgres inside ONE transaction that is ROLLED BACK. The
-- fixture's entities are `src:fixture-*` and its URLs are on the reserved
-- `.test` TLD, so it cannot collide with a real capture — and the first
-- assertion refuses to run at all if either already exists, because every
-- count below would then be measuring someone else's rows.
--
-- Trigger: any change to tool/corpus_import.dart, import_recipe(), or
-- corpus/_fixtures/. A fixture edit changes the expectations here in the same
-- commit.

\set ON_ERROR_STOP on

begin;

do $pre$
begin
  assert not exists (select 1 from entities where slug like 'src:fixture-%'),
    'src:fixture-* entities already exist in this database; the counts below would be meaningless';
end
$pre$;

\ir ../../corpus/_import_fixture/0001.sql
\ir ../../corpus/_import_fixture/0002.sql

do $fx$
declare
  v_blog     uuid;
  v_brand    uuid;
  v_r1       recipes%rowtype;
  v_r2       recipes%rowtype;
  v_r6       recipes%rowtype;
  v_b2       recipes%rowtype;
  v_names    text[];
  v_steps    text[];
  n          bigint;
begin
  select id into v_blog  from entities where slug = 'src:fixture-chef-blog';
  select id into v_brand from entities where slug = 'src:fixture-brand';

  -- ==========================================================================
  -- 1. What landed, and what did not.
  -- ==========================================================================
  -- Two publishers: the foreign-language source is outside the English-first
  -- tier, and the source with no shard contributes nothing — not even an
  -- entity, because the importer only ever creates one on a recipe's behalf.
  assert v_blog is not null and v_brand is not null, 'both fixture publishers exist';
  select count(*) into n from entities where slug like 'src:fixture-%';
  assert n = 2, format('2 fixture entities, got %s', n);
  assert (select kind from entities where id = v_blog) = 'chef_site',
    'a corpus `chef` site is the `chef_site` entity kind — a person is not an entity';
  assert (select kind from entities where id = v_brand) = 'brand';
  assert (select country from entities where id = v_brand) = 'GB';
  assert (select created_by from entities where id = v_blog) is null,
    'nobody on this service registered an imported publisher';

  -- Five documents were generated and FOUR recipes exist: the fifth is the
  -- duplicate capture of R1's URL, and `unique(source_entity_id, source_url)`
  -- turned it into a no-op inside the very batch that carried it.
  select count(*) into n from recipes where source_entity_id in (v_blog, v_brand);
  assert n = 4, format('4 imported recipes, got %s', n);
  assert not exists (
    select 1 from recipes where title in (
      'Fixture No Cover', 'Fixture Thin Capture', 'Fixture No Servings',
      'Fixture Foreign Recipe', 'Fixture Brown Butter Shortbread (duplicate capture)')),
    'a gated, duplicate or out-of-tier record was imported';

  -- Every imported row is marked, public, unranked by construction, and
  -- carries none of the publisher's prose (Phase 35a — linked, not reproduced).
  select count(*) into n from recipes
   where source_entity_id in (v_blog, v_brand)
     and is_imported and visibility = 'public' and description = ''
     and imported_at is not null and rights_mode = 'functional';
  assert n = 4, format('4 marked, public, prose-free rows, got %s', n);
  assert not exists (
    select 1 from recipes r where r.source_entity_id in (v_blog, v_brand)
       and r.description like '%FIXTURE-PROSE%'),
    'the captured description reached the database';

  -- ==========================================================================
  -- 2. R1 — every field populated.
  -- ==========================================================================
  select * into v_r1 from recipes where title = 'Fixture Brown Butter Shortbread';
  -- `finalUrl` wins over `sourceUrl`: the redirect target is the page's
  -- identity, and the query-stringed feed URL would split one recipe into two.
  assert v_r1.source_url = 'https://chef-blog.example.test/shortbread/',
    format('source_url is finalUrl: %s', v_r1.source_url);
  assert v_r1.source_name = 'Fixture Chef Blog';
  assert v_r1.cover_image_url = 'https://img.example.test/shortbread.jpg',
    format('first cover wins: %s', v_r1.cover_image_url);
  assert v_r1.cuisine = 'Scottish' and v_r1.category = 'Dessert',
    format('first cuisine/category: %s / %s', v_r1.cuisine, v_r1.category);
  assert v_r1.servings = 16 and v_r1.prep_minutes = 15 and v_r1.cook_minutes = 25,
    format('servings/prep/cook: %s/%s/%s', v_r1.servings, v_r1.prep_minutes, v_r1.cook_minutes);
  assert v_r1.created_at = '2021-03-04T10:00:00Z'::timestamptz,
    format('a parseable datePublished dates the recipe: %s', v_r1.created_at);
  -- cover 25 + servings 15 + time 15 + byline 15 + cuisine 5 + category 5
  -- + 4 ingredients (3..40) 10 + 3 steps (2..40) 10.
  assert v_r1.quality_score = 100, format('R1 quality 100, got %s', v_r1.quality_score);
  assert (select display_name from profiles where id = v_r1.owner_id) = 'Fixture Cook',
    'the byline, not the publisher, owns a credited recipe';
  assert (select kind from profiles where id = v_r1.owner_id) = 'imported';

  -- Ingredient groups in page order; the unnamed line falls back to its raw
  -- text; the line with neither is dropped rather than imported blank.
  select array_agg(name order by sort_order) into v_names
    from ingredient_groups where recipe_id = v_r1.id;
  assert v_names = array['For the dough', 'To finish'],
    format('ingredient groups: %s', v_names);
  select array_agg(i.name order by i.sort_order) into v_names
    from ingredients i join ingredient_groups g on g.id = i.group_id
   where g.recipe_id = v_r1.id and g.name = 'To finish';
  assert v_names = array['a pinch of flaky salt'],
    format('raw fallback, blank line dropped: %s', v_names);
  assert exists (
    select 1 from ingredients i join ingredient_groups g on g.id = i.group_id
     where g.recipe_id = v_r1.id and i.name = 'butter'
       and i.quantity = 200 and i.unit = 'g' and i.note = 'browned and cooled'),
    'quantity, unit and note travel with the ingredient';

  -- Steps are flat in the corpus with a group LABEL on each, and the labels
  -- interleave (Dough, Finish, Dough). Grouping keeps first-appearance order
  -- and never sorts; the whitespace-only step is dropped.
  select array_agg(name order by sort_order) into v_names
    from step_groups where recipe_id = v_r1.id;
  assert v_names = array['Dough', 'Finish'], format('step groups: %s', v_names);
  select array_agg(s.text order by s.step_order) into v_steps
    from steps s join step_groups g on g.id = s.group_id
   where g.recipe_id = v_r1.id and g.name = 'Dough';
  assert v_steps = array['Brown the butter.', 'Mix and press into the tin.'],
    format('Dough steps: %s', v_steps);
  assert exists (
    select 1 from steps s join step_groups g on g.id = s.group_id
     where g.recipe_id = v_r1.id and s.text = 'Brown the butter.'
       and s.duration_minutes = 8
       and s.tip = 'Take it off the heat when the foam subsides.'),
    'duration and tip travel with the step';
  assert exists (
    select 1 from steps s join step_groups g on g.id = s.group_id
     where g.recipe_id = v_r1.id and s.text = 'Mix and press into the tin.'
       and s.temperature = '160C' and s.step_order = 1 and s.sort_order = 1),
    'temperature travels, and numbering restarts inside each group (B022)';

  -- ==========================================================================
  -- 3. R2 — the degraded record.
  -- ==========================================================================
  select * into v_r2 from recipes where title = 'Fixture Weeknight Dal';
  -- No byline: credited to the publisher alone, as a profile named for it.
  assert (select display_name from profiles where id = v_r2.owner_id) = 'Fixture Chef Blog',
    'a page that names nobody is credited to its publisher';
  -- A total-only time is attributed to cooking rather than split or dropped.
  assert v_r2.prep_minutes = 0 and v_r2.cook_minutes = 45,
    format('total-only timing -> cook: %s/%s', v_r2.prep_minutes, v_r2.cook_minutes);
  -- An unparseable date is an unknown date: dropped by the tool, so the row
  -- takes `now()` — which inside this transaction is exactly `now()`.
  assert v_r2.created_at = now(),
    format('unparseable datePublished -> now(): %s', v_r2.created_at);
  -- A string category is read as-is; an empty cuisine list is null.
  assert v_r2.category = 'Main' and v_r2.cuisine is null,
    format('category/cuisine: %s / %s', v_r2.category, v_r2.cuisine);
  -- cover 25 + servings 15 + time 15 + category 5 + ingredients 10 + steps 10.
  assert v_r2.quality_score = 80, format('R2 quality 80, got %s', v_r2.quality_score);
  -- The writer dollar-quotes each document and must pick a tag the document
  -- does not contain. This step holds the default tag, verbatim.
  assert exists (
    select 1 from steps s join step_groups g on g.id = s.group_id
     where g.recipe_id = v_r2.id
       and s.text = 'Temper the cumin in oil; the $ci$ in this sentence is a quoting test.'),
    'the literal $ci$ survived the dollar-quoting';
  select count(*) into n from step_groups where recipe_id = v_r2.id;
  assert n = 1, format('ungrouped steps make one group, got %s', n);

  -- ==========================================================================
  -- 4. Identity is scoped to the publisher and reused within it.
  -- ==========================================================================
  select * into v_r6 from recipes where title = 'Fixture Oat Porridge';
  assert v_r6.owner_id = v_r1.owner_id,
    'a second recipe by the same byline on the same publisher reuses the profile';
  select count(*) into n from profiles p
    join entity_members m on m.profile_id = p.id
   where m.entity_id in (v_blog, v_brand);
  assert n = 3, format('3 imported profiles (Fixture Cook, the blog, the brand lead), got %s', n);

  select * into v_b2 from recipes where title = 'Fixture Brand Scones';
  assert (select display_name from profiles where id = v_b2.owner_id) = 'Fixture Test Kitchen Lead';
  assert v_b2.source_entity_id = v_brand and v_b2.source_name = 'Fixture Brand Kitchen';
  assert v_b2.created_at = '2020-05-01'::timestamptz,
    format('a date-only datePublished parses: %s', v_b2.created_at);

  -- Unranked: no imported fixture profile reaches the board (Phase 35b).
  select count(*) into n from chefs_leaderboard(100000, 0) b
   where b.id in (v_r1.owner_id, v_r2.owner_id, v_b2.owner_id);
  assert n = 0, format('imported fixture chefs on the leaderboard: %s', n);

  -- Snapshot for the re-apply below.
  create temp table corpus_fixture_before on commit drop as
  select
    (select count(*) from recipes where source_entity_id in (v_blog, v_brand)) as recipes,
    (select count(*) from ingredient_groups g join recipes r on r.id = g.recipe_id
      where r.source_entity_id in (v_blog, v_brand)) as ingredient_groups,
    (select count(*) from ingredients i join ingredient_groups g on g.id = i.group_id
      join recipes r on r.id = g.recipe_id
      where r.source_entity_id in (v_blog, v_brand)) as ingredients,
    (select count(*) from steps s join step_groups g on g.id = s.group_id
      join recipes r on r.id = g.recipe_id
      where r.source_entity_id in (v_blog, v_brand)) as steps,
    (select count(*) from entity_members where entity_id in (v_blog, v_brand)) as members,
    (select count(*) from entities where slug like 'src:fixture-%') as entities;

  raise notice 'corpus_import_fixture: first apply — all assertions passed';
end
$fx$;

-- ============================================================================
-- 5. The same files again. Nothing may change: no recipe, no content row, no
--    second profile for a byline, no second entity.
-- ============================================================================
\ir ../../corpus/_import_fixture/0001.sql
\ir ../../corpus/_import_fixture/0002.sql

do $again$
declare
  b corpus_fixture_before%rowtype;
  a corpus_fixture_before%rowtype;
begin
  select * into b from corpus_fixture_before;
  select
    (select count(*) from recipes r join entities e on e.id = r.source_entity_id
      where e.slug like 'src:fixture-%'),
    (select count(*) from ingredient_groups g join recipes r on r.id = g.recipe_id
      join entities e on e.id = r.source_entity_id where e.slug like 'src:fixture-%'),
    (select count(*) from ingredients i join ingredient_groups g on g.id = i.group_id
      join recipes r on r.id = g.recipe_id
      join entities e on e.id = r.source_entity_id where e.slug like 'src:fixture-%'),
    (select count(*) from steps s join step_groups g on g.id = s.group_id
      join recipes r on r.id = g.recipe_id
      join entities e on e.id = r.source_entity_id where e.slug like 'src:fixture-%'),
    (select count(*) from entity_members m join entities e on e.id = m.entity_id
      where e.slug like 'src:fixture-%'),
    (select count(*) from entities where slug like 'src:fixture-%')
  into a;
  assert a = b, format('re-apply changed the import: before %s, after %s', b, a);
  raise notice 'corpus_import_fixture: re-apply is a no-op — %', a;
end
$again$;

-- ============================================================================
-- 6. Import-time cleaning (Phase 37 — B127 bylines, B134 titles). The pure
--    functions on the corpus's real shapes, then one document end to end, so
--    `import_recipe` is proven to call them rather than merely compile beside
--    them.
-- ============================================================================
do $clean$
declare
  v_id   uuid;
  v_name text;
begin
  assert byline_person('Adapted from <a href="https://x.test/y">Silk Canada</a>') is null,
    'a credit line is not a person';
  assert byline_person('Jennifer Segal, adapted from <a href="http://a.test">Mix</a>') = 'Jennifer Segal',
    'provenance after the name is dropped';
  assert byline_person('Isabelle Boucher (<a href="https://c.test">Crumb</a>)') = 'Isabelle Boucher (Crumb)',
    'markup inside a name is stripped, the text kept';
  assert byline_person('Linda &amp; Alex') = 'Linda & Alex', 'entities decode';
  assert byline_person('kannamma @ https://k.test/') = 'kannamma', 'a trailing URL goes';
  assert byline_person(repeat('word ', 20)) is null, 'a sentence is not a name';
  assert clean_byline_text('Adapted from <a href="x">Silk</a>') = 'Adapted from Silk',
    'the readable fallback carries no markup';
  assert clean_import_title('Pumpkin Muffin Recipe + VIDEO') = 'Pumpkin Muffin';
  assert clean_import_title('Mondongo Soup [Video+Recipe] Tripe Stew') = 'Mondongo Soup Tripe Stew';
  assert clean_import_title('Easy Recipe') = 'Easy Recipe', 'Recipe goes only after two words';
  -- One pass left `… - VIDEO` behind, so a re-apply of the backfill changed
  -- rows again; the cleaner has to be idempotent.
  assert clean_import_title('Vanilla Mousse - VIDEO Recipe') = 'Vanilla Mousse',
    'the cleaner runs to a fixed point';
  assert clean_import_title('Fixture Brown Butter Shortbread') = 'Fixture Brown Butter Shortbread',
    'a clean title is untouched';

  v_id := import_recipe(jsonb_build_object(
    'source_url', 'https://clean.example.test/muffins/',
    'entity_slug', 'fixture-clean',
    'entity_name', 'Fixture Clean Kitchen',
    'entity_kind', 'chef_site',
    'title', 'Fixture Muffin Recipe + VIDEO',
    'chef_name', 'Fixture Baker, adapted from <a href="https://b.test">A Book</a>',
    'ingredient_groups', jsonb_build_array(jsonb_build_object('name', '',
      'ingredients', jsonb_build_array(jsonb_build_object('name', 'flour', 'quantity', 1, 'unit', 'cup')))),
    'step_groups', jsonb_build_array(jsonb_build_object('name', '',
      'steps', jsonb_build_array(jsonb_build_object('text', 'Bake.'))))
  ));
  assert v_id is not null, 'the cleaning fixture imported';
  assert (select title from recipes where id = v_id) = 'Fixture Muffin',
    'import_recipe stores the cleaned title';
  select p.display_name into v_name
    from recipes r join profiles p on p.id = r.owner_id where r.id = v_id;
  assert v_name = 'Fixture Baker', format('import_recipe credits the cleaned byline, got %s', v_name);

  -- A byline that names nobody credits the publisher, not a sentence.
  v_id := import_recipe(jsonb_build_object(
    'source_url', 'https://clean.example.test/cake/',
    'entity_slug', 'fixture-clean',
    'entity_name', 'Fixture Clean Kitchen',
    'entity_kind', 'chef_site',
    'title', 'Fixture Cake',
    'chef_name', 'Adapted from <a href="https://b.test">A Book</a>',
    'ingredient_groups', jsonb_build_array(jsonb_build_object('name', '',
      'ingredients', jsonb_build_array(jsonb_build_object('name', 'flour', 'quantity', 1, 'unit', 'cup')))),
    'step_groups', jsonb_build_array(jsonb_build_object('name', '',
      'steps', jsonb_build_array(jsonb_build_object('text', 'Bake.'))))
  ));
  select p.display_name into v_name
    from recipes r join profiles p on p.id = r.owner_id where r.id = v_id;
  assert v_name = 'Fixture Clean Kitchen',
    format('a credit line falls back to the publisher, got %s', v_name);

  raise notice 'corpus_import_fixture: import-time cleaning — all assertions passed';
end
$clean$;

-- ============================================================================
-- 7. Units in the house canon (Phase 39, UX-030). `canonical_unit` on the
--    corpus's real spellings, its two invariants over the whole registry, one
--    `import_recipe` call end to end, then the backfill — including that it
--    stamps no `updated_at` — and last, the registry taken away.
--    Needs nutrition_foods.sql loaded (every path that runs this file has it).
-- ============================================================================
do $units$
declare
  v_id    uuid;
  v_units text[];
  v_ing    uuid;
  v_member uuid;
  v_n      int;
begin
  assert exists (select 1 from food_unit where display is not null),
    'the unit canon is not loaded — apply nutrition_foods.sql first';

  -- Invariant units: one spelling at every quantity, any case, any padding.
  assert canonical_unit('tablespoons', 3) = 'tbsp';
  assert canonical_unit('Tbsp', 1) = 'tbsp', 'lookup is case-insensitive';
  assert canonical_unit('TSPS', 2) = 'tsp';
  assert canonical_unit(' teaspoon ', 0.5) = 'tsp', 'lookup ignores padding';
  assert canonical_unit('liters', 2) = 'L', 'the display of key l is L';
  assert canonical_unit('fluid ounces', 8) = 'fl oz';
  assert canonical_unit('pounds', 2) = 'lb';
  -- Word units agree with the quantity; below 1 or none keeps the page's number.
  assert canonical_unit('cup', 3) = 'cups';
  assert canonical_unit('Cups', 1) = 'cup';
  assert canonical_unit('cups', 0.5) = 'cups';
  assert canonical_unit('cup', 0.5) = 'cup';
  assert canonical_unit('cup', null) = 'cup';
  assert canonical_unit('clove', 3) = 'cloves';
  -- Never invents: unknown, deliberately unresolvable, non-English, bare count.
  assert canonical_unit('sprigs', 3) = 'sprigs';
  assert canonical_unit('Handful', 1) = 'Handful', 'an unknown spelling is not even re-cased';
  assert canonical_unit('個', 1) = '個';
  assert canonical_unit('', 2) = '', 'the bare-count marker has no display';
  assert canonical_unit(null, 2) is null;

  -- Over EVERY registered spelling at every quantity class: a fixed point
  -- (the backfill's idempotency rests on it), and the same unit afterwards
  -- (the estimator resolves the rewritten spelling to the same unit_key).
  assert not exists (
    select 1
      from food_unit u
     cross join (values (null::numeric), (0.5), (1), (3)) q(n)
     where u.display is not null
       and canonical_unit(canonical_unit(u.spelling, q.n), q.n)
           is distinct from canonical_unit(u.spelling, q.n)),
    'canonical_unit is not a fixed point on its own output';
  assert not exists (
    select 1
      from food_unit u
     cross join (values (null::numeric), (0.5), (1), (3)) q(n)
     left join food_unit c on c.spelling = lower(canonical_unit(u.spelling, q.n))
     where u.display is not null
       and c.unit_key is distinct from u.unit_key),
    'a canonical spelling resolves to a different unit';

  -- End to end: import_recipe stores the canon, not the page's spelling.
  v_id := import_recipe(jsonb_build_object(
    'source_url', 'https://units.example.test/soup/',
    'entity_slug', 'fixture-units',
    'entity_name', 'Fixture Units Kitchen',
    'entity_kind', 'chef_site',
    'title', 'Fixture Unit Soup',
    'ingredient_groups', jsonb_build_array(jsonb_build_object('name', '',
      'ingredients', jsonb_build_array(
        jsonb_build_object('name', 'olive oil', 'quantity', 3, 'unit', 'tablespoons'),
        jsonb_build_object('name', 'flour', 'quantity', 1, 'unit', 'Cups'),
        jsonb_build_object('name', 'garlic', 'quantity', 2, 'unit', 'clove'),
        jsonb_build_object('name', 'thyme', 'quantity', 3, 'unit', 'sprigs'),
        jsonb_build_object('name', 'milk', 'quantity', 0.5, 'unit', 'cups'),
        jsonb_build_object('name', 'eggs', 'quantity', 2, 'unit', '')))),
    'step_groups', jsonb_build_array(jsonb_build_object('name', '',
      'steps', jsonb_build_array(jsonb_build_object('text', 'Simmer.'))))
  ));
  assert v_id is not null, 'the units fixture imported';
  select array_agg(coalesce(i.unit, '∅') order by i.sort_order) into v_units
    from ingredients i join ingredient_groups g on g.id = i.group_id
   where g.recipe_id = v_id;
  assert v_units = array['tbsp', 'cup', 'cloves', 'sprigs', 'cups', '∅'],
    format('import_recipe stores canonical units, got %s', v_units);

  -- The backfill: a row imported before the canon existed (written directly,
  -- as the pre-Phase-39 importer did), dated in the past with the touch
  -- trigger held off so the date is ours to set.
  select i.id into v_ing
    from ingredients i join ingredient_groups g on g.id = i.group_id
   where g.recipe_id = v_id and i.name = 'olive oil';
  update ingredients set unit = 'Tablespoons' where id = v_ing;
  alter table recipes disable trigger recipes_touch;
  update recipes set updated_at = '2000-01-01T00:00:00Z' where id = v_id;
  alter table recipes enable trigger recipes_touch;

  v_n := canonicalise_imported_units();
  assert v_n >= 1, format('the backfill changed nothing (%s)', v_n);
  assert (select unit from ingredients where id = v_ing) = 'tbsp',
    'the backfill canonicalised the stale row';
  assert (select updated_at from recipes where id = v_id) = '2000-01-01T00:00:00Z'::timestamptz,
    'the backfill stamped updated_at — ingredients_search_tsv_upd was not parked';
  assert canonicalise_imported_units() = 0, 'a second backfill changed rows';
  assert (select tgenabled from pg_trigger
           where tgname = 'ingredients_search_tsv_upd'
             and tgrelid = 'ingredients'::regclass) = 'O',
    'the backfill left the search trigger disabled';

  -- A member's unit is their own text: the backfill touches imported rows only.
  -- Every path that runs this file has the 14 curated recipes to borrow a row
  -- from; the assert says so rather than passing vacuously without one.
  select i.id into v_member
    from ingredients i join ingredient_groups g on g.id = i.group_id
    join recipes r on r.id = g.recipe_id
   where not r.is_imported
   limit 1;
  assert v_member is not null, 'no non-imported ingredient to test the scope with';
  update ingredients set unit = 'Tablespoons' where id = v_member;
  perform canonicalise_imported_units();
  assert (select unit from ingredients where id = v_member) = 'Tablespoons',
    'the backfill rewrote a non-imported recipe''s unit';

  -- A registry from before Phase 39 (no display forms), then none at all:
  -- the canon is absent, so nothing is rewritten and nothing is invented.
  update ingredients set unit = 'Tablespoons' where id = v_ing;
  update food_unit set display = null, plural = null;
  assert canonical_unit('tablespoons', 3) = 'tablespoons', 'no canon, no rewrite';
  assert canonicalise_imported_units() = 0, 'the backfill ran without a canon';
  delete from food_unit;
  assert canonical_unit('Cups', 3) = 'Cups', 'an empty registry is the identity';
  assert canonicalise_imported_units() = 0, 'the backfill ran on an empty registry';
  assert (select unit from ingredients where id = v_ing) = 'Tablespoons';

  raise notice 'corpus_import_fixture: units in the house canon — all assertions passed';
end
$units$;

-- Nothing this file wrote is meant to survive it.
rollback;
