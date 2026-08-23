-- 0_sim_schema.sql — the `sim` schema: config, personas, presets, registries,
-- and the deterministic random helpers the generator draws from.
--
-- Idempotent and standalone. Creates nothing in `public`.
--
-- WHY A SEPARATE SCHEMA. Supabase exposes `public` to PostgREST, so every
-- function placed there becomes a callable RPC by default — that is B026, and
-- `seed.sql` carries a whole `revoke` block to undo it. A schema PostgREST does
-- not know about makes the same guarantee by construction, and cannot be
-- forgotten when someone adds the next helper.
--
-- WHY HASHING, NOT random(). `setseed()` + `random()` is reproducible only for a
-- fixed evaluation order, which a plan change or a parallel scan silently
-- breaks. Every draw here is a pure function of the row's own key, so the same
-- seed produces the same database no matter how Postgres decides to execute it.
--
-- Run order:  0_sim_schema -> 1_sim_dishes -> 2_sim_generate -> 3_sim_verify
-- Teardown:   9_sim_teardown

create extension if not exists "pgcrypto";
create schema if not exists sim;

-- Belt and braces; `sim` is not in Supabase's exposed schema list anyway.
do $grants$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema sim from anon, authenticated';
  end if;
end $grants$;

-- ============================================================================
-- Config
-- ============================================================================

create table if not exists sim.config (
  key   text primary key,
  value text not null
);

insert into sim.config (key, value) values
  ('seed', '20260820'),
  ('preset', 'medium'),
  -- false: simulated users engage ONLY with simulated recipes, so the counters
  -- on the Kitchen's 14 recipes and on d1-d7 stay byte-identical and every
  -- standing pinned in docs/SDS.md §10.7 remains reproducible with the sim
  -- applied. Turning this on routes through sim.counter_baseline so it stays
  -- idempotent, but it does invalidate that table.
  ('engage_existing', 'false'),
  -- How sharply forks concentrate on the recipes people actually read. 0 makes
  -- a fork source a uniform draw among everything older; 1 weights it by the
  -- recipe's own reach; 2 — the default — squares that. See sim.fork_bias().
  ('fork_bias', '2.0')
on conflict (key) do nothing;

create or replace function sim.cfg(p_key text, p_default text default null)
returns text language sql stable as $$
  select coalesce((select value from sim.config where key = p_key), p_default);
$$;

create or replace function sim.seed()
returns bigint language sql stable as $$
  select sim.cfg('seed', '20260820')::bigint;
$$;

-- Exponent applied to a recipe's reach when a fork picks its source (§5 of
-- 2_sim_generate.sql).
--
-- A fork means "I read this and wanted my own version of it", so the source is
-- not a uniform draw: it is weighted by how widely the recipe was read in the
-- first place. The exponent is above 1 because those two effects COMPOUND —
-- being read is already popularity-weighted, and wanting to rewrite what you
-- read is popularity-weighted again on top.
--
-- It is a knob rather than a literal because it is the only thing that decides
-- whether Discover's MOST FORKED shelf ranks anything. Measured at the medium
-- preset, seed 20260820, the same 74 forks either way:
--
--   fork_bias = 0    54 distinct sources, most-forked recipe has  2
--   fork_bias = 2.0  28 distinct sources, most-forked recipe has 10 (then 5, 5, 3…)
--
-- Both fill a 20-card shelf; only the second one ORDERS it. Check G3 in
-- 3_sim_verify.sql asserts a maximum of 3+, which the uniform draw fails.
create or replace function sim.fork_bias()
returns double precision language sql stable as $$
  select sim.cfg('fork_bias', '2.0')::double precision;
$$;

-- ============================================================================
-- Deterministic draws
--
-- sim.rand(key, stream) is the only source of randomness. `key` identifies the
-- row (e.g. 'actor:412'), `stream` identifies what is being decided ('persona',
-- 'signup'), so two decisions about the same row never correlate.
-- ============================================================================

