-- seed.sql — curated public recipes for the Discover page.
--
-- Idempotent + safe to re-run. Recipes are owned by a dedicated
-- "Secret Sauce Kitchen" system account and marked public so they show in
-- Discover. Run this in the Supabase SQL editor, or via `supabase db reset`
-- (which runs this automatically after migrations).

create extension if not exists "pgcrypto";   -- crypt(), gen_salt() for the system user

-- The pool of dummy "taster" accounts that supply star ratings on curated
-- recipes. Fixed ids so re-running the seed updates rather than duplicates.
create or replace function seed_taster_ids()
returns uuid[]
language sql
immutable
as $$
  select array[
    '00000000-0000-0000-0000-0000000000c1',
    '00000000-0000-0000-0000-0000000000c2',
    '00000000-0000-0000-0000-0000000000c3',
    '00000000-0000-0000-0000-0000000000c4',
    '00000000-0000-0000-0000-0000000000c5',
    '00000000-0000-0000-0000-0000000000c6',
    '00000000-0000-0000-0000-0000000000c7',
    '00000000-0000-0000-0000-0000000000c8'
  ]::uuid[];
$$;

-- Helper: apply one rating per taster (in pool order) to a recipe. Idempotent —
-- re-running updates the existing rows. The recipe_ratings trigger recomputes
-- recipes.rating_avg / rating_count from these rows.
create or replace function seed_ratings(p_recipe uuid, p_ratings jsonb)
returns void
language plpgsql
as $$
declare
  v_tasters uuid[] := seed_taster_ids();
  v_item    jsonb;
  v_idx     int := 0;
