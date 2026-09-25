import 'package:core/core.dart';
import 'package:core/src/repositories/recipe_queries.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decoding tests for the chefs feature.
///
/// These need no `SupabaseClient` — they are pure JSON→model functions, so the
/// mocking blocker that holds up *repository* tests (ROADMAP Phase 3) does not
/// apply here. What they guard is the seam between Postgres and Dart: enum wire
/// values, column-name→field mappings, and `numeric` decoding. Nothing else in
/// the suite touches that seam, and a mismatch there fails silently at runtime
/// rather than at compile time.
void main() {
  group('ChefTier wire format', () {
    // These strings are the Postgres `chef_tier` enum labels. If they drift out
    // of sync with 0001_init.sql, every profile decodes to the fallback tier and
    // the whole leaderboard quietly renders as "Home Cook".
    const wire = {
      'home_cook': ChefTier.homeCook,
      'line_cook': ChefTier.lineCook,
      'sous_chef': ChefTier.sousChef,
      'head_chef': ChefTier.headChef,
      'master_chef': ChefTier.masterChef,
    };

    // `wireValue` restates these labels by hand, because json_serializable
    // keeps its own mapping private and a `.eq('chef_tier', …)` filter needs
    // the string without a decode. `tierCounts()` counts zero chefs on every
    // rung if the two ever disagree, which no other test would notice.
    test('wireValue is the same label the decoder accepts', () {
      for (final tier in ChefTier.values) {
        expect(
          Profile.fromJson({'id': 'x', 'chef_tier': tier.wireValue}).chefTier,
          tier,
          reason: '${tier.name} -> ${tier.wireValue}',
        );
      }
      // And every label really is distinct — a copy-paste slip that made two
      // tiers share a wire value would pass the round-trip above for one of
      // them and silently merge their counts.
      expect(
        ChefTier.values.map((t) => t.wireValue).toSet(),
        hasLength(ChefTier.values.length),
      );
    });

    test('every SQL enum label decodes to its Dart value', () {
      for (final entry in wire.entries) {
        final p = Profile.fromJson({'id': 'x', 'chef_tier': entry.key});
        expect(p.chefTier, entry.value, reason: entry.key);
      }
    });

    test('every Dart value re-encodes to its SQL label', () {
      for (final entry in wire.entries) {
        final json = Profile(id: 'x', chefTier: entry.value).toJson();
        expect(json['chef_tier'], entry.key, reason: entry.value.name);
      }
    });

    test('the enum has exactly the five tiers, lowest first', () {
      // Order is load-bearing: `rank` is the index, and chef_tier_for() returns
      // these in ascending score order.
      expect(ChefTier.values, [
        ChefTier.homeCook,
        ChefTier.lineCook,
        ChefTier.sousChef,
        ChefTier.headChef,
        ChefTier.masterChef,
      ]);
      expect(ChefTier.values.map((t) => t.rank), [0, 1, 2, 3, 4]);
    });

    test('labels are the fixed English display strings', () {
      expect(ChefTier.values.map((t) => t.label), [
        'Home Cook',
        'Line Cook',
        'Sous Chef',
        'Head Chef',
        'Master Chef',
      ]);
    });

    // The forward-compatibility story: a client that predates a future tier must
    // degrade, not throw. Without `unknownEnumValue` this line raises and takes
    // down the whole Discover/leaderboard response.
    test('an unrecognised tier falls back to homeCook instead of throwing', () {
      expect(
        Profile.fromJson({'id': 'x', 'chef_tier': 'grill_master'}).chefTier,
        ChefTier.homeCook,
      );
      expect(
        ChefStanding.fromJson({
          'chef_rank': 1,
          'id': 'x',
          'chef_tier': 'sommelier',
        }).chefTier,
        ChefTier.homeCook,
      );
    });

    test('a null or absent tier falls back to homeCook', () {
      expect(Profile.fromJson({'id': 'x'}).chefTier, ChefTier.homeCook);
      expect(
        Profile.fromJson({'id': 'x', 'chef_tier': null}).chefTier,
        ChefTier.homeCook,
      );
    });
  });

  group('Profile chef columns', () {
    test('decodes all three server-owned columns', () {
      final p = Profile.fromJson({
        'id': '00000000-0000-0000-0000-0000000000d1',
        'display_name': 'Amara Okonkwo',
        'chef_score': 21000.0,
        'chef_tier': 'master_chef',
        'public_recipe_count': 2,
      });
      expect(p.chefScore, 21000.0);
      expect(p.chefTier, ChefTier.masterChef);
      expect(p.publicRecipeCount, 2);
    });

    // Any query that does not select the chef columns (the share dialog's
    // profile lookup, an older cached row) must still decode.
    test('defaults to an unranked home cook when the columns are absent', () {
      final p = Profile.fromJson({'id': 'x', 'display_name': 'Vishnu'});
      expect(p.chefScore, 0);
      expect(p.chefTier, ChefTier.homeCook);
      expect(p.publicRecipeCount, 0);
    });

    // Postgres `numeric` arrives as a JSON number that may be int OR double
    // depending on the value — a bare `as double` throws on the whole-number
    // case (CLAUDE.md gotcha 12).
    test('chef_score survives arriving as an int', () {
      final p = Profile.fromJson({'id': 'x', 'chef_score': 100});
      expect(p.chefScore, 100.0);
      expect(p.chefScore, isA<double>());
    });

    test('chef_score survives arriving as a double', () {
      final p = Profile.fromJson({'id': 'x', 'chef_score': 105.2});
      expect(p.chefScore, closeTo(105.2, 1e-9));
    });
  });

  group('ChefStanding', () {
    // Keys are the `chefs_leaderboard` RETURNS TABLE column names. A rename on
    // either side silently zeroes the affected field.
    Map<String, dynamic> row({Object score = 21000.0, int rank = 1}) => {
      'chef_rank': rank,
      'id': '00000000-0000-0000-0000-0000000000d1',
      'display_name': 'Amara Okonkwo',
      'avatar_url': null,
      'chef_tier': 'master_chef',
      'chef_score': score,
      'public_recipe_count': 2,
      'total_likes': 4000,
      'total_saves': 1600,
      'total_views': 5000,
      'created_at': '2025-03-14T09:30:00.5+00:00',
    };

    test('decodes every column of the RPC row', () {
      final s = ChefStanding.fromJson(row());
      expect(s.chefRank, 1);
      expect(s.id, '00000000-0000-0000-0000-0000000000d1');
      expect(s.displayName, 'Amara Okonkwo');
      expect(s.avatarUrl, isNull);
      expect(s.chefTier, ChefTier.masterChef);
      expect(s.chefScore, 21000.0);
      expect(s.publicRecipeCount, 2);
      expect(s.totalLikes, 4000);
      expect(s.totalSaves, 1600);
      expect(s.totalViews, 5000);
      // Phase 33: returned by both leaderboard RPCs, in lockstep.
      expect(s.createdAt, DateTime.utc(2025, 3, 14, 9, 30, 0, 500));
    });

    test('chef_score decodes as double from both int and double JSON', () {
      expect(ChefStanding.fromJson(row(score: 100)).chefScore, 100.0);
      expect(
        ChefStanding.fromJson(row(score: 105.2)).chefScore,
        closeTo(105.2, 1e-9),
      );
    });

    test('tolerates a sparse row', () {
      final s = ChefStanding.fromJson({'chef_rank': 9, 'id': 'x'});
      expect(s.displayName, '');
      expect(s.chefScore, 0);
      expect(s.publicRecipeCount, 0);
      expect(s.totalViews, 0);
      // An older server that does not return the column still decodes.
      expect(s.createdAt, isNull);
    });

    // Grouped since Phase 22 — the board and the expanded card both print
    // thousands separators, and `scoreLabel` delegates to `ChefScoring.label`
    // so there is one implementation rather than two.
    group('scoreLabel', () {
      test('drops the trailing .0 on whole scores', () {
        expect(ChefStanding.fromJson(row(score: 21000.0)).scoreLabel, '21,000');
        expect(ChefStanding.fromJson(row(score: 0)).scoreLabel, '0');
        expect(ChefStanding.fromJson(row(score: 100)).scoreLabel, '100');
      });

      // Views contribute 0.2 each, so one-decimal scores are the common case
      // for any chef with a view count that is not a multiple of five.
      test('keeps one decimal otherwise', () {
        expect(ChefStanding.fromJson(row(score: 105.2)).scoreLabel, '105.2');
        expect(
          ChefStanding.fromJson(row(score: 10189.4)).scoreLabel,
          '10,189.4',
        );
      });
    });

    group('derived board fields', () {
      test('podium covers exactly the top three ranks', () {
        expect(ChefStanding.fromJson(row(rank: 3)).isPodium, isTrue);
        expect(ChefStanding.fromJson(row(rank: 4)).isPodium, isFalse);
      });

      test('reports the gap to the next tier', () {
        final kitchen = ChefStanding.fromJson(row(score: 10189));
        expect(kitchen.nextTier, ChefTier.masterChef);
        expect(kitchen.nextTierLabel, '34% to Master');
        expect(kitchen.pointsToNextLabel, '9,811');
      });

      test('has no next tier at the top', () {
        final top = ChefStanding.fromJson(row(score: 21000));
        expect(top.nextTier, isNull);
        expect(top.nextTierLabel, isNull);
        expect(top.pointsToNextLabel, isNull);
      });
    });
  });

  group('Recipe.owner embedding', () {
    Map<String, dynamic> recipeJson({Map<String, dynamic>? owner}) => {
      'id': 'r1',
      'owner_id': '00000000-0000-0000-0000-0000000000d1',
      'title': 'Charcoal Jollof Rice',
      if (owner != null) 'owner': owner,
    };

    test('decodes the embedded owner when the query asked for it', () {
      final r = Recipe.fromJson(
        recipeJson(
          owner: {
            'id': '00000000-0000-0000-0000-0000000000d1',
            'display_name': 'Amara Okonkwo',
            'avatar_url': null,
            'chef_tier': 'master_chef',
          },
        ),
      );
      expect(r.owner, isNotNull);
      expect(r.owner!.id, r.ownerId);
      expect(r.owner!.chefTier, ChefTier.masterChef);
    });

    // Surfaces that don't embed must still decode — they simply render no badge.
    test('owner is null when the embedding is absent', () {
      expect(Recipe.fromJson(recipeJson()).owner, isNull);
    });

    test('owner is null when the embedding is explicitly null', () {
      expect(Recipe.fromJson({...recipeJson(), 'owner': null}).owner, isNull);
    });

    // The embed is a read-side join, not a column. Writing it back would send
    // `owner` to PostgREST as an unknown column on insert/update, and would
    // bloat every recipe_versions.content_snapshot.
    test('owner is excluded from toJson', () {
      final r = Recipe.fromJson(
        recipeJson(
          owner: {
            'id': '00000000-0000-0000-0000-0000000000d1',
            'display_name': 'Amara Okonkwo',
          },
        ),
      );
      expect(r.owner, isNotNull);
      expect(r.toJson().containsKey('owner'), isFalse);
    });
  });

  group('kRecipeSelect', () {
    // Regression guard for the PGRST201 trap: `recipes` and `profiles` are
    // related five ways, so a bare `profiles(...)` is ambiguous and every
    // recipe query fails at once. The FK hint is the whole point of this
    // constant existing.
    test('names the owner_id foreign key explicitly', () {
      expect(kRecipeSelect, contains('profiles!recipes_owner_id_fkey'));
      expect(
        RegExp(r'profiles(?!!)').hasMatch(kRecipeSelect),
        isFalse,
        reason: 'an unhinted `profiles` embed would raise PGRST201',
      );
    });

    test('aliases the embed as `owner` so Recipe.owner maps to it', () {
      expect(kRecipeSelect, contains('owner:profiles'));
    });

    // Was `startsWith('*,')` until OPT-P1. `recipes.search_tsv` is a ~450-byte
    // tsvector the client never reads, and `*` shipped it on every row (~13 KB
    // per 30-card page), so the columns are now listed explicitly. The contract
    // that actually matters is unchanged — every column `Recipe` decodes must be
    // requested — so assert that instead of the wildcard.
    //
    // The list below used to include `rating_sum`, under a name claiming these
    // are the columns the model decodes. It is not one: `Recipe` has
    // `ratingAvg` and `ratingCount` and no sum, so the select carried a number
    // nothing could read and the pin said otherwise (B086). The inverse test
    // after this one is what makes that class fail loudly.
    test('requests every column Recipe decodes', () {
      const required = [
        'id',
        'owner_id',
        'title',
        'description',
        'cover_image_url',
        'cuisine',
        'category',
        'difficulty',
        'prep_minutes',
        'cook_minutes',
        'servings',
        'visibility',
        'attribution',
        'forked_from_recipe_id',
        'forked_from_version_id',
        'current_version_id',
        'like_count',
        'save_count',
        'view_count',
        'created_at',
        'updated_at',
        'rating_count',
        'rating_avg',
        'nutrition',
        // Phase 35c provenance. Server-owned like the counters, and read for
        // the same reason: the credit line, its link and the image decision are
        // all rendered.
        'is_imported',
        'source_url',
        'source_name',
        'source_entity_id',
        'rights_mode',
        'image_mode',
      ];
      // Only the base-row part: the embed carries its own `id`/`avatar_url`.
      final base = kRecipeSelect.substring(0, kRecipeSelect.indexOf(',owner:'));
      for (final column in required) {
        expect(
          base.split(',').contains(column),
          isTrue,
          reason:
              '$column is missing from kRecipeSelect, so Recipe.$column '
              'would silently decode as null',
        );
      }
    });

    // The other direction (32d1). Without it, a column can be requested forever
    // with no field behind it — dead weight on every row of every grid, and
    // invisible, because PostgREST answers happily and the decoder ignores what
    // it does not know.
    test('every column it requests decodes into a Recipe field', () {
      const sample = Recipe(id: 'r1', ownerId: 'u1', title: 'Tart');
      final known = sample.toJson().keys.toSet();
      // The two embeds are `includeToJson: false` (they are nested reads, not
      // columns) and `owner` is the FK embed, so they are named rather than
      // discovered.
      known.addAll(['ingredient_groups', 'step_groups', 'owner']);

      final base = kRecipeSelect.substring(0, kRecipeSelect.indexOf(',owner:'));
      for (final column in base.split(',')) {
        expect(
          known.contains(column),
          isTrue,
          reason:
              '$column is fetched on every recipe row and no Recipe field '
              'decodes it — either add the field or drop the column (B086)',
        );
      }
    });

    test('does not request the server-owned search_tsv', () {
      expect(
        kRecipeSelect,
        isNot(contains('search_tsv')),
        reason:
            'OPT-P1: the tsvector is write-only server state; shipping it '
            'adds ~450 bytes per recipe for a field nothing reads',
      );
    });

    test('requests the fields ChefBadge renders', () {
      for (final field in ['id', 'display_name', 'avatar_url', 'chef_tier']) {
        expect(kRecipeSelect, contains(field), reason: field);
      }
    });

    // B118: `Profile.kind` defaults to member, so dropping `kind` from the
    // owner embed would silently put `Home Cook` back on every captured byline.
    // Matched inside the embed, because `recipes` has no `kind` column and a
    // bare `contains('kind')` would pass on an unrelated substring.
    test('embeds the owner kind, so an imported chef shows no tier', () {
      final embed = RegExp(
        r'owner:profiles!recipes_owner_id_fkey\(([^)]*)\)',
      ).firstMatch(kRecipeSelect);
      expect(embed, isNotNull);
      expect(embed!.group(1)!.split(','), contains('kind'));
    });
  });

  // Phase 33. Keys are `chef_window_stats`' RETURNS TABLE column names — the
  // windowed board returns the same six beside the board's eleven.
  group('ChefWindowStats', () {
    Map<String, dynamic> row({Object score = 312, int likes = 40}) => {
      'id': 'd1',
      'window_start': '2026-09-17T12:00:00+00:00',
      'window_likes': likes,
      'window_saves': 30,
      'window_views': 60,
      'window_ratings': 2,
      'window_recipes': 1,
      'window_score': score,
    };

    test('decodes every column', () {
      final w = ChefWindowStats.fromJson(row());
      expect(w.id, 'd1');
      expect(w.windowStart, DateTime.utc(2026, 9, 17, 12));
      expect(w.likes, 40);
      expect(w.saves, 30);
      expect(w.viewers, 60);
      expect(w.ratings, 2);
      expect(w.newRecipes, 1);
      expect(w.score, 312.0);
    });

    test('window_score survives an int or a double (Gotcha 12)', () {
      expect(ChefWindowStats.fromJson(row(score: 0)).score, 0.0);
      expect(ChefWindowStats.fromJson(row(score: 12.4)).score, 12.4);
    });

    test(
      'moved is a positive score; idle also needs no ratings or recipes',
      () {
        final quiet = ChefWindowStats.fromJson(row(score: 0, likes: 0));
        expect(quiet.moved, isFalse);
        // Published a recipe and got two ratings: did not move, was not idle.
        expect(quiet.isIdle, isFalse);
        expect(quiet.copyWith(ratings: 0, newRecipes: 0).isIdle, isTrue);
        expect(ChefWindowStats.fromJson(row()).moved, isTrue);
      },
    );

    test('gainLabel is grouped and signed', () {
      expect(ChefWindowStats.fromJson(row(score: 1312)).gainLabel, '+1,312');
      expect(ChefWindowStats.fromJson(row(score: 12.4)).gainLabel, '+12.4');
      expect(ChefWindowStats.fromJson(row(score: 0)).gainLabel, '+0');
    });

    test('a windowed board row splits into its two halves', () {
      final r = ChefWindowStanding.fromRow({
        ...row(),
        'chef_rank': 3,
        'display_name': 'Chen Wei',
        'chef_score': 1200,
        'total_likes': 200,
      });
      expect(r.id, 'd1');
      // The rank on a windowed row is the rank IN THE WINDOW.
      expect(r.standing.chefRank, 3);
      expect(r.standing.chefScore, 1200.0);
      expect(r.standing.totalLikes, 200);
      expect(r.window.likes, 40);
    });
  });
}