create or replace function sim.rand(p_key text, p_stream text)
returns double precision language sql stable as $$
  select (abs(hashtextextended(p_stream || '|' || p_key, sim.seed())) % 2147483647)::double precision
       / 2147483647.0;
$$;

create or replace function sim.rand_int(p_key text, p_stream text, p_lo int, p_hi int)
returns int language sql stable as $$
  select p_lo + floor(sim.rand(p_key, p_stream) * (p_hi - p_lo + 1))::int;
$$;

create or replace function sim.rand_bool(p_key text, p_stream text, p_p double precision)
returns boolean language sql stable as $$
  select sim.rand(p_key, p_stream) < p_p;
$$;

-- Box-Muller. u1 is floored away from zero because ln(0) is -infinity.
create or replace function sim.rand_normal(p_key text, p_stream text)
returns double precision language sql stable as $$
  select sqrt(-2.0 * ln(greatest(sim.rand(p_key, p_stream || '/n1'), 1e-12)))
       * cos(2.0 * pi() * sim.rand(p_key, p_stream || '/n2'));
$$;

-- The workhorse for anything with a heavy tail: recipe exposure, recipe counts.
create or replace function sim.rand_lognormal(
  p_key text, p_stream text, p_mu double precision, p_sigma double precision
) returns double precision language sql stable as $$
  select exp(p_mu + p_sigma * sim.rand_normal(p_key, p_stream));
$$;

-- How widely one recipe gets read, before any multiplier.
--
-- The draw itself, in one place, because TWO passes need the same number for
-- the same recipe and they run at opposite ends of the generator: §7 turns it
-- into view rows, and §5 — which runs before a single view exists — weights
-- fork sources by it. Inlining it twice would leave two `'exposure'` streams
-- that agree only as long as nobody edits one of them, and a fork shelf
-- silently uncorrelated with the recipes that are actually read is exactly the
-- kind of wrong that still looks plausible.
--
-- Callers apply their own multipliers on top (persona boost, the star tail,
-- recipe age, preset scale) — this is the per-recipe part only.
create or replace function sim.exposure_draw(p_n bigint)
returns double precision language sql stable as $$
  select sim.rand_lognormal('recipe:' || p_n, 'exposure', 2.0, 1.4);
$$;

-- A timestamp in [from, to). p_skew > 1 packs draws toward `to` (recent), which
-- is what both signups and engagement actually look like.
create or replace function sim.rand_ts(
  p_key text, p_stream text, p_from timestamptz, p_to timestamptz,
  p_skew double precision default 1.0
) returns timestamptz language sql stable as $$
  select p_from + (p_to - p_from) * power(sim.rand(p_key, p_stream), 1.0 / greatest(p_skew, 0.0001));
$$;

-- Deterministic ids. A re-run therefore updates rather than duplicating, and
-- the registries below can name exactly what the sim created.
--
-- bigint, not int, and that is load-bearing rather than defensive: the
-- generator composes ids as `n * 10000 + group * 100 + child`, and at the
-- `large` preset n exceeds 8,000,000 — the product overflows a 32-bit int
-- before it ever reaches this function.
--
-- Every historical signature must be dropped in the file that recreates the
-- function (B024). `create or replace` cannot change an argument list, so the
-- int overload would otherwise survive beside this one.
drop function if exists sim.uid(text, int);
create or replace function sim.uid(p_kind text, p_n bigint)
returns uuid language sql stable as $$
  select md5('sim|' || sim.seed()::text || '|' || p_kind || '|' || p_n)::uuid;
$$;

-- ============================================================================
-- Personas
--
-- The distribution is DATA, so retuning a share is a one-row update rather than
-- a rewrite. Shares sum to 1.0.
--
-- The starting point is the 90-9-1 rule (90% read, 9% engage, 1% create). This
-- product moves it upward because keeping your OWN recipes is the core value
-- proposition, so private-only creators are a real group rather than an
-- anomaly — but 79% of accounts still own no public recipe, which is the case
-- the database has never contained.
-- ============================================================================