begin
  for v_item in select * from jsonb_array_elements(coalesce(p_ratings, '[]'::jsonb)) loop
    exit when v_idx >= array_length(v_tasters, 1);
    v_idx := v_idx + 1;
    insert into recipe_ratings (user_id, recipe_id, rating)
    values (v_tasters[v_idx], p_recipe, (v_item #>> '{}')::numeric)
    on conflict (user_id, recipe_id) do update set rating = excluded.rating;
  end loop;
end;
$$;

-- The pool of demo "chef" accounts backing the leaderboard. Fixed ids, one per
-- interesting case (tier ladder, exact threshold, zero engagement, private-only,
-- tied score) — see the table further down.
create or replace function seed_chef_ids()
returns uuid[]
language sql
immutable
as $$
  select array[
    '00000000-0000-0000-0000-0000000000d1',
    '00000000-0000-0000-0000-0000000000d2',
    '00000000-0000-0000-0000-0000000000d3',
    '00000000-0000-0000-0000-0000000000d4',
    '00000000-0000-0000-0000-0000000000d5',
    '00000000-0000-0000-0000-0000000000d6',
    '00000000-0000-0000-0000-0000000000d7'
  ]::uuid[];
$$;

-- Helper: insert a fully-structured recipe from JSON arrays. If a recipe with
-- the same title already exists for the owner, the content is left alone but
-- ratings are still (re)applied, so re-running the seed backfills them.
--
-- NOTE: adding p_visibility changed this function's signature. The previous
-- 16-argument overload is listed in supabase/scripts/drop.sql so `db:drop`
-- removes it instead of leaving two overloads behind.
create or replace function seed_recipe(
  p_owner       uuid,
  p_title       text,
  p_description text,
  p_cuisine     text,
  p_category    text,
  p_difficulty  difficulty,
  p_prep        int,
  p_cook        int,
  p_servings    int,
  p_attribution text,
  p_ingredients jsonb,   -- [{ "qty": "2", "unit": "cups", "name": "flour" }, ...]
  p_steps       jsonb,   -- [{ "text": "...", "duration": "10" }, ...]
  p_likes       int default 0,
  p_saves       int default 0,
  p_views       int default 0,
  p_ratings     jsonb default '[]'::jsonb,  -- [4.5, 5, 4] — one per taster, in order
  p_visibility  recipe_visibility default 'public'
)
returns void
language plpgsql
as $$
declare
  v_recipe  uuid;
  v_ig      uuid;
  v_sg      uuid;
  v_item    jsonb;
  v_idx     int;
  v_version uuid;
begin
  select id into v_recipe from recipes where owner_id = p_owner and title = p_title;
  if v_recipe is not null then
    perform seed_ratings(v_recipe, p_ratings);   -- backfill on an already-seeded DB
    return;
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

  insert into ingredient_groups (recipe_id, name, sort_order)
  values (v_recipe, '', 0) returning id into v_ig;

  v_idx := 0;
  for v_item in select * from jsonb_array_elements(p_ingredients) loop
    insert into ingredients (group_id, quantity, unit, name, sort_order)
    values (
      v_ig,
      nullif(v_item ->> 'qty', '')::numeric,
      nullif(v_item ->> 'unit', ''),
      v_item ->> 'name',
      v_idx
    );
    v_idx := v_idx + 1;
  end loop;

  insert into step_groups (recipe_id, name, sort_order)
  values (v_recipe, '', 0) returning id into v_sg;

  v_idx := 0;
  for v_item in select * from jsonb_array_elements(p_steps) loop
    insert into steps (group_id, step_order, text, duration_minutes, sort_order)
    values (
      v_sg,
      v_idx,
      v_item ->> 'text',
      nullif(v_item ->> 'duration', '')::int,
      v_idx
    );
    v_idx := v_idx + 1;
  end loop;

  perform seed_ratings(v_recipe, p_ratings);

  insert into recipe_versions (recipe_id, version_number, author_id, change_summary, content_snapshot)
  values (v_recipe, 1, p_owner, 'Seeded recipe', '{}'::jsonb)
  returning id into v_version;

  update recipes set current_version_id = v_version where id = v_recipe;
end;
$$;

-- Create the taster accounts (auth user + profile) before any recipe is seeded.
do $$
declare
  v_id uuid;
  v_i  int := 0;
begin
  foreach v_id in array seed_taster_ids() loop
    v_i := v_i + 1;
    insert into auth.users (
      instance_id, id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
      'taster' || v_i || '@secretsauce.local',
      -- Unguessable, never recorded: these accounts exist only to own rows in
      -- recipe_ratings (profiles.id is an FK to auth.users, so a rating needs a
      -- real auth user). Nobody signs in as a taster, and the seed is documented
      -- as safe to run against the hosted project — a literal password here
      -- would be a live, publicly-known credential on production.
      crypt(gen_random_uuid()::text, gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}',
      format('{"display_name":"Taster %s"}', v_i)::jsonb,
      '', '', '', ''
    ) on conflict (id) do nothing;

    -- Explicit upsert: after a `db:drop` the auth user survives, so the
    -- on_auth_user_created trigger will not re-create the profile row.
    insert into profiles (id, display_name)
    values (v_id, 'Taster ' || v_i)
    on conflict (id) do update set display_name = excluded.display_name;
  end loop;
end $$;

-- Curated recipes are owned by a dedicated "Secret Sauce Kitchen" system account
-- so they don't clutter any real user's "My Recipes".
do $$
declare
  v_owner uuid := '00000000-0000-0000-0000-0000000000aa';
begin
  -- Ensure the system auth user exists (profile is auto-created by the
  -- on_auth_user_created trigger; we upsert it below to set the bio).
  insert into auth.users (
    instance_id, id, aud, role, email,
    encrypted_password, email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
    -- Random password, as for the tasters above: this account owns the curated
    -- recipes but is never signed into.
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

  -- 1) Margherita Pizza
  perform seed_recipe(
    v_owner,
    'Classic Margherita Pizza',
    'A blistered, chewy Neapolitan-style pizza with San Marzano tomato, fresh mozzarella, and basil.',
    'Italian', 'Main', 'medium', 30, 12, 2,
    'Traditional Naples pizzeria style.',
    '[
      {"qty":"250","unit":"g","name":"00 pizza flour"},
      {"qty":"160","unit":"ml","name":"warm water"},
      {"qty":"3","unit":"g","name":"active dry yeast"},
      {"qty":"5","unit":"g","name":"salt"},
      {"qty":"150","unit":"g","name":"San Marzano tomatoes, crushed"},
      {"qty":"125","unit":"g","name":"fresh mozzarella, torn"},
      {"qty":"","unit":"","name":"fresh basil leaves"},
      {"qty":"1","unit":"tbsp","name":"extra-virgin olive oil"}
    ]'::jsonb,
    '[
      {"text":"Dissolve the yeast in warm water and let it sit until foamy.","duration":"10"},
      {"text":"Mix flour and salt, add the yeast water, and knead into a smooth dough.","duration":"10"},
      {"text":"Cover and let rise until doubled.","duration":"90"},
      {"text":"Stretch the dough by hand into a thin round; top with crushed tomato and mozzarella."},
      {"text":"Bake in the hottest possible oven until the crust is charred and bubbling.","duration":"10"},
      {"text":"Finish with fresh basil and a drizzle of olive oil."}
    ]'::jsonb,
    128, 74, 940,
    '[5, 4.5, 5, 4.5, 5, 4, 4.5, 5]'::jsonb
  );

  -- 2) Spaghetti Aglio e Olio
  perform seed_recipe(
    v_owner,
    'Spaghetti Aglio e Olio',
    'A five-ingredient Roman classic: garlic and chilli sizzled in good olive oil, tossed with spaghetti.',
    'Italian', 'Main', 'easy', 5, 15, 2,
    'Late-night Roman comfort food.',
    '[
      {"qty":"200","unit":"g","name":"spaghetti"},
      {"qty":"4","unit":"cloves","name":"garlic, thinly sliced"},
      {"qty":"60","unit":"ml","name":"extra-virgin olive oil"},
      {"qty":"1","unit":"tsp","name":"red chilli flakes"},
      {"qty":"","unit":"","name":"flat-leaf parsley, chopped"},
      {"qty":"","unit":"","name":"salt"}
    ]'::jsonb,
    '[
      {"text":"Boil the spaghetti in well-salted water until al dente; reserve a cup of pasta water.","duration":"9"},
      {"text":"Gently warm the olive oil and garlic until the garlic is pale gold — do not brown it.","duration":"4"},
      {"text":"Add chilli flakes and a splash of pasta water to emulsify."},
      {"text":"Toss the drained pasta in the oil, adding pasta water until glossy."},
      {"text":"Finish with parsley and serve immediately."}
    ]'::jsonb,
    203, 156, 1520,
    '[5, 5, 4.5, 5, 4.5, 5, 5, 4.5]'::jsonb
  );

  -- 3) Chicken Tikka Masala
  perform seed_recipe(
    v_owner,
    'Chicken Tikka Masala',
    'Charred marinated chicken simmered in a creamy, spiced tomato gravy. A crowd favourite.',
    'Indian', 'Main', 'medium', 30, 40, 4,
    NULL,
    '[
      {"qty":"600","unit":"g","name":"boneless chicken thigh, cubed"},
      {"qty":"150","unit":"g","name":"plain yoghurt"},
      {"qty":"2","unit":"tbsp","name":"tikka spice blend"},
      {"qty":"1","unit":"","name":"onion, finely diced"},
      {"qty":"3","unit":"cloves","name":"garlic, minced"},
      {"qty":"1","unit":"tbsp","name":"ginger, grated"},
      {"qty":"400","unit":"g","name":"tomato passata"},
      {"qty":"120","unit":"ml","name":"heavy cream"},
      {"qty":"2","unit":"tbsp","name":"butter"}
    ]'::jsonb,
    '[
      {"text":"Marinate the chicken in yoghurt and half the spice blend.","duration":"30"},
      {"text":"Sear or grill the chicken until charred at the edges; set aside.","duration":"8"},
      {"text":"Soften the onion in butter, then add garlic, ginger, and the rest of the spice.","duration":"6"},
      {"text":"Pour in the passata and simmer until deepened in colour.","duration":"15"},
      {"text":"Stir in the cream and return the chicken to warm through.","duration":"8"},
      {"text":"Serve with basmati rice or naan."}
    ]'::jsonb,
    311, 240, 2100,
    '[4.5, 4, 4.5, 5, 4, 4.5, 4, 4]'::jsonb
  );

  -- 4) Fluffy Buttermilk Pancakes
  perform seed_recipe(
    v_owner,
    'Fluffy Buttermilk Pancakes',
    'Tall, tender pancakes with a golden crust — a weekend breakfast staple.',
    'American', 'Breakfast', 'easy', 10, 15, 4,
    NULL,
    '[
      {"qty":"200","unit":"g","name":"all-purpose flour"},
      {"qty":"2","unit":"tbsp","name":"sugar"},
      {"qty":"1","unit":"tsp","name":"baking powder"},
      {"qty":"0.5","unit":"tsp","name":"baking soda"},
      {"qty":"0.5","unit":"tsp","name":"salt"},
      {"qty":"300","unit":"ml","name":"buttermilk"},
      {"qty":"1","unit":"","name":"egg"},
      {"qty":"40","unit":"g","name":"butter, melted"}
    ]'::jsonb,
    '[
      {"text":"Whisk the dry ingredients together in a bowl."},
      {"text":"In another bowl whisk buttermilk, egg, and melted butter."},
      {"text":"Fold wet into dry until just combined — lumps are fine; do not overmix."},
      {"text":"Rest the batter so the leavening activates.","duration":"5"},
      {"text":"Cook ladlefuls on a medium griddle until bubbles form, then flip until golden.","duration":"4"},
      {"text":"Serve stacked with butter and maple syrup."}
    ]'::jsonb,
    98, 61, 780,
    '[4, 3.5, 4, 4.5, 3.5, 4]'::jsonb
  );

  -- 5) Fresh Guacamole
  perform seed_recipe(
    v_owner,
    'Fresh Guacamole',
    'Bright, chunky avocado dip with lime, coriander, and a little heat. Ready in minutes.',
    'Mexican', 'Appetizer', 'easy', 15, 0, 4,
    NULL,
    '[
      {"qty":"3","unit":"","name":"ripe avocados"},
      {"qty":"1","unit":"","name":"lime, juiced"},
      {"qty":"0.5","unit":"","name":"red onion, finely diced"},
      {"qty":"1","unit":"","name":"jalapeño, minced"},
      {"qty":"","unit":"","name":"fresh coriander, chopped"},
      {"qty":"","unit":"","name":"salt to taste"}
    ]'::jsonb,
    '[
      {"text":"Halve the avocados and scoop the flesh into a bowl."},
      {"text":"Mash to your preferred texture — leave it chunky."},
      {"text":"Fold in lime juice, onion, jalapeño, and coriander."},
      {"text":"Season with salt and serve right away with tortilla chips."}
    ]'::jsonb,
    76, 52, 610,
    '[5, 4.5, 4]'::jsonb
  );

  -- 6) Chocolate Chip Cookies
  perform seed_recipe(
    v_owner,
    'Brown Butter Chocolate Chip Cookies',
    'Crisp edges, chewy centres, and pools of dark chocolate, deepened with nutty brown butter.',
    'American', 'Dessert', 'easy', 20, 11, 24,
    'A tweaked take on the classic Toll House cookie.',
    '[
      {"qty":"170","unit":"g","name":"butter"},
      {"qty":"150","unit":"g","name":"brown sugar"},
      {"qty":"100","unit":"g","name":"white sugar"},
      {"qty":"1","unit":"","name":"egg"},
      {"qty":"1","unit":"","name":"egg yolk"},
      {"qty":"1","unit":"tsp","name":"vanilla extract"},
      {"qty":"250","unit":"g","name":"all-purpose flour"},
      {"qty":"0.5","unit":"tsp","name":"baking soda"},
      {"qty":"200","unit":"g","name":"dark chocolate, chopped"}
    ]'::jsonb,
    '[
      {"text":"Brown the butter until it smells nutty, then cool slightly.","duration":"6"},
      {"text":"Whisk in both sugars, the egg, yolk, and vanilla until smooth."},
      {"text":"Fold in the flour and baking soda, then the chopped chocolate."},
      {"text":"Chill the dough for deeper flavour.","duration":"30"},
      {"text":"Scoop onto trays and bake until the edges set but centres look underdone.","duration":"11"},
      {"text":"Cool on the tray so they finish setting."}
    ]'::jsonb,
    412, 358, 3050,
    '[5, 5, 5, 4.5, 5, 5, 4.5, 5]'::jsonb
  );

  raise notice 'Seed complete for owner %', v_owner;
