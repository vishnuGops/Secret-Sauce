import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/link.dart';

import 'package:app/features/legal/legal_document.dart';
import 'package:app/routing/app_router.dart';

/// Where a recipe came from: the fork mark, the cook's own story, and — for a
/// recipe captured from the public web — who wrote it, who published it and
/// where the original is.
///
/// Both layouts drew these themselves, a few pixels apart (32c5). They are the
/// same statements about provenance, so they are one widget each here and
/// differ only in how the page around them frames them.

/// `⑂ Forked recipe` — the lineage mark above the title (canvas frame F).
///
/// It says what the row *knows*: `forked_from_recipe_id` is an id, and naming
/// the parent would need a second read neither layout makes.
class ForkedLabel extends StatelessWidget {
  const ForkedLabel({super.key, this.expand = false});

  /// Let the label take the row's free width. The compact page stacks it above
  /// the title in a full-width column, where an `Expanded` text can ellipsise;
  /// the expanded page sits it in a row of chips beside the back button, where
  /// it must size to its content.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Text(
      'Forked recipe',
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: scheme.primary),
    );

    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(Icons.call_split, size: AppIconSize.sm, color: scheme.primary),
        const SizedBox(width: AppSpacing.xs),
        if (expand) Expanded(child: label) else label,
      ],
    );
  }
}

/// The attribution / story block — the cook's own line about where the recipe
/// came from, which is the whole point of a family recipe vault.
class AttributionBlock extends StatelessWidget {
  const AttributionBlock({super.key, required this.text, this.boxed = false});

  final String text;

  /// Draw it as its own card. Compact does: on a phone the story follows the
  /// description with nothing else to separate them, so it needs an edge.
  /// The expanded header band already sits on `surfaceContainerLow` under a
  /// display-size title, where a second box would be one border too many — so
  /// there the text carries the distinction instead, in the secondary colour.
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.auto_stories,
          size: AppIconSize.md,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style:
                boxed
                    ? textTheme.bodyMedium
                    : textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
          ),
        ),
      ],
    );

    if (!boxed) return row;
    return Container(
      padding: AppInsets.callout,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: row,
    );
  }
}

/// Where an imported recipe came from, and on what terms it is shown here —
/// Phase 35a's recipe-detail attribution block, with Phase 35c's content behind
/// it.
///
/// This is not decoration and it is not optional. The rights position the app
/// states — store and show the functional part of a recipe, link everything
/// expressive, never re-host a photograph — only holds because the credit and
/// the link travel with the content. A captured recipe rendered without them is
/// the same bytes making a different, and indefensible, claim.
///
/// Four statements, top to bottom, each answering a question a reader has:
///
///  1. **Who wrote it** — `Recipe by <chef>`, linking to `/chef/:id`. The chef
///     is the recipe's owner, which for a captured recipe is the imported
///     profile the importer made from the byline. Omitted when the page named
///     nobody: the importer then credits the *publisher* as author (one profile
///     per entity, named after it), and printing `Recipe by Mutti` over
///     `Published by Mutti` would invent a person who is not there. The Rights
///     page says a recipe with no byline "is credited to the publisher and to
///     nobody else", and this is where that promise is kept.
///  2. **Who published it** — `Published by <publisher>`, linking to
///     `/entity/:id` when the row carries an entity. Recorded separately from
///     the chef and never inferred from it (35a).
///  3. **Where the original is** — a real outbound link. On web it is an
///     anchor (`Link`), so it opens in a new tab, middle-clicks and copies like
///     any other link on the web.
///  4. **On what terms** — one sentence of the rights position, in the same
///     words `/explore` uses above its first card, and a link to the Rights
///     page for the rest.
///
/// Rendered for imported recipes only. A member's own recipe is credited by its
/// owner badge like every other, and a second credit line under it would read
/// as a second author.
class SourceCredit extends StatelessWidget {
  const SourceCredit({super.key, required this.recipe});

  final Recipe recipe;

  /// Keys the tests (and nothing else) reach the three links by.
  static const chefLineKey = ValueKey('source-credit-chef');

  /// `profiles.display_name`'s length cap (`profiles_text_lengths`).
  static const _kProfileNameMax = 80;
  static const publisherLineKey = ValueKey('source-credit-publisher');
  static const originalLinkKey = ValueKey('source-credit-original');

  /// The person to credit, or null when there is no separate one.
  ///
  /// Null when the owner embed is missing (nothing to name or route to) and in
  /// the publisher-as-author case described on the class.
  static Profile? creditedChef(Recipe recipe) {
    final owner = recipe.owner;
    if (owner == null) return null;
    final name = owner.displayName.trim();
    if (name.isEmpty) return null;
    var publisher = (recipe.sourceName ?? '').trim();
    // `import_recipe` clamps a publisher-as-author profile's name to 80
    // characters (`profiles_text_lengths`) but stores `source_name` whole, so
    // compare on the clamped length — otherwise a long publisher name reads as
    // "Recipe by <the same publisher, truncated>", the invented person this
    // method exists to avoid.
    if (publisher.length > _kProfileNameMax) {
      publisher = publisher.substring(0, _kProfileNameMax).trim();
    }
    if (publisher.isNotEmpty && publisher.toLowerCase() == name.toLowerCase()) {
      return null;
    }
    return owner;
  }