create table if not exists sim.persona (
  code           text primary key,
  sort_order     int  not null,
  share          numeric not null,
  min_recipes    int not null,
  max_recipes    int not null,
  private_rate   numeric not null,   -- fraction of their recipes that are private
  view_weight    int not null,       -- relative browsing volume
  like_rate      numeric not null,   -- P(like | viewed)
  save_rate      numeric not null,   -- P(save | viewed)
  rate_rate      numeric not null,   -- P(rating | viewed)
  exposure_boost numeric not null,   -- how much reach their own recipes get
  label          text not null
);

insert into sim.persona (code, sort_order, share, min_recipes, max_recipes,
                         private_rate, view_weight, like_rate, save_rate, rate_rate,
                         exposure_boost, label) values
  ('ghost',     1, 0.220,  0,  0, 0.00, 1, 0.01, 0.00, 0.00, 1, 'Signed up, barely returned'),
  ('lurker',    2, 0.430,  0,  0, 0.00, 6, 0.08, 0.02, 0.01, 1, 'Reads recipes, posts nothing'),
  ('collector', 3, 0.140,  0,  1, 0.80, 9, 0.18, 0.22, 0.05, 1, 'Saves everything, cooks later'),
  ('casual',    4, 0.110,  1,  3, 0.30, 5, 0.14, 0.10, 0.06, 1, 'A few recipes of their own'),
  ('regular',   5, 0.060,  4, 15, 0.15, 7, 0.16, 0.12, 0.08, 2, 'Posts regularly'),
  ('power',     6, 0.025, 15, 60, 0.10, 8, 0.15, 0.11, 0.07, 6, 'Publishes a lot, gets read a lot'),
  ('vault',     7, 0.015,  3, 20, 1.00, 3, 0.05, 0.03, 0.02, 1, 'Private vault only, shares nothing')
on conflict (code) do update set
  sort_order = excluded.sort_order, share = excluded.share,
  min_recipes = excluded.min_recipes, max_recipes = excluded.max_recipes,
  private_rate = excluded.private_rate, view_weight = excluded.view_weight,
  like_rate = excluded.like_rate, save_rate = excluded.save_rate,
  rate_rate = excluded.rate_rate, exposure_boost = excluded.exposure_boost,
  label = excluded.label;

-- Inverse CDF over the share column.
create or replace function sim.persona_for(p_u double precision)
returns text language sql stable as $$
  select coalesce(
    (select code from (
       select code, sort_order, sum(share) over (order by sort_order) as cum
       from sim.persona
     ) x where p_u < x.cum order by x.sort_order limit 1),
    (select code from sim.persona order by sort_order desc limit 1)
  );
$$;

-- ============================================================================
-- Presets
--
-- `users` drives everything else: recipe count falls out of the persona mix,
-- and engagement falls out of the recipe count.
-- ============================================================================

create table if not exists sim.preset (
  name             text primary key,
  users            int not null,
  engagement_scale numeric not null,
  note             text not null
);

insert into sim.preset (name, users, engagement_scale, note) values
  ('tiny',     60, 0.5, 'Screenshots and CI. Seconds to load.'),
  ('small',   250, 0.8, 'Safe on a hosted free tier.'),
  ('medium', 1000, 1.0, 'The default. Breaks pagination, ranking and search assumptions.'),
  ('large',  8000, 1.2, 'Stress test. Expect the search and RLS per-row costs to show.')
on conflict (name) do update set
  users = excluded.users, engagement_scale = excluded.engagement_scale,
  note = excluded.note;

-- ============================================================================
-- Registries — the teardown's safety mechanism
--
-- 9_sim_teardown deletes exactly what is listed here. Never an email pattern,
-- never an id range: a pattern that is subtly wrong on a hosted project deletes
-- real accounts, and `auth.users` has no undo.
-- ============================================================================