end $$;

-- ============================================================================
-- Demo chefs for the leaderboard (Phase 18)
--
-- chef_score = 3*likes + 5*saves + 0.2*views, over PUBLIC recipes only, and the
-- tiers are inclusive (`>=`). Each account pins one case so a formula or
-- threshold regression is visible immediately:
--
--   id  name              likes  saves  views   score    tier         why
--   d1  Amara Okonkwo      4000   1600   5000   21000    master_chef  >= 20000; split over TWO recipes (tests the sum)
--   d2  Bruno Castellani   1000    400   2500    5500    head_chef    >= 5000
--   d3  Chen Wei            200    100    500     1200   sous_chef    >= 1000
--   d4  Dara Nilsson         20      8      0      100   line_cook    EXACTLY the threshold — proves `>=`
--   d5  Elif Yilmaz           0      0      0        0   home_cook    public recipes, zero engagement — ranked last
--   d6  Farid Haddad          -      -      -        0   home_cook    PRIVATE-only — engagement excluded, absent from the board
--   d7  Greta Lindqvist     100    180      0     1200   sous_chef    ties d3 exactly — proves dense_rank shares a rank
--
-- The existing "Secret Sauce Kitchen" account scores 10189 from the curated
-- recipes above and lands in head_chef with no help. Tasters own nothing, so
-- they are excluded by the public_recipe_count > 0 filter.
--
-- Passwords are randomized exactly like the tasters (B018): seed.sql is
-- documented as safe to run against the hosted project, so a literal password
-- here would be a live, publicly-known production credential.
-- ============================================================================
do $$
declare
  v_names text[] := array[
    'Amara Okonkwo', 'Bruno Castellani', 'Chen Wei', 'Dara Nilsson',
    'Elif Yilmaz', 'Farid Haddad', 'Greta Lindqvist'
  ];
  v_bios text[] := array[
    'Lagos-born, fire-obsessed. Everything tastes better over coals.',
    'Third-generation trattoria cook. Pasta, patience, and good olive oil.',
    'Wok-first home cook documenting family recipes before they are lost.',
    'Nordic baker. Rye, cardamom, and very cold butter.',
    'Just getting started — mostly weeknight food for two.',
    'Keeps the family book closed. Recipes here are for me alone.',
    'Preserving, pickling, fermenting. If it can sit in brine, it will.'
  ];
  v_id uuid;
  v_i  int := 0;