  /// The original page as a link target, or null when it is not one.
  ///
  /// Only `http`/`https` with a host: `source_url` is scraped data, and a
  /// `javascript:` or `file:` value there must print, never become a tap
  /// target.
  static Uri? originalUri(Recipe recipe) {
    final raw = (recipe.sourceUrl ?? '').trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return uri;
  }

  /// `cafedelites.com` for `https://www.cafedelites.com/x/` — what the link
  /// button names, because "Read the original" alone does not say where a tap
  /// is about to take you.
  static String hostLabel(Uri uri) =>
      uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;

  @override
  Widget build(BuildContext context) {
    if (!recipe.isImported) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final chef = creditedChef(recipe);
    final uri = originalUri(recipe);
    final host = uri == null ? null : hostLabel(uri);
    final publisher = (recipe.sourceName ?? '').trim();
    final entityId = recipe.sourceEntityId;
    final rawUrl = (recipe.sourceUrl ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The kicker says what kind of recipe this is before any name does,
          // so a credit line is never mistaken for this app's own byline.
          Row(
            children: [
              Icon(
                Icons.travel_explore_outlined,
                size: AppIconSize.sm,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xsPlus),
              // The icon is the non-flex child and the text takes what is left
              // (Gotcha 21).
              Expanded(
                child: Text(
                  'FROM AROUND THE WEB',
                  style: context.appText.overline.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (chef != null)
            _CreditLine(
              key: chefLineKey,
              label: 'Recipe by',
              name: chef.displayName.trim(),
              onTap: () => context.push(Routes.chef(chef.id)),
            ),
          _CreditLine(
            key: publisherLineKey,
            label: publisher.isEmpty && host == null ? null : 'Published by',
            name:
                publisher.isNotEmpty
                    ? publisher
                    : (host ?? 'Published elsewhere'),
            onTap:
                entityId == null || entityId.isEmpty
                    ? null
                    : () => context.push(Routes.entity(entityId)),
          ),
          if (uri != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Link(
              uri: uri,
              target: LinkTarget.blank,
              builder:
                  (context, followLink) => _OriginalButton(
                    key: originalLinkKey,
                    host: host!,
                    // A link-only recipe has no method on this page, so the
                    // link *is* the recipe — it gets the filled button.
                    prominent: !recipe.showsContent,
                    onPressed:
                        followLink == null
                            ? null
                            : () => unawaited(followLink()),
                  ),
            ),
          ] else if (rawUrl.isNotEmpty) ...[
            // An address that is not a web link still gets printed — a reader
            // can go and find it — but never becomes something to tap.
            const SizedBox(height: AppSpacing.sm),
            SelectableText(rawUrl, style: muted),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            recipe.showsContent
                // `/explore`'s preamble, near word for word: a reader who came
                // from that page has been told this once already, and two
                // phrasings of one promise read as two promises.
                ? 'We keep the ingredients and the method, credit the cook and '
                    'the publisher, and link back to the original — we do not '
                    'copy their photographs or their writing.'
                : 'This publisher asked us to link rather than reproduce, so '
                    'the method is on their page.',
            style: muted,
          ),
          TextButton.icon(
            // Shape and label weight come from the theme (UX-033). Only the
            // inset stays: a near-zero, compact padding keeps this link flush
            // with the credit text above it instead of indented like a button.
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => context.push(Routes.legal(LegalDoc.rights.slug)),
            icon: const Icon(Icons.gavel_outlined, size: AppIconSize.sm),
            label: const Text('How we credit recipes'),
          ),
        ],
      ),
    );
  }
}

/// `Recipe by Karina Carrel ›` — one credit, tappable when it has a page.
///
/// One `Text.rich` rather than a label beside a name: at 2.0× on a phone
/// `Published by` alone is half the row, and two `Text`s in a `Row` would cut
/// the name — the part that matters — to fit the label. A rich span wraps as
/// one sentence instead.
class _CreditLine extends StatelessWidget {
  const _CreditLine({
    super.key,
    required this.label,
    required this.name,
    this.onTap,
  });

  /// Null prints the name alone (`Published elsewhere`).
  final String? label;
  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final text = Text.rich(
      TextSpan(
        children: [
          if (label != null)
            TextSpan(
              text: '$label ',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          TextSpan(
            text: name,
            style: theme.textTheme.titleSmall?.copyWith(
              color: onTap == null ? null : scheme.primary,
            ),
          ),
        ],
      ),
    );

    const pad = EdgeInsets.symmetric(vertical: AppSpacing.xsPlus);
    if (onTap == null) return Padding(padding: pad, child: text);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Padding(
        padding: pad,
        // Text flexes, chevron does not (Gotcha 21).
        child: Row(
          children: [
            Expanded(child: text),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.chevron_right,
              size: AppIconSize.button,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// `↗ Read the original on cafedelites.com`.
class _OriginalButton extends StatelessWidget {
  const _OriginalButton({
    super.key,
    required this.host,
    required this.prominent,
    required this.onPressed,
  });

  final String host;
  final bool prominent;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.open_in_new, size: AppIconSize.button);
    // The label wraps rather than ellipsising: a host is unbounded, and a
    // half-printed address is the one thing a link must never be.
    final label = Text('Read the original on $host');
    return prominent
        ? FilledButton.tonalIcon(onPressed: onPressed, icon: icon, label: label)
        : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: label);
  }
}