create table if not exists sim.actor (
  id         uuid primary key,
  n          int  not null unique,
  persona    text not null references sim.persona (code),
  created_at timestamptz not null
);

create table if not exists sim.recipe (
  id         uuid primary key,
  n          int  not null unique,
  owner_id   uuid not null,
  slug       text not null,
  created_at timestamptz not null
);

-- Only used when config.engage_existing is true: the pre-sim counter values of
-- recipes the sim did not create, captured once so `counter = baseline +
-- generated` stays idempotent across re-runs.
create table if not exists sim.counter_baseline (
  recipe_id  uuid primary key,
  like_count int not null,
  save_count int not null,
  view_count int not null
);

-- ============================================================================
-- Title variants
--
-- One dish becomes many recipes, and `(owner_id, title)` is the import key — a
-- collision within an owner silently collapses two recipes into one row
-- (docs/SDS.md §11.2). The generator indexes into this pool by occurrence, so
-- an owner drawing the same dish twice cannot produce the same title twice.
-- Collisions ACROSS owners are left alone: two people publishing their own take
-- on the same dish is legitimate, and nothing in the database has ever
-- contained that case.
-- ============================================================================

create table if not exists sim.title_variant (
  n        int primary key,
  template text not null
);

insert into sim.title_variant (n, template) values
  (1,  '{title}'),
  (2,  'Weeknight {title}'),
  (3,  'My {title}'),
  (4,  'Grandmother''s {title}'),
  (5,  '{title}, Simplified'),
  (6,  'Slow {title}'),
  (7,  '{title} for Two'),
  (8,  '{title} for a Crowd'),
  (9,  'Quick {title}'),
  (10, 'Sunday {title}'),
  (11, '{title} with a Twist'),
  (12, 'Family {title}'),
  (13, 'Spicy {title}'),
  (14, 'Everyday {title}'),
  (15, '{title}, Made Ahead'),
  (16, 'One-Pot {title}'),
  (17, '{title} the Long Way'),
  (18, 'Budget {title}'),
  (19, '{title}, Lightened Up'),
  (20, 'Festival {title}'),
  (21, 'Late-Night {title}'),
  (22, '{title} from Memory'),
  (23, 'Improved {title}'),
  (24, '{title}, Second Attempt')
on conflict (n) do update set template = excluded.template;

-- The dish library table is declared HERE as well as in the generated
-- 1_sim_dishes.sql, and that is not redundancy to tidy away. Postgres validates
-- a `language sql` function body at creation time, so sim.pick_dish below
-- cannot be created unless sim.dish already exists — and the run order is 0
-- then 1. Without this the very first apply on a clean database fails with
-- `relation "sim.dish" does not exist`, which is invisible on any machine where
-- an earlier run already created it. Both declarations are
-- `create table if not exists`, so whichever file runs first wins and the other
-- is a no-op.
create table if not exists sim.dish (
  slug text primary key,
  doc  jsonb not null
);

-- Weighted draw over sim.dish, so an everyday dish appears more often than a
-- three-hour project bake. Uses the `weight` the dish author set.
create or replace function sim.pick_dish(p_u double precision)
returns text language sql stable as $$
  with w as (
    select d.slug,
           sum(coalesce((d.doc ->> 'weight')::numeric, 1))
             over (order by d.slug rows between unbounded preceding and current row) as cum
    from sim.dish d
  ),
  t as (select sum(coalesce((doc ->> 'weight')::numeric, 1)) as total from sim.dish)
  select w.slug from w cross join t
  where p_u * t.total <= w.cum
  order by w.cum
  limit 1;
$$;

do $$ begin raise notice 'sim schema ready (% personas, % presets, % title variants)',
  (select count(*) from sim.persona),
  (select count(*) from sim.preset),
  (select count(*) from sim.title_variant);
end $$;
