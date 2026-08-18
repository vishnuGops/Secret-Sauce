# SDS — Software Design Spec — Secret-Sauce

Authoritative design reference. Kept in sync with the code.

## 1. Overview

Secret-Sauce is a cross-platform recipe vault. Users create richly structured recipes, keep them
private or public, share privately with specific users, and **fork** others' recipes (git-style)
with a **version history** so recipes and their improvements are preserved across generations.

### Goals

- Make recipe **structure and instructions** clear and easy to follow.
- Preserve legacy recipes (attribution + story, immutable version snapshots).
- Enable sharing, discovery, and safe forking/improvement.

### Non-goals (now)

- Upstream "suggest changes" (PR-like) flow — schema hook reserved, UI deferred.
- Real-time collaborative editing.

## 2. Architecture

Single **adaptive** Flutter app; shared logic/UI in packages.

```mermaid
flowchart TD
  subgraph app["apps/app (Flutter, adaptive)"]
    UI["features/* screens"] --> P["Riverpod controllers/providers"]
  end
  subgraph core["packages/core"]
    P --> R["Repositories (abstract)"]
    R --> RI["Supabase implementations"]
    RI --> S["Services: Auth / Storage / Client"]
  end
  DS["packages/design_system"] --> UI
  S --> SB[("Supabase: Postgres + Auth + Storage + RLS")]
```

- UI → Riverpod → Repository (abstract) → Supabase impl → Supabase.
- UI never calls Supabase directly.
- Authorization is enforced by **RLS**; client checks are UX-only.

### Layers

| Layer         | Location                     | Responsibility                         |
| ------------- | ---------------------------- | -------------------------------------- |
| Presentation  | `apps/app/features/*`        | Screens, adaptive layout               |
| Design system | `packages/design_system`     | Theme, reusable widgets (`RecipeCard`) |
| State         | `apps/app` (Riverpod)        | Controllers, view-models               |
| Domain/Data   | `packages/core/repositories` | Contracts + Supabase impls             |
| Services      | `packages/core/services`     | Client bootstrap, auth, storage        |

## 3. Data model

### 3.1 Enums

- `difficulty`: `easy` \| `medium` \| `hard`
- `recipe_visibility`: `private` \| `public`
- `share_permission`: `view` (reserved: `edit`)
- `suggestion_status`: `open` \| `accepted` \| `rejected` (reserved for future PR flow)

### 3.2 Tables

**profiles** — 1:1 with `auth.users`
`id (uuid, PK, = auth.uid)`, `display_name`, `avatar_url`, `bio`, `created_at`.
Created by the `on_auth_user_created` trigger. Every other table's `user_id` is an FK to
**profiles**, not `auth.users`, so a missing profile row breaks rating/saving/view logging for
that account — `0001_init.sql` therefore backfills profiles from `auth.users` on every apply
(the trigger only fires on insert, so it cannot repair users that predate it; see B015).

**recipes**
`id`, `owner_id → profiles`, `title`, `description`, `cover_image_url`, `cuisine`,
`category`, `difficulty`, `prep_minutes`, `cook_minutes`, `servings`,
`visibility`, `attribution` (legacy: original creator/story),
`forked_from_recipe_id → recipes` (nullable), `forked_from_version_id → recipe_versions` (nullable),
`current_version_id → recipe_versions` (nullable), `like_count`, `save_count`, `view_count`,
`rating_sum (numeric)`, `rating_count (int)`, `rating_avg (numeric(3,2))`,
`created_at`, `updated_at`.

The three `rating_*` columns are **denormalized aggregates** — never written by the client;
the `recipe_ratings` trigger recomputes them from scratch so they cannot drift.

**recipe_versions** — git-like immutable snapshots
`id`, `recipe_id → recipes`, `version_number (int)`, `parent_version_id → recipe_versions` (nullable),
`author_id → profiles`, `change_summary`, `content_snapshot (jsonb)` (full recipe body at that point),
`created_at`.

**ingredient_groups**: `id`, `recipe_id`, `name` (e.g. "For the sauce"), `sort_order`.
**ingredients**: `id`, `group_id → ingredient_groups`, `quantity (numeric, nullable)`,
`unit`, `name`, `note`, `is_optional (bool)`, `sort_order`.

**step_groups**: `id`, `recipe_id`, `name`, `sort_order`.
**steps**: `id`, `group_id → step_groups`, `step_order (int)`, `text`, `image_url`,
`duration_minutes`, `temperature`, `tip`, `sort_order`.

**tags**: `id`, `name (unique)`. **recipe_tags**: `recipe_id`, `tag_id` (PK pair).

**recipe_shares**: `recipe_id`, `shared_with_user_id → profiles`, `permission (share_permission)`,
`created_at` (PK: recipe_id + user).

