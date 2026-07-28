-- seed.sql — curated public recipes for the Discover page.
--
-- Idempotent + safe to re-run. Recipes are owned by a dedicated
-- "Secret Sauce Kitchen" system account and marked public so they show in
-- Discover. Run this in the Supabase SQL editor, or via `supabase db reset`
-- (which runs this automatically after migrations).

create extension if not exists "pgcrypto";   -- crypt(), gen_salt() for the system user

-- Helper: insert a fully-structured recipe from JSON arrays. No-op if a recipe
-- with the same title already exists for the owner.
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
  p_views       int default 0
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
  if exists (select 1 from recipes where owner_id = p_owner and title = p_title) then
    return; -- already seeded
  end if;

  insert into recipes (
    owner_id, title, description, cuisine, category, difficulty,
    prep_minutes, cook_minutes, servings, visibility, attribution,
    like_count, save_count, view_count
  ) values (
    p_owner, p_title, p_description, p_cuisine, p_category, p_difficulty,
    p_prep, p_cook, p_servings, 'public', p_attribution,
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

  insert into recipe_versions (recipe_id, version_number, author_id, change_summary, content_snapshot)
  values (v_recipe, 1, p_owner, 'Seeded recipe', '{}'::jsonb)
  returning id into v_version;

  update recipes set current_version_id = v_version where id = v_recipe;
end;
$$;

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
    'kitchen@secretsauce.local', crypt('secret-sauce-kitchen', gen_salt('bf')),
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
    128, 74, 940
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
    203, 156, 1520
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
    311, 240, 2100
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
    98, 61, 780
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
    76, 52, 610
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
    412, 358, 3050
  );

  raise notice 'Seed complete for owner %', v_owner;
end $$;