begin
  foreach v_id in array seed_chef_ids() loop
    v_i := v_i + 1;
    insert into auth.users (
      instance_id, id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
      'chef' || v_i || '@secretsauce.local',
      crypt(gen_random_uuid()::text, gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}',
      format('{"display_name":%s}', to_jsonb(v_names[v_i]))::jsonb,
      '', '', '', ''
    ) on conflict (id) do nothing;

    -- Explicit upsert: after a `db:drop` the auth user survives, so the
    -- on_auth_user_created trigger will not re-create the profile row.
    insert into profiles (id, display_name, bio)
    values (v_id, v_names[v_i], v_bios[v_i])
    on conflict (id) do update
      set display_name = excluded.display_name, bio = excluded.bio;
  end loop;
end $$;

do $$
declare
  v_chefs uuid[] := seed_chef_ids();
begin
  -- d1 — master_chef. Two recipes, so the aggregate has to sum across rows.
  perform seed_recipe(
    v_chefs[1], 'Suya-Spiced Lamb Skewers',
    'Thin lamb, heavy on the yaji peanut-chilli rub, cooked hard and fast over coals.',
    'Nigerian', 'Main', 'medium', 25, 10, 4,
    'Roadside suya, Lagos.',
    '[{"qty":"600","unit":"g","name":"lamb leg, sliced thin"},
      {"qty":"60","unit":"g","name":"roasted peanuts, ground"},
      {"qty":"2","unit":"tsp","name":"cayenne"},
      {"qty":"1","unit":"tsp","name":"ginger powder"},
      {"qty":"1","unit":"","name":"onion, sliced, to serve"}]'::jsonb,
    '[{"text":"Blitz peanuts, cayenne, ginger, and salt into a coarse rub."},
      {"text":"Toss the lamb in oil, then coat heavily in the rub.","duration":"5"},
      {"text":"Thread onto skewers and rest so the rub sticks.","duration":"20"},
      {"text":"Grill over high heat, turning once.","duration":"6"},
      {"text":"Serve with raw onion and extra rub."}]'::jsonb,
    2500, 1000, 3000, '[5, 5, 4.5, 5, 5, 4.5]'::jsonb
  );
  perform seed_recipe(
    v_chefs[1], 'Charcoal Jollof Rice',
    'Party jollof with a deliberate layer of smoky bottom-of-the-pot rice.',
    'Nigerian', 'Main', 'hard', 20, 45, 6,
    NULL,
    '[{"qty":"500","unit":"g","name":"long-grain parboiled rice"},
      {"qty":"400","unit":"g","name":"tomato passata"},
      {"qty":"2","unit":"","name":"red bell peppers"},
      {"qty":"1","unit":"","name":"scotch bonnet"},
      {"qty":"120","unit":"ml","name":"groundnut oil"}]'::jsonb,
    '[{"text":"Blend peppers, scotch bonnet, and onion into a smooth base."},
      {"text":"Fry the base in hot oil until it darkens and splits.","duration":"15"},
      {"text":"Add passata and stock; season and simmer.","duration":"10"},
      {"text":"Stir in the rice, cover, and cook on the lowest heat.","duration":"25"},
      {"text":"Raise the heat for the last two minutes to catch the bottom.","duration":"2"},
      {"text":"Rest covered, then fold the smoky layer through."}]'::jsonb,
    1500, 600, 2000, '[5, 4.5, 5, 5]'::jsonb
  );

  -- d2 — head_chef.
  perform seed_recipe(
    v_chefs[2], 'Cacio e Pepe',
    'Pecorino, black pepper, pasta water. Nothing else, and nothing forgiving.',
    'Italian', 'Main', 'medium', 5, 12, 2,
    'Trattoria family recipe, Rome.',
    '[{"qty":"200","unit":"g","name":"tonnarelli"},
      {"qty":"100","unit":"g","name":"pecorino romano, finely grated"},
      {"qty":"2","unit":"tsp","name":"black peppercorns, cracked"}]'::jsonb,
    '[{"text":"Toast the cracked pepper in a dry pan until fragrant.","duration":"2"},
      {"text":"Cook the pasta in minimal water so the water goes starchy.","duration":"8"},
      {"text":"Whisk pecorino with warm pasta water into a smooth cream."},
      {"text":"Toss off the heat — too hot and the cheese splits."},
      {"text":"Serve immediately with more pepper."}]'::jsonb,
    1000, 400, 2500, '[4.5, 5, 4.5, 4, 5]'::jsonb
  );

  -- d3 — sous_chef. Ties exactly with d7 below.
  perform seed_recipe(
    v_chefs[3], 'Tomato and Egg Stir-Fry',
    'The ten-minute dish every Chinese household argues about. Soft egg, sweet-sour tomato.',
    'Chinese', 'Main', 'easy', 5, 8, 2,
    'My mother''s version — a pinch of sugar, no ketchup.',
    '[{"qty":"4","unit":"","name":"eggs"},
      {"qty":"3","unit":"","name":"ripe tomatoes, wedged"},
      {"qty":"1","unit":"tsp","name":"sugar"},
      {"qty":"2","unit":"","name":"spring onions, sliced"}]'::jsonb,
    '[{"text":"Beat the eggs with a little salt and a splash of water."},
      {"text":"Scramble in hot oil until just set; remove while glossy.","duration":"2"},
      {"text":"Fry the tomatoes until they collapse into a sauce.","duration":"4"},
      {"text":"Season with sugar and salt to balance the acid."},
      {"text":"Return the egg, fold once, and finish with spring onion."}]'::jsonb,
    200, 100, 500, '[4.5, 4, 5]'::jsonb
  );

  -- d4 — score is EXACTLY 100 (3*20 + 5*8 + 0.2*0). Any drift in the formula or
  -- a `>` instead of `>=` in chef_tier_for() drops this account to home_cook.
  perform seed_recipe(
    v_chefs[4], 'Cardamom Rye Buns',
    'Dark, chewy rye buns with a heavy hand of freshly ground cardamom.',
    'Swedish', 'Dessert', 'medium', 30, 20, 12,
    NULL,
    '[{"qty":"300","unit":"g","name":"strong white flour"},
      {"qty":"100","unit":"g","name":"rye flour"},
      {"qty":"2","unit":"tbsp","name":"cardamom pods, ground"},
      {"qty":"80","unit":"g","name":"butter, cold"},
      {"qty":"200","unit":"ml","name":"milk"}]'::jsonb,
    '[{"text":"Grind the cardamom fresh — pre-ground is a different spice."},
      {"text":"Mix the doughs and knead until smooth.","duration":"10"},
      {"text":"Prove until doubled.","duration":"60"},
      {"text":"Roll, butter, fold, and twist into knots."},
      {"text":"Bake hot until deep brown.","duration":"14"}]'::jsonb,
    20, 8, 0, '[4, 4.5]'::jsonb
  );

  -- d5 — public recipes, zero engagement: score 0, home_cook, ranked last by the
  -- deterministic tie-break. Two recipes so public_recipe_count > 0 is what keeps
  -- this account on the board, not its score.
  perform seed_recipe(
    v_chefs[5], 'Weeknight Lentil Soup',
    'One pot, pantry ingredients, done before the kettle cools.',
    'British', 'Main', 'easy', 10, 25, 2,
    NULL,
    '[{"qty":"150","unit":"g","name":"red lentils"},
      {"qty":"1","unit":"","name":"onion, diced"},
      {"qty":"2","unit":"","name":"carrots, diced"},
      {"qty":"800","unit":"ml","name":"vegetable stock"}]'::jsonb,
    '[{"text":"Sweat the onion and carrot until soft.","duration":"8"},
      {"text":"Add lentils and stock; simmer until collapsing.","duration":"20"},
      {"text":"Blend half, leave half chunky."},
      {"text":"Season hard — lentils take more salt than you expect."}]'::jsonb,
    0, 0, 0, '[]'::jsonb
  );
  perform seed_recipe(
    v_chefs[5], 'Two-Egg Omelette',
    'The first thing worth learning to cook properly.',
    'French', 'Breakfast', 'easy', 2, 4, 1,
    NULL,
    '[{"qty":"2","unit":"","name":"eggs"},
      {"qty":"15","unit":"g","name":"butter"},
      {"qty":"","unit":"","name":"chives, snipped"}]'::jsonb,
    '[{"text":"Beat the eggs until completely uniform — no streaks."},
      {"text":"Melt butter until foaming but not coloured.","duration":"1"},
      {"text":"Stir constantly for twenty seconds, then let the base set."},
      {"text":"Fold and slide out while the centre is still loose."}]'::jsonb,
    0, 0, 0, '[]'::jsonb
  );

  -- d6 — PRIVATE-only. The engagement below would score 27000 (master_chef) if
  -- private recipes counted; it must contribute nothing, leaving this chef at
  -- score 0 / home_cook and absent from the leaderboard entirely.
  perform seed_recipe(
    v_chefs[6], 'Family Kibbeh (private)',
    'Not for sharing. Written down so it survives, not so it spreads.',
    'Lebanese', 'Main', 'hard', 60, 30, 6,
    'Grandmother''s, Tripoli.',
    '[{"qty":"500","unit":"g","name":"lean lamb"},
      {"qty":"200","unit":"g","name":"fine bulgur"},
      {"qty":"1","unit":"tsp","name":"kibbeh spice blend"},
      {"qty":"1","unit":"","name":"onion, grated"}]'::jsonb,
    '[{"text":"Soak the bulgur until it swells, then squeeze bone dry.","duration":"20"},
      {"text":"Work the lamb, bulgur, onion, and spice into a smooth paste."},
      {"text":"Chill so it firms enough to shape.","duration":"30"},
      {"text":"Shape, stuff, and seal each shell."},
      {"text":"Fry until deep brown and cooked through.","duration":"8"}]'::jsonb,
    5000, 2000, 10000, '[]'::jsonb, 'private'
  );

  -- d7 — score EXACTLY equal to d3 (3*100 + 5*180 = 1200) via a different mix,
  -- so the two share a dense_rank and the display_name tie-break decides order.
  perform seed_recipe(
    v_chefs[7], 'Quick Dill Pickles',
    'Refrigerator pickles that are ready overnight and gone within the week.',
    'Swedish', 'Appetizer', 'easy', 15, 0, 8,
    NULL,
    '[{"qty":"600","unit":"g","name":"small cucumbers"},
      {"qty":"200","unit":"ml","name":"white vinegar"},
      {"qty":"200","unit":"ml","name":"water"},
      {"qty":"2","unit":"tbsp","name":"sugar"},
      {"qty":"","unit":"","name":"dill and mustard seed"}]'::jsonb,
    '[{"text":"Pack the cucumbers tightly with dill and mustard seed."},
      {"text":"Boil vinegar, water, sugar, and salt until dissolved.","duration":"3"},
      {"text":"Cool the brine slightly so the cucumbers stay crisp.","duration":"10"},
      {"text":"Pour over, seal, and refrigerate overnight."}]'::jsonb,
    100, 180, 0, '[4.5, 4.5, 4]'::jsonb
  );

  raise notice 'Chef seed complete (% accounts)', array_length(seed_chef_ids(), 1);
end $$;
