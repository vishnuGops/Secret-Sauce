-- seed_recipes.sql — GENERATED FILE. DO NOT EDIT BY HAND.
--
-- Source: recipeData/recipes/*.json  ·  Generator: tool/recipes.dart
-- Regenerate with `melos run recipes:gen`; `melos run recipes:check`
-- fails if this file is stale.
--
-- Standalone and idempotent: it bootstraps the Secret Sauce Kitchen
-- account itself, so it can be applied before or after supabase/seed.sql,
-- and survives that file being deleted when the demo data is retired.
-- Safe to paste into the hosted SQL editor. Contains no credentials —
-- the kitchen account gets a random password it is never signed in with
-- (B018: never put a literal credential in a file the README tells you
-- to run against production).
--
-- Re-running never edits an existing recipe: seed_recipe_v2 returns early
-- when (owner_id, title) already exists. To push a content change, delete
-- that recipe first — it is not an upsert.

create extension if not exists "pgcrypto";

-- The "Secret Sauce Kitchen" system account that owns every curated recipe, so
-- they never clutter a real user's "My Recipes". Same fixed id as
-- supabase/seed.sql uses; both inserts are conflict-guarded, so either file may
-- run first.
do $owner$
declare
  v_owner uuid := '00000000-0000-0000-0000-0000000000aa';
begin
  insert into auth.users (
    instance_id, id, aud, role, email,
    encrypted_password, email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
    'kitchen@secretsauce.local', crypt(gen_random_uuid()::text, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Secret Sauce Kitchen"}',
    '', '', '', ''
  ) on conflict (id) do nothing;

  insert into profiles (id, display_name, bio)
  values (
    v_owner,
    'Secret Sauce Kitchen',
    'Curated classics from the Secret Sauce test kitchen.'
  )
  on conflict (id) do update
    set display_name = excluded.display_name, bio = excluded.bio;
end $owner$;

-- ---------------------------------------------------------------------------
-- seed_recipe_v2 — insert a fully-structured recipe, groups and all.
--
-- Distinct from seed.sql's flat `seed_recipe`, which collapses everything into
-- one unnamed group. Both can coexist; neither overloads the other.
--
-- B024: `create or replace function` cannot change an argument list, so a
-- signature change leaves the OLD overload alive beside the new one and every
-- call then matches both (`42725 … is not unique`). Drops belong HERE, in the
-- file that recreates the function — drop.sql is a separate destructive script
-- that a plain re-apply never runs. There are no historical signatures to drop
-- yet; when this one changes, add its exact argument list below and keep every
-- earlier entry.
--
--   drop function if exists seed_recipe_v2(<the previous argument list>);
--
-- ---------------------------------------------------------------------------
create or replace function seed_recipe_v2(
  p_owner       uuid,
  p_title       text,
  p_description text,
  p_cuisine     text,
  p_category    text,
  p_difficulty  difficulty,
  p_prep        int,
  p_cook        int,
  p_servings    int,
  p_visibility  recipe_visibility,
  p_attribution text,
  p_ingredients jsonb,   -- [{"name":"Crust","ingredients":[{"quantity":1.25,"unit":"cup","name":"flour","note":null,"is_optional":false}]}]
  p_steps       jsonb,   -- [{"name":"Crust","steps":[{"text":"…","duration_minutes":60,"temperature":"350°F","tip":null}]}]
  p_likes       int   default 0,
  p_saves       int   default 0,
  p_views       int   default 0,
  p_ratings     jsonb default '[]'::jsonb
)
returns void
language plpgsql
as $fn$
declare
  v_recipe  uuid;
  v_group   uuid;
  v_grp     jsonb;
  v_item    jsonb;
  v_gidx    int;
  v_idx     int;
  v_version uuid;
begin
  select id into v_recipe from recipes where owner_id = p_owner and title = p_title;
  if v_recipe is not null then
    perform seed_recipe_v2_ratings(v_recipe, p_ratings);
    return;   -- content is left alone; this is not an upsert
  end if;

  insert into recipes (
    owner_id, title, description, cuisine, category, difficulty,
    prep_minutes, cook_minutes, servings, visibility, attribution,
    like_count, save_count, view_count
  ) values (
    p_owner, p_title, p_description, p_cuisine, p_category, p_difficulty,
    p_prep, p_cook, p_servings, p_visibility, p_attribution,
    p_likes, p_saves, p_views
  ) returning id into v_recipe;

  -- Groups and their children are numbered from 0 WITHIN each group, matching
  -- SupabaseRecipeRepository._persistContent. Numbering steps continuously
  -- across groups would work until the first edit re-persisted them per-group
  -- and silently renumbered every step (the B022 family of problem).
  v_gidx := 0;
  for v_grp in select * from jsonb_array_elements(p_ingredients) loop
    insert into ingredient_groups (recipe_id, name, sort_order)
    values (v_recipe, coalesce(v_grp ->> 'name', ''), v_gidx)
    returning id into v_group;

    v_idx := 0;
    for v_item in select * from jsonb_array_elements(coalesce(v_grp -> 'ingredients', '[]'::jsonb)) loop
      insert into ingredients (group_id, quantity, unit, name, note, is_optional, sort_order)
      values (
        v_group,
        (v_item ->> 'quantity')::numeric,
        v_item ->> 'unit',
        v_item ->> 'name',
        v_item ->> 'note',
        coalesce((v_item ->> 'is_optional')::boolean, false),
        v_idx
      );
      v_idx := v_idx + 1;
    end loop;
    v_gidx := v_gidx + 1;
  end loop;

  v_gidx := 0;
  for v_grp in select * from jsonb_array_elements(p_steps) loop
    insert into step_groups (recipe_id, name, sort_order)
    values (v_recipe, coalesce(v_grp ->> 'name', ''), v_gidx)
    returning id into v_group;

    v_idx := 0;
    for v_item in select * from jsonb_array_elements(coalesce(v_grp -> 'steps', '[]'::jsonb)) loop
      insert into steps (group_id, step_order, text, duration_minutes, temperature, tip, sort_order)
      values (
        v_group,
        v_idx,
        v_item ->> 'text',
        (v_item ->> 'duration_minutes')::int,
        v_item ->> 'temperature',
        v_item ->> 'tip',
        v_idx
      );
      v_idx := v_idx + 1;
    end loop;
    v_gidx := v_gidx + 1;
  end loop;

  perform seed_recipe_v2_ratings(v_recipe, p_ratings);

  insert into recipe_versions (recipe_id, version_number, author_id, change_summary, content_snapshot)
  values (v_recipe, 1, p_owner, 'Seeded recipe', '{}'::jsonb)
  returning id into v_version;

  update recipes set current_version_id = v_version where id = v_recipe;
end
$fn$;

-- Demo ratings are applied through supabase/seed.sql's taster accounts. That
-- file is scheduled for deletion, and this one has to keep working without it,
-- so the call is guarded on the helper still existing rather than declared as a
-- dependency. Also runs on the early-return path above, so a re-seed backfills
-- ratings onto already-seeded recipes (B014).
create or replace function seed_recipe_v2_ratings(p_recipe uuid, p_ratings jsonb)
returns void
language plpgsql
as $fn$
begin
  if p_ratings is null or jsonb_array_length(p_ratings) = 0 then
    return;
  end if;
  if to_regprocedure('seed_ratings(uuid, jsonb)') is null then
    raise notice 'seed_ratings() not present — skipping demo ratings for %', p_recipe;
    return;
  end if;
  execute 'select seed_ratings($1, $2)' using p_recipe, p_ratings;
end
$fn$;

-- PostgREST exposes every function in `public` as an RPC, and both of these
-- write rows. Invoker-rights (so RLS still applies) AND execute revoked, per
-- the trigger-rights rule in CLAUDE.md.
do $grants$
begin
  execute 'revoke execute on function seed_recipe_v2(uuid, text, text, text, text, difficulty, int, int, int, recipe_visibility, text, jsonb, jsonb, int, int, int, jsonb) from public';
  execute 'revoke execute on function seed_recipe_v2_ratings(uuid, jsonb) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function seed_recipe_v2(uuid, text, text, text, text, difficulty, int, int, int, recipe_visibility, text, jsonb, jsonb, int, int, int, jsonb) from anon, authenticated';
    execute 'revoke execute on function seed_recipe_v2_ratings(uuid, jsonb) from anon, authenticated';
  end if;
end $grants$;


-- ---------------------------------------------------------------------------
-- The recipes. 9 of them, ordered by slug.
-- ---------------------------------------------------------------------------
do $seed$
declare
  v_owner uuid := '00000000-0000-0000-0000-0000000000aa';
begin

  -- blueberry-nectarine-galette.json
  perform seed_recipe_v2(
    v_owner,
    $sr$Blueberry Nectarine Galette$sr$,
    $sr$A free-form summer tart on a shop-bought crust — nectarines and blueberries, pleated by hand, chilled hard before it bakes so the edges hold.$sr$,
    $sr$American$sr$, $sr$Dessert$sr$, 'easy',
    20, 35, 8, 'public',
    $sr$Secret Sauce Kitchen$sr$,
    $sr$[{"name":"Filling","ingredients":[{"quantity":2,"unit":null,"name":"nectarines","note":"chopped","is_optional":false},{"quantity":1.5,"unit":"cup","name":"fresh blueberries","note":null,"is_optional":false},{"quantity":0.5,"unit":"Tbsp","name":"lemon zest","note":null,"is_optional":false},{"quantity":1,"unit":"Tbsp","name":"fresh lemon juice","note":null,"is_optional":false},{"quantity":0.25,"unit":"cup","name":"organic cane sugar","note":"adjust to the sweetness of the fruit","is_optional":false},{"quantity":2,"unit":"Tbsp","name":"cornstarch","note":null,"is_optional":false}]},{"name":"To assemble","ingredients":[{"quantity":1,"unit":null,"name":"refrigerated pie crust","note":null,"is_optional":false},{"quantity":1,"unit":null,"name":"egg","note":"beaten with 1 Tbsp water, for egg wash","is_optional":false},{"quantity":null,"unit":null,"name":"turbinado sugar","note":"for garnish","is_optional":false}]}]$sr$::jsonb,
    $sr$[{"name":"","steps":[{"text":"Preheat the oven to 400°F.","duration_minutes":null,"temperature":"400°F","tip":null},{"text":"In a bowl, mix together the nectarines, blueberries, lemon juice, lemon zest, sugar, and cornstarch.","duration_minutes":null,"temperature":null,"tip":null},{"text":"Unroll the pie crust, flattening it with a rolling pin if needed to remove creases. It should be about 1/8-inch thick and 10-12 inches across. Place it on parchment paper on a large rimmed baking sheet.","duration_minutes":null,"temperature":null,"tip":null},{"text":"Using a slotted spoon, pile the fruit onto the centre of the crust and spread it into an even layer, leaving a 2-3 inch border.","duration_minutes":null,"temperature":null,"tip":"The slotted spoon matters — the juice left behind in the bowl is what would otherwise soak through the base."},{"text":"Fold the edges of the dough over the fruit, pleating as you go and pinching each fold gently to seal it.","duration_minutes":null,"temperature":null,"tip":null},{"text":"Chill the assembled galette on its baking sheet in the freezer.","duration_minutes":15,"temperature":null,"tip":"Cold dough hits the hot oven and sets before it can slump."},{"text":"Brush the galette with the egg wash, sprinkle with turbinado sugar, and bake on the centre rack until golden brown and the filling is bubbling. Serve warm with vanilla ice cream.","duration_minutes":35,"temperature":"400°F","tip":null}]}]$sr$::jsonb,
    0, 0, 0,
    $sr$[]$sr$::jsonb
  );

  -- classic-margarita.json
  perform seed_recipe_v2(
    v_owner,
    $sr$Classic Margarita$sr$,
    $sr$Fresh lime, a little orange, and a simple syrup you make yourself so you can dial the sweetness to the fruit. Shaken, served over ice.

Mocktail: replace the tequila and orange liqueur with 6 oz lime sparkling water and a squeeze of lemon.$sr$,
    $sr$Mexican$sr$, $sr$Drink$sr$, 'easy',
    5, 12, 2, 'public',
    $sr$Secret Sauce Kitchen$sr$,
    $sr$[{"name":"Simple syrup","ingredients":[{"quantity":0.5,"unit":"cup","name":"organic granulated cane sugar","note":null,"is_optional":false},{"quantity":0.5,"unit":"cup","name":"filtered water","note":null,"is_optional":false}]},{"name":"Margarita","ingredients":[{"quantity":4,"unit":null,"name":"limes","note":"juiced, about 4 oz","is_optional":false},{"quantity":1,"unit":null,"name":"orange","note":"juiced, about 2 oz","is_optional":false},{"quantity":4,"unit":"oz","name":"tequila blanco","note":null,"is_optional":false},{"quantity":2,"unit":"oz","name":"orange liqueur","note":null,"is_optional":false},{"quantity":null,"unit":null,"name":"ice","note":null,"is_optional":false}]}]$sr$::jsonb,
    $sr$[{"name":"","steps":[{"text":"In a small saucepan, stir the sugar and water together over medium-high heat. Bring to a low boil, reduce to medium-low, and simmer until the syrup is slightly thickened. Let it cool and store it sealed in the fridge until you need it.","duration_minutes":12,"temperature":"medium-low","tip":"Makes more than this recipe uses; it keeps for a month."},{"text":"Pour the lime juice, orange juice, simple syrup to taste, tequila, and orange liqueur into a shaker with ice. Shake until the outside frosts, then divide between two 12 oz glasses over fresh ice.","duration_minutes":null,"temperature":null,"tip":"Sweeten last — how much syrup it takes depends entirely on the limes."}]}]$sr$::jsonb,
    0, 0, 0,
    $sr$[]$sr$::jsonb
  );

  -- easy-guacamole.json
  perform seed_recipe_v2(
    v_owner,
    $sr$Easy Guacamole$sr$,
    $sr$Chunky guacamole with cherry tomatoes and a whole jalapeño — mashed to whatever texture you like and on the table in ten minutes.$sr$,
    $sr$Mexican$sr$, $sr$Appetizer$sr$, 'easy',
    10, 0, 4, 'public',
    $sr$Secret Sauce Kitchen$sr$,
    $sr$[{"name":"","ingredients":[{"quantity":2,"unit":null,"name":"ripe avocados","note":"halved and pitted","is_optional":false},{"quantity":0.25,"unit":"cup","name":"red onion","note":"finely chopped","is_optional":false},{"quantity":1,"unit":"cup","name":"cherry tomatoes","note":"quartered","is_optional":false},{"quantity":2,"unit":"Tbsp","name":"cilantro","note":"chopped","is_optional":false},{"quantity":1,"unit":null,"name":"jalapeño","note":"finely chopped","is_optional":false},{"quantity":3,"unit":"cloves","name":"garlic","note":"minced","is_optional":false},{"quantity":2,"unit":"Tbsp","name":"fresh lime juice","note":null,"is_optional":false},{"quantity":0.5,"unit":"tsp","name":"salt","note":null,"is_optional":false},{"quantity":0.5,"unit":"tsp","name":"pepper","note":null,"is_optional":false}]}]$sr$::jsonb,
    $sr$[{"name":"","steps":[{"text":"Scoop the avocado into a medium bowl and mash with a fork to the consistency you want.","duration_minutes":null,"temperature":null,"tip":"Stop while there are still lumps — this is not a dip you want smooth."},{"text":"Fold in the remaining ingredients until combined, then taste and adjust the salt and lime. Serve with tortilla chips.","duration_minutes":null,"temperature":null,"tip":null}]}]$sr$::jsonb,
    0, 0, 0,
    $sr$[]$sr$::jsonb
  );

  -- raspberry-brownies.json
  perform seed_recipe_v2(
    v_owner,
    $sr$Raspberry Brownies$sr$,
    $sr$Deep cocoa brownies with whole raspberries folded through, so they collapse into jammy pockets as they bake. Makes 16 from an 8-inch square pan.$sr$,
    $sr$American$sr$, $sr$Dessert$sr$, 'easy',
    15, 35, 16, 'public',
    $sr$Secret Sauce Kitchen$sr$,
    $sr$[{"name":"","ingredients":[{"quantity":0.5,"unit":"cup","name":"butter","note":"plus more for the pan","is_optional":false},{"quantity":0.75,"unit":"cup","name":"unsweetened cocoa powder","note":null,"is_optional":false},{"quantity":0.5,"unit":"cup","name":"granulated cane sugar","note":null,"is_optional":false},{"quantity":0.5,"unit":"cup","name":"brown sugar","note":null,"is_optional":false},{"quantity":2,"unit":null,"name":"eggs","note":"beaten","is_optional":false},{"quantity":1,"unit":"tsp","name":"vanilla","note":null,"is_optional":false},{"quantity":0.75,"unit":"cup","name":"unbleached wheat flour","note":null,"is_optional":false},{"quantity":6,"unit":"oz","name":"fresh raspberries","note":null,"is_optional":false},{"quantity":0.5,"unit":"cup","name":"chocolate chips","note":null,"is_optional":true}]}]$sr$::jsonb,
    $sr$[{"name":"","steps":[{"text":"Preheat the oven to 350°F and grease an 8-inch square baking dish with butter or cooking spray.","duration_minutes":null,"temperature":"350°F","tip":null},{"text":"In a 2-quart pot, melt the butter over medium heat and whisk in the cocoa powder until smooth. Remove from the heat and let it cool slightly.","duration_minutes":null,"temperature":"medium","tip":"Cool it before the eggs go in, or they scramble."},{"text":"In a bowl, mix the cocoa and butter mixture with both sugars, the eggs, and the vanilla until smooth. Stir in the flour until just combined, then fold in the raspberries and chocolate chips.","duration_minutes":null,"temperature":null,"tip":null},{"text":"Scrape the batter into the prepared dish and bake until a tester comes out with fudgy crumbs.","duration_minutes":35,"temperature":"350°F","tip":"A clean tester means you have gone too far — pull them while the centre still looks underdone."}]}]$sr$::jsonb,
    0, 0, 0,
    $sr$[]$sr$::jsonb
  );

  -- rustic-ratatouille.json
  perform seed_recipe_v2(
    v_owner,
    $sr$Rustic Ratatouille$sr$,
    $sr$Not the layered kind — the vegetables are roasted hard first, then baked together so they collapse into each other. Serve over pasta or polenta.$sr$,
    $sr$French$sr$, $sr$Main$sr$, 'easy',
    20, 55, 3, 'public',
    $sr$Secret Sauce Kitchen$sr$,
    $sr$[{"name":"","ingredients":[{"quantity":2,"unit":"Tbsp","name":"olive oil","note":"divided","is_optional":false},{"quantity":1,"unit":null,"name":"eggplant","note":null,"is_optional":false},{"quantity":2,"unit":null,"name":"zucchini","note":"small","is_optional":false},{"quantity":1,"unit":null,"name":"red bell pepper","note":null,"is_optional":false},{"quantity":1,"unit":"pint","name":"cherry tomatoes","note":null,"is_optional":false},{"quantity":0.5,"unit":"tsp","name":"kosher salt","note":null,"is_optional":false},{"quantity":0.25,"unit":"tsp","name":"black pepper","note":null,"is_optional":false},{"quantity":1,"unit":null,"name":"yellow onion","note":"chopped","is_optional":false},{"quantity":4,"unit":"cloves","name":"garlic","note":"minced","is_optional":false},{"quantity":0.5,"unit":"bunch","name":"basil","note":"chopped","is_optional":false},{"quantity":null,"unit":null,"name":"salt and pepper","note":"to taste","is_optional":false},{"quantity":null,"unit":null,"name":"hot cooked pasta, polenta, or crusty bread","note":"for serving","is_optional":false}]}]$sr$::jsonb,
    $sr$[{"name":"Roast","steps":[{"text":"Preheat the oven to 425°F and line a large rimmed baking sheet with foil or a silicone mat.","duration_minutes":null,"temperature":"425°F","tip":null},{"text":"Cut the eggplant, zucchini, and bell pepper into chunks and put them in a bowl with the whole cherry tomatoes. Toss with 1 1/2 Tbsp of the olive oil, the kosher salt, and the black pepper, then spread out in a single layer on the prepared sheet.","duration_minutes":null,"temperature":null,"tip":null},{"text":"Roast until the vegetables are tender and browning at the edges.","duration_minutes":20,"temperature":"425°F","tip":"A single layer with room between the pieces is the difference between roasting and steaming."}]},{"name":"Bake","steps":[{"text":"Heat the remaining 1/2 Tbsp olive oil in a heavy-bottomed, oven-going pot over medium heat. Cook the onion until softened and translucent, about 5 minutes, then add the garlic and cook one minute more. Add the roasted vegetables and mix everything together, gently smashing the tomatoes with the back of a spoon to release their juices.","duration_minutes":6,"temperature":"medium","tip":null},{"text":"Reduce the oven to 375°F and bake the ratatouille. Stir in the chopped basil, season to taste, and serve over hot pasta or polenta, or with crusty bread.","duration_minutes":30,"temperature":"375°F","tip":null}]}]$sr$::jsonb,
    0, 0, 0,
    $sr$[]$sr$::jsonb
  );

  -- shirazi-salad.json
  perform seed_recipe_v2(
    v_owner,
    $sr$Shirazi Salad$sr$,
    $sr$The Persian table salad — cucumber, tomato, and onion in a fine dice, brightened with lemon and dill. No cooking, and better after an hour in the fridge.$sr$,
    $sr$Persian$sr$, $sr$Salad$sr$, 'easy',
    15, 0, 4, 'public',
    $sr$Secret Sauce Kitchen$sr$,
    $sr$[{"name":"","ingredients":[{"quantity":4,"unit":null,"name":"Persian cucumbers","note":"1/2-inch dice; or 2 green cucumbers, peeled and seeded","is_optional":false},{"quantity":1,"unit":"pint","name":"cherry tomatoes","note":"quartered","is_optional":false},{"quantity":0.5,"unit":"cup","name":"red onion","note":"chopped","is_optional":false},{"quantity":2,"unit":"Tbsp","name":"fresh dill","note":"chopped; cilantro, parsley, mint, or basil all work","is_optional":false},{"quantity":1,"unit":"Tbsp","name":"olive oil","note":null,"is_optional":false},{"quantity":1,"unit":"Tbsp","name":"golden balsamic vinegar","note":null,"is_optional":true},{"quantity":1,"unit":null,"name":"lemon","note":"zest and juice","is_optional":false},{"quantity":2,"unit":"cloves","name":"garlic","note":"large, smashed and minced","is_optional":false},{"quantity":null,"unit":null,"name":"salt and pepper","note":"to taste","is_optional":false}]}]$sr$::jsonb,
    $sr$[{"name":"","steps":[{"text":"Toss all of the ingredients together in a large bowl. Taste and adjust the seasoning.","duration_minutes":null,"temperature":null,"tip":"Dice everything to roughly the same size — that is what makes this salad read as one thing rather than a bowl of parts."},{"text":"Cover and refrigerate to let the flavours get to know each other.","duration_minutes":60,"temperature":null,"tip":null}]}]$sr$::jsonb,
    0, 0, 0,
    $sr$[]$sr$::jsonb
  );

  -- spring-vegetable-tart.json
  perform seed_recipe_v2(
    v_owner,
    $sr$Spring Vegetable Tart$sr$,
    $sr$A flaky all-butter crust filled with sweet leeks, crisp prosciutto, peas, and three cheeses, finished with a fan of asparagus. Makes one 9-inch tart.$sr$,
    $sr$French$sr$, $sr$Main$sr$, 'medium',
    30, 55, 8, 'public',
    $sr$Secret Sauce Kitchen$sr$,
    $sr$[{"name":"Crust","ingredients":[{"quantity":1.25,"unit":"cup","name":"organic unbleached wheat flour","note":null,"is_optional":false},{"quantity":0.5,"unit":"tsp","name":"kosher salt","note":null,"is_optional":false},{"quantity":6,"unit":"Tbsp","name":"butter","note":"cold, cut into 1/2-inch cubes","is_optional":false},{"quantity":3,"unit":"Tbsp","name":"ice water","note":"start with 2 Tbsp and add as needed","is_optional":false}]},{"name":"Filling","ingredients":[{"quantity":2,"unit":"Tbsp","name":"butter","note":null,"is_optional":false},{"quantity":1,"unit":null,"name":"yellow onion","note":"chopped","is_optional":false},{"quantity":1,"unit":null,"name":"leek","note":"large, thinly sliced, tough leaves removed","is_optional":false},{"quantity":2,"unit":"cloves","name":"garlic","note":"smashed and minced","is_optional":false},{"quantity":1,"unit":"pkg","name":"prosciutto","note":"thinly sliced","is_optional":false},{"quantity":0.5,"unit":"cup","name":"peas","note":null,"is_optional":false},{"quantity":0.5,"unit":"cup","name":"parmesan","note":"shredded","is_optional":false},{"quantity":0.5,"unit":"cup","name":"Gruyère","note":"shredded","is_optional":false},{"quantity":0.25,"unit":"cup","name":"smoked Gouda","note":"shredded","is_optional":false},{"quantity":1,"unit":"tsp","name":"poultry seasoning","note":null,"is_optional":false},{"quantity":null,"unit":null,"name":"salt and pepper","note":"to taste","is_optional":false},{"quantity":2,"unit":null,"name":"eggs","note":null,"is_optional":false},{"quantity":0.5,"unit":"cup","name":"whole milk","note":null,"is_optional":false}]},{"name":"To assemble","ingredients":[{"quantity":1,"unit":"Tbsp","name":"Dijon mustard","note":null,"is_optional":false},{"quantity":0.5,"unit":"bunch","name":"asparagus","note":"trimmed","is_optional":false}]}]$sr$::jsonb,
    $sr$[{"name":"Crust","steps":[{"text":"Mix the flour and kosher salt. Using a pastry cutter, blend in the cold butter until the dough gathers into small pea-sized clumps. Add the ice water 1 or 2 tablespoons at a time until the dough forms a ball, then gently form it into a thick, even disk.","duration_minutes":null,"temperature":null,"tip":"Stop as soon as it holds together — worked dough turns tough."},{"text":"Wrap the disk in plastic wrap and refrigerate.","duration_minutes":60,"temperature":null,"tip":"Overnight is better if you have the time."},{"text":"Preheat the oven to 350°F. Roll out the crust and gently fit it into the tart pan. Roll over the top with a rolling pin to trim the edges, then dock the crust all over with a fork.","duration_minutes":null,"temperature":"350°F","tip":null},{"text":"Blind-bake the crust until set and lightly coloured.","duration_minutes":20,"temperature":"350°F","tip":null}]},{"name":"Filling","steps":[{"text":"In a large skillet, heat 2 Tbsp butter over medium heat. Fry the onion until translucent and beginning to soften, about 5 minutes. Add the leek and garlic and continue cooking until the leek is tender, another 5-7 minutes. Remove to a medium bowl.","duration_minutes":12,"temperature":"medium","tip":null},{"text":"In the same skillet, fry the prosciutto over medium heat until brown and crisp, then mix it into the leek mixture.","duration_minutes":2,"temperature":"medium","tip":null},{"text":"Add the peas, parmesan, Gruyère, Gouda, poultry seasoning, salt, and pepper to the vegetables. Whisk the eggs and milk together and stir those in as well.","duration_minutes":null,"temperature":null,"tip":null}]},{"name":"Assemble and bake","steps":[{"text":"Brush the bottom and sides of the pre-baked crust with Dijon mustard, add the filling, and top with the asparagus.","duration_minutes":null,"temperature":null,"tip":"The mustard layer keeps the crust from going soggy under the custard."},{"text":"Bake until the filling is set and the crust is golden. Serve warm.","duration_minutes":35,"temperature":"350°F","tip":null}]}]$sr$::jsonb,
    0, 0, 0,
    $sr$[]$sr$::jsonb
  );

  -- teriyaki-pork-pineapple-skewers.json
  perform seed_recipe_v2(
    v_owner,
    $sr$Teriyaki Pork & Pineapple Skewers$sr$,
    $sr$Pork and pineapple charred on the grill and brushed with a teriyaki glaze you reduce yourself — mirin, tamari, honey, ginger, and enough chilli to keep it from being sweet.$sr$,
    $sr$Japanese$sr$, $sr$Main$sr$, 'medium',
    25, 15, 4, 'public',
    $sr$Secret Sauce Kitchen$sr$,
    $sr$[{"name":"Teriyaki sauce","ingredients":[{"quantity":0.5,"unit":"cup","name":"mirin","note":null,"is_optional":false},{"quantity":0.5,"unit":"cup","name":"pineapple juice","note":"orange juice also works","is_optional":false},{"quantity":0.25,"unit":"cup","name":"tamari","note":null,"is_optional":false},{"quantity":3,"unit":"Tbsp","name":"honey","note":null,"is_optional":false},{"quantity":1,"unit":"Tbsp","name":"rice vinegar","note":null,"is_optional":false},{"quantity":2,"unit":"cloves","name":"garlic","note":"grated","is_optional":false},{"quantity":1,"unit":"inch","name":"fresh ginger","note":"grated","is_optional":false},{"quantity":1,"unit":"tsp","name":"red pepper flakes","note":"or to taste","is_optional":false},{"quantity":1,"unit":"tsp","name":"cornstarch","note":null,"is_optional":false},{"quantity":1,"unit":"Tbsp","name":"water","note":null,"is_optional":false}]},{"name":"Pork and skewers","ingredients":[{"quantity":1,"unit":"lb","name":"pork","note":"cut for kabobs","is_optional":false},{"quantity":1,"unit":"Tbsp","name":"olive oil","note":null,"is_optional":false},{"quantity":2,"unit":"tsp","name":"tamari","note":null,"is_optional":false},{"quantity":1,"unit":"tsp","name":"smoked paprika","note":null,"is_optional":false},{"quantity":null,"unit":null,"name":"salt and black pepper","note":"to taste","is_optional":false},{"quantity":1,"unit":null,"name":"pineapple","note":"small, skin and core removed","is_optional":false},{"quantity":1,"unit":null,"name":"red bell pepper","note":"stemmed and seeded","is_optional":false},{"quantity":1,"unit":null,"name":"yellow onion","note":null,"is_optional":false},{"quantity":6,"unit":null,"name":"bamboo skewers","note":"4-6, soaked in water at least 30 minutes","is_optional":false}]}]$sr$::jsonb,
    $sr$[{"name":"Teriyaki sauce","steps":[{"text":"In a small saucepan, whisk together the mirin, pineapple juice, tamari, honey, rice vinegar, garlic, ginger, and red pepper flakes. Bring to a low boil, reduce the heat to medium, and simmer until slightly reduced.","duration_minutes":10,"temperature":"medium","tip":null},{"text":"In a small bowl, whisk together the cornstarch and water, then whisk that into the sauce. Cook and stir until thickened and bubbly.","duration_minutes":2,"temperature":null,"tip":"Mix the slurry with cold water and add it off a hard boil, or it seizes into lumps."}]},{"name":"Skewers","steps":[{"text":"Pat the pork dry and cut it into 1 1/2-inch cubes if needed. Sprinkle with salt, black pepper, smoked paprika, and tamari, then toss with the olive oil to coat.","duration_minutes":null,"temperature":null,"tip":null},{"text":"Set the pork aside to marinate.","duration_minutes":30,"temperature":null,"tip":null},{"text":"Cut the pineapple, bell pepper, and yellow onion into 1 1/2-inch pieces, then load them onto the soaked skewers alternating with the pork.","duration_minutes":null,"temperature":null,"tip":null},{"text":"Grill or broil on high, brushing with the teriyaki sauce and turning every 3-5 minutes, until the pork is cooked through and lacquered.","duration_minutes":15,"temperature":"high","tip":"Keep back some sauce for serving — anything that touched raw pork goes on the grill, not the table."}]}]$sr$::jsonb,
    0, 0, 0,
    $sr$[]$sr$::jsonb
  );

  -- tuna-fishcakes.json
  perform seed_recipe_v2(
    v_owner,
    $sr$Tuna Fishcakes$sr$,
    $sr$Pantry fishcakes that come together in under half an hour — panko and parmesan for structure, lemon and smoked paprika for lift. Makes 6 cakes.

Form larger patties instead of six small ones and serve them on buns as fish burgers.$sr$,
    $sr$American$sr$, $sr$Main$sr$, 'easy',
    15, 10, 2, 'public',
    $sr$Secret Sauce Kitchen$sr$,
    $sr$[{"name":"","ingredients":[{"quantity":1,"unit":"pouch","name":"tuna","note":"3 oz pouch or 5 oz can, drained","is_optional":false},{"quantity":1,"unit":"Tbsp","name":"butter","note":null,"is_optional":false},{"quantity":0.5,"unit":"cup","name":"yellow onion","note":"minced","is_optional":false},{"quantity":2,"unit":"cloves","name":"garlic","note":"minced","is_optional":false},{"quantity":0.5,"unit":"cup","name":"panko bread crumbs","note":null,"is_optional":false},{"quantity":0.25,"unit":"cup","name":"parmesan","note":"grated","is_optional":false},{"quantity":2,"unit":null,"name":"mini sweet peppers","note":"1/4-inch dice","is_optional":false},{"quantity":2,"unit":null,"name":"green onions","note":"minced","is_optional":false},{"quantity":1,"unit":null,"name":"egg","note":null,"is_optional":false},{"quantity":1,"unit":"Tbsp","name":"lemon juice","note":null,"is_optional":false},{"quantity":1,"unit":null,"name":"lemon","note":"zest only","is_optional":false},{"quantity":0.5,"unit":"tsp","name":"kosher salt","note":null,"is_optional":false},{"quantity":0.25,"unit":"tsp","name":"black pepper","note":null,"is_optional":false},{"quantity":0.5,"unit":"tsp","name":"smoked paprika","note":null,"is_optional":false},{"quantity":0.25,"unit":"tsp","name":"garlic powder","note":null,"is_optional":false},{"quantity":null,"unit":null,"name":"oil","note":"for frying","is_optional":false}]}]$sr$::jsonb,
    $sr$[{"name":"","steps":[{"text":"In a small skillet, heat the butter over medium heat. Cook the yellow onion and garlic until translucent and fragrant.","duration_minutes":5,"temperature":"medium","tip":null},{"text":"Add every remaining ingredient except the frying oil to a large bowl, including the cooked onion and garlic. Mix well.","duration_minutes":null,"temperature":null,"tip":null},{"text":"Using a 1/4 cup measuring cup, scoop up the mixture and form it into patties about 1/2-inch thick.","duration_minutes":null,"temperature":null,"tip":"Press firmly — loosely packed cakes fall apart in the pan."},{"text":"Heat oil in a cast iron skillet over medium heat and cook the fishcakes until golden, 1-2 minutes per side. Sprinkle with salt and serve hot with your favourite dipping sauce.","duration_minutes":4,"temperature":"medium","tip":null}]}]$sr$::jsonb,
    0, 0, 0,
    $sr$[]$sr$::jsonb
  );
  raise notice 'Recipe seed complete (% authored recipes)', 9;
end $seed$;