**recipe_likes** / **recipe_saves**: `user_id`, `recipe_id`, `created_at` (PK pair).
**recipe_views**: `id`, `recipe_id`, `user_id (nullable)`, `viewed_at`. An append-only log — every
visit inserts a row. The `on_view_insert` trigger rolls it into `recipes.view_count`, counting
**distinct signed-in viewers**: a user's second-and-later row for the same recipe is ignored, and
anonymous rows (`user_id is null`) never count at all. The probe is a read-then-write, so it takes
a per-(recipe, user) `pg_advisory_xact_lock` — without it two concurrent first-views from one
account both bump. Deliberately has no unique constraint, so `logView()` stays a plain insert
(PostgREST cannot express `on conflict` inference against a partial index) and the full log
survives for later analytics.

`view_count` is **monotonic and therefore an upper bound**, not an exact distinct count: nothing
decrements it, and `user_id` is `on delete set null` (unlike `recipe_likes`/`recipe_saves`, which
cascade and fire their DELETE branch), so a deleted account's contribution stays and a
re-registered user counts again.

**recipe_ratings**: `user_id`, `recipe_id` (PK pair), `rating (numeric(2,1))`, `created_at`,
`updated_at`. One row per user per recipe — re-rating overwrites. `rating` is constrained to
**0.5 … 5.0 in half-star steps** (`rating * 2 = floor(rating * 2)`). An `after insert/update/delete`
trigger calls `recompute_recipe_rating(recipe_id)`, which rewrites `recipes.rating_sum`,
`rating_count`, and `rating_avg`.

**recipe_suggestions** _(reserved stub — not wired to UI)_
`id`, `recipe_id (target)`, `from_recipe_id (fork source)`, `author_id`, `status (suggestion_status)`,
`summary`, `payload (jsonb)`, `created_at`.

### 3.3 ERD

```mermaid
erDiagram
  profiles ||--o{ recipes : owns
  recipes ||--o{ recipe_versions : has
  recipes ||--o{ ingredient_groups : has
  ingredient_groups ||--o{ ingredients : has
  recipes ||--o{ step_groups : has
  step_groups ||--o{ steps : has
  recipes ||--o{ recipe_tags : tagged
  tags ||--o{ recipe_tags : labels
  recipes ||--o{ recipe_shares : shared
  recipes ||--o{ recipe_likes : liked
  recipes ||--o{ recipe_saves : saved
  recipes ||--o{ recipe_views : viewed
  recipes ||--o{ recipe_ratings : rated
  profiles ||--o{ recipe_ratings : rates
  recipes ||--o| recipes : "forked_from"
  recipes ||--o{ recipe_suggestions : suggests
```

## 4. Row-Level Security

- **recipes SELECT**: `visibility = 'public'` OR `owner_id = auth.uid()` OR exists row in
  `recipe_shares` for `(recipe_id, auth.uid())`.
- **recipes INSERT/UPDATE/DELETE**: `owner_id = auth.uid()`.
- Child tables (ingredients/steps/versions/…): access derived from parent recipe visibility.
- **recipe_shares**: recipe owner manages; shared user can read own rows.
- **likes/saves**: user manages own rows; counts denormalized on `recipes` via triggers.
- **views**: anyone who can read a recipe may log a view, including anonymous visitors — but only
  as themselves: `views_insert`'s `with check` requires `user_id is null or user_id = auth.uid()`,
  so a view cannot be attributed to another user. Only the recipe owner can read the log.
  Anonymous rows never move `view_count`, because `anon` holds `insert` on the table and counting
  them would make `recipes_trending` inflatable without an account.
- **counter/aggregate triggers** (`on_like_change`, `on_save_change`, `on_view_insert`,
  `on_rating_change`) are
  `security definer`: they write a `recipes` row the acting user does not own, which plain
  invoker rights would let RLS drop silently (see B011). Their helpers (`bump_count`,
  `recompute_recipe_rating`) have EXECUTE revoked from `public` / `anon` / `authenticated`, so
  PostgREST cannot expose them as RPCs.
- **ratings**: readable by anyone who can read the recipe; a user may write only their own row
  (`user_id = auth.uid()`), only for a recipe they can read, and **never for a recipe they own** —
  self-rating is rejected by the `with check` clause, not just hidden in the UI.
- **profiles**: readable by all; writable only by self.
- **grants**: RLS chooses rows, `GRANT` chooses tables — both are required. The schema grants
  `select` on all public tables to `anon` + `authenticated`, DML to `authenticated`, and
  `insert on recipe_views` to `anon`. Without this a fresh Supabase project returns
  `permission denied for table ...` for every request (B013).

## 5. Forking & versioning

- **Edit** → append a `recipe_versions` row (`version_number = max+1`, `parent_version_id` = prior),
  set `recipes.current_version_id`. Snapshots are immutable → full lineage retained.
- **Fork** → deep-copy recipe + its groups/ingredients/steps into a new recipe owned by the forker;
  set `forked_from_recipe_id` and `forked_from_version_id`. Independent thereafter.
- **Attribution** → `recipes.attribution` free-text preserves legacy origin/story; detail screen
  also shows "Forked from {title} by {owner}" when lineage exists.
- **Future PR flow** → `recipe_suggestions` reserved so a fork can later propose changes upstream.

## 6. Discovery & ranking

- **Access**: Discover, search, and public recipe detail are open to anonymous (signed-out)
  visitors — RLS `recipes SELECT` already permits reading `public` recipes without auth. Sign-in
  is only required for creating/editing, My Recipes, Profile, and owner actions (share, fork).
- **Recent**: `ORDER BY created_at DESC` over public recipes.
- **Popular**: ranked by **star rating**, using a Bayesian (weighted) average so a single 5-star
  recipe does not outrank a 4.8 with hundreds of ratings:

  ```text
  score = (rating_sum + m * C) / (rating_count + m)     m = 5, C = site-wide mean rating
  ```

  `m` phantom ratings sit at the site mean `C` (`sum(rating_sum) / sum(rating_count)` over public
  recipes, defaulting to 3.5 when nothing is rated yet); real ratings pull the score away from that
  prior. Ties break on `rating_count`, then `save_count + like_count`, then `created_at`.
- **Trending**: recency-weighted score, e.g.
  `score = (like_count + view_count) / pow(hours_since_created + 2, 1.5)`. Both inputs are
  one-per-user by construction (`recipe_likes` PK, `on_view_insert` dedup), so the score cannot be
  driven up by repeat traffic from one account or by anonymous visitors.
- **Search**: Postgres full-text over title + description + ingredient names + tags.

## 7. Screens

| Screen         | Route                             | Notes                                                                                 |
| -------------- | --------------------------------- | ------------------------------------------------------------------------------------- |
| Home / landing | `/`                               | Intro, feature highlights, sign in/up                                                 |
| Sign in / up   | `/auth`                           | Supabase auth                                                                         |
| Discover       | `/discover`                       | Popular (rating-ranked) / Trending / Recent tabs + search (public, no sign-in)         |
| My Recipes     | `/my`                             | Tabs: My / Shared-with-me; `RecipeCard` grid with Public/Private badges                |
| Recipe detail  | `/recipe/:id`                     | Structured view, servings scaler, rating, fork, versions (public recipes viewable signed-out) |
| Recipe editor  | `/recipe/new`, `/recipe/:id/edit` | Structured create/edit                                                                |
| Profile        | `/profile`                        | Current user                                                                          |

### Adaptive behavior

- Narrow (< 600): bottom navigation, single-column lists.
- Wide (≥ 1000): fixed top navigation bar (brand + destinations + "New recipe"), multi-column grids, side-by-side detail.
- Breakpoints centralized in `design_system/layout/adaptive.dart`.

## 8. RecipeCard contract

Inputs: cover image, name, short description, cook time (prep+cook), average star rating
(hidden until the recipe has at least one rating), difficulty badge. `showVisibility: true`
overlays a Public/Private pill on the cover — used on My Recipes, where both kinds are listed.
Used across Discover and My Recipes.

### Rating widgets (`design_system`)

| Widget            | Use                                                                 |
| ----------------- | ------------------------------------------------------------------- |
| `StarRating`      | Read-only 5-star display with half stars, value, and rating count   |
| `RatingPill`      | Compact single star + value, for dense surfaces (`RecipeCard`)      |
| `StarRatingInput` | Interactive half-star input; `onChangeEnd` fires when a gesture ends |

`StarRatingInput` maps the left half of star _n_ to `n - 0.5` and the right half to `n`, and
previews during a drag; the caller persists on `onChangeEnd` so a drag writes once, not per frame.
If the gesture is **cancelled** — an ancestor scroll view claims it after a press-and-hold — the
preview is dropped and `onChangeEnd` never fires, so the stars never show an unsaved value (B017).

The `RecipeCard` metadata row (time · rating · difficulty) is width-adaptive: the time label,
both `RatingPill` texts, and the `DifficultyBadge` label are `Flexible` and ellipsize in that
order. A fixed-aspect grid tile cannot grow, so the row degrades instead of overflowing at narrow
widths or large text scale (B016).

## 9. Security notes

- No secrets in source; Supabase keys via `--dart-define` / env.
- All authorization via RLS; never rely on client filtering for privacy.
- Storage buckets scoped; signed/public URLs per bucket policy.
