/// The three legal documents, as structured content rather than markup.
///
/// Phase 35a. They are Dart consts and not rows in a table on purpose: a legal
/// document is a *release artifact*: which words were in force on a given day
/// has to be answerable from the repository, and a database row has no history
/// anyone can read. Keeping them here also means they ship with the build that
/// they describe, which is the only way `lastUpdated` can be trusted.
///
/// No `flutter_markdown`: three heading/paragraph/bullet documents do not earn
/// a dependency, and a renderer that accepts arbitrary markup is a renderer
/// that will eventually be handed some.
library;

/// The facts only the owner can supply.
///
/// **These are provisional.** They are well-formed so the documents read as
/// documents rather than as a form with holes in it, and every one of them is a
/// statement about a real legal entity that has not been made yet. Nothing here
/// is a fact until somebody checks it.
///
/// [provisional] is a separate flag rather than a guess at the values, because
/// the previous shape — "is it still in brackets?" — stops working the moment
/// the placeholders look plausible, which is exactly what makes them dangerous.
/// Replacing the four values and flipping one boolean is the whole change.
///
/// This is the ONE place to edit them. Nothing below restates a value.
class LegalFacts {
  LegalFacts._();

  /// Set to `false` once all four values below have been confirmed by someone
  /// who can commit the operator to them. While it is `true`, every document
  /// carries a banner saying so.
  static const bool provisional = true;

  /// The legal entity that operates Secret-Sauce.
  ///
  /// The product name stands in for it. There is no registered company behind
  /// Secret-Sauce yet, and naming one that does not exist would be worse than
  /// naming none.
  static const String entity = 'Secret-Sauce';

  /// Governing law and the courts that have jurisdiction.
  ///
  /// England and Wales as a working assumption. This is the value most likely
  /// to be wrong and the most expensive one to be wrong about — it decides
  /// which consumer-protection regime the Terms sit inside, so it cannot ship
  /// unconfirmed.
  static const String governingLaw =
      'These terms are governed by the laws of England and Wales. The courts of '
      'England and Wales have exclusive jurisdiction over any dispute arising '
      'from them, and nothing here removes a right you have under the consumer '
      'law of the country you live in.';

  /// Where privacy requests and takedown notices go.
  ///
  /// `.example` is reserved by RFC 2606 and can never resolve, so this address
  /// cannot silently swallow a real takedown notice while it is provisional —
  /// mail to it bounces, which is the loud failure rather than the quiet one.
  static const String contactEmail = 'legal@secret-sauce.example';

  /// The AWS region the Supabase project runs in. Named because "where your
  /// data is" is a question a privacy policy has to answer concretely, and it
  /// is the one value here that can be read off the hosted project rather than
  /// decided.
  static const String hostingRegion = 'the eu-west-2 (London) region';

  /// True once the four values above are confirmed.
  static bool get isComplete => !provisional;
}

/// One block of a document. Sealed so the renderer's switch is exhaustive and a
/// new block type cannot be added without the renderer being updated.
sealed class LegalBlock {
  const LegalBlock();
}

/// A section heading.
class LegalHeading extends LegalBlock {
  const LegalHeading(this.text);
  final String text;
}

class LegalParagraph extends LegalBlock {
  const LegalParagraph(this.text);
  final String text;
}

class LegalBullets extends LegalBlock {
  const LegalBullets(this.items);
  final List<String> items;
}

/// Which of the three documents. Also the route parameter, so the router and
/// the sibling links below cannot drift apart.
enum LegalDoc {
  privacy('privacy', 'Privacy', 'Privacy Policy'),
  terms('terms', 'Terms', 'Terms of Service'),
  rights('rights', 'Rights', 'Content Rights & Attribution');

  const LegalDoc(this.slug, this.shortLabel, this.title);

  /// The URL segment — `/legal/<slug>`.
  final String slug;

  /// What the footer prints. Short because three of them share one row that has
  /// to survive 2.0x text scale at 600px.
  final String shortLabel;

  /// What the page prints.
  final String title;

  static LegalDoc? fromSlug(String? slug) {
    for (final d in LegalDoc.values) {
      if (d.slug == slug) return d;
    }
    return null;
  }

  List<LegalBlock> get blocks => switch (this) {
    LegalDoc.privacy => kPrivacyBlocks,
    LegalDoc.terms => kTermsBlocks,
    LegalDoc.rights => kRightsBlocks,
  };
}

/// The date the wording last changed, for all three documents.
///
/// One date rather than three: they cross-reference each other, so a reader
/// comparing them wants to know they are looking at one consistent set. **Move
/// it in the same commit as any wording change** — text that moves without this
/// date moving is the review failure to look for, and it is the only thing here
/// a test cannot catch.
const String kLegalLastUpdated = '28 September 2026';

// ---------------------------------------------------------------------------
// Privacy
// ---------------------------------------------------------------------------

const List<LegalBlock> kPrivacyBlocks = [
  LegalParagraph(
    'This describes what Secret-Sauce actually stores and who can see it. It is '
    'written against this application rather than adapted from a template, so '
    'everything named below is a real table, a real column or a real setting.',
  ),

  LegalHeading('What we hold'),
  LegalBullets([
    'Your account: an email address and a hashed password, held by Supabase '
        'Auth. We never receive or store your password itself.',
    'Your profile: a display name, an optional avatar image and an optional '
        'bio. All three are public.',
    'Your recipes: titles, descriptions, ingredients, steps, timings, photos, '
        'tags and the full version history of every edit you save. A recipe is '
        'private until you choose to publish it.',
    'Your engagement: which recipes you liked, saved and rated.',
    'Your reading: one row each time a signed-in account opens a recipe, keyed '
        'to your profile. This is the item most people would not guess we keep, '
        'which is exactly why it is listed. It is what produces a recipe view '
        'count and what feeds the trending lists. Visits by signed-out '
        'visitors are recorded without any account attached and are not counted '
        'towards a recipe view count at all.',
    'Images you upload, stored in a folder namespaced to your account.',
  ]),
  LegalParagraph(
    'There is no analytics SDK, no advertising identifier, no third-party '
    'tracker and no cookie banner, because there is nothing to consent to: '
    'the only thing stored in your browser is the token that keeps you signed '
    'in.',
  ),

  LegalHeading('Where it lives'),
  LegalParagraph(
    'All of it is held in a Supabase project — Postgres, Auth and Storage — '
    'running on Amazon Web Services in ${LegalFacts.hostingRegion}. Supabase is '
    'our only processor. Nothing is sold, and nothing is shared with an '
    'advertiser or a data broker.',
  ),

  LegalHeading('Who can see what'),
  LegalBullets([
    'A private recipe is visible to you and to anyone you explicitly share it '
        'with. Nobody else, including other signed-in users.',
    'A public recipe is visible to everyone, including people who are not '
        'signed in.',
    'Your display name, avatar and bio are public, as is the number of public '
        'recipes you have and the score derived from engagement with them.',
    'Your likes and saves are yours alone. A rating you give contributes to a '
        'recipe average that is public; the individual rating is not published '
        'beside your name.',
  ]),
  LegalParagraph(
    'This is enforced in the database by row-level security, not by hiding '
    'buttons in the interface. A request for a recipe you may not see returns '
    'nothing, whatever the request looks like.',
  ),

  LegalHeading('Deleting your account'),
  LegalParagraph(
    'Deleting your account deletes your profile and, with it, every recipe you '
    'own and their versions, images, tags and shares. There is one exception '
    'and it is stated because it is true rather than because it is flattering: '
    'the reading rows described above are kept with the account reference '
    'removed. They become anonymous rows that cannot be traced back to you, '
    'and the view counts they already contributed to do not go down.',
  ),

  LegalHeading('Your rights'),
  LegalParagraph(
    'You can ask for a copy of what we hold about you, ask for it to be '
    'corrected, ask for it to be deleted, or object to how it is used. Write to '
    '${LegalFacts.contactEmail} and we will answer. Depending on where you '
    'live, you may also have the right to complain to a data protection '
    'authority.',
  ),

  LegalHeading('Chefs credited from the public web'),
  LegalParagraph(
    'Some chef pages on Secret-Sauce describe people who have never signed up. '
    'They exist because a recipe published elsewhere is credited to them, and '
    'a credit with no page behind it is not a credit. Such a page holds a name, '
    'the recipes credited to that name and a link to where each was published — '
    'no invented biography, no invented photograph, and no ranking: these pages '
    'are deliberately absent from the chef leaderboard, because ranking someone '
    'by engagement they never sought is not something to do by accident.',
  ),
  LegalParagraph(
    'If one of those pages is you, two things are available and both start at '
    '${LegalFacts.contactEmail}: you can claim it, which transfers the page and '
    'everything on it to your account, or you can ask for it to be removed. '
    'Removal is recorded so that a later crawl cannot bring it back. The '
    'Content Rights page describes the process in full.',
  ),

  LegalHeading('Children'),
  LegalParagraph(
    'Secret-Sauce is not directed at children, and we do not knowingly collect '
    'information from anyone under the age at which they can consent for '
    'themselves where they live. If you believe a child has an account here, '
    'write to ${LegalFacts.contactEmail} and we will remove it.',
  ),

  LegalHeading('Changes'),
  LegalParagraph(
    'The date at the top of this page moves whenever the wording does. There is '
    'no separate archive yet; if that changes, this paragraph will say where it '
    'is.',
  ),

  LegalHeading('Contact'),
  LegalParagraph('${LegalFacts.entity} — ${LegalFacts.contactEmail}'),
];

// ---------------------------------------------------------------------------
// Terms
// ---------------------------------------------------------------------------

const List<LegalBlock> kTermsBlocks = [
  LegalParagraph(
    'These terms are the agreement between you and ${LegalFacts.entity} for '
    'your use of Secret-Sauce. Using the app means accepting them.',
  ),

  LegalHeading('Your account'),
  LegalParagraph(
    'You need an account to write, save, rate or share a recipe. Reading public '
    'recipes needs nothing. Keep your password to yourself, give us an address '
    'you can actually receive mail at, and tell us if you think someone else is '
    'using your account.',
  ),

  LegalHeading('Your recipes stay yours'),
  LegalParagraph(
    'You keep ownership of everything you write and every photograph you '
    'upload. You grant ${LegalFacts.entity} a non-exclusive, worldwide, '
    'royalty-free licence to store it and to display it inside Secret-Sauce, '
    'for the purpose of running Secret-Sauce. That licence exists so the app '
    'can show your recipe to the people you intend to see it, and it does not '
    'extend to selling your content, licensing it to anyone else, or using it '
    'outside the app.',
  ),

  LegalHeading('Publishing a recipe publicly means it can be forked'),
  LegalParagraph(
    'This is the one term that is specific to how Secret-Sauce works, so it is '
    'stated plainly rather than buried. Forking is the heart of the product: '
    'any signed-in user can take a public recipe, make an independent copy of '
    'it, and change that copy however they like.',
  ),
  LegalBullets([
    'A fork never modifies your recipe. Your version, its history and its '
        'numbers are untouched.',
    'A fork keeps a permanent link back to the exact version it was copied '
        'from, so the lineage and the credit travel with it.',
    'The person who forked it owns their copy, including their changes.',
    'You cannot un-fork a recipe after the fact. A copy someone already made is '
        'theirs.',
  ]),
  LegalParagraph(
    'By setting a recipe to public you are granting every other user permission '
    'to fork it on those terms. If that is not what you want, keep the recipe '
    'private, or share it with named people instead — a shared recipe is not '
    'public and cannot be forked by anyone else.',
  ),

  LegalHeading('Nutrition, allergens and food safety'),
  LegalParagraph(
    'Nutrition figures in Secret-Sauce come from more than one place and none '
    'of them is a guarantee. A cook may type them in by hand. The app may '
    'estimate them by matching an ingredient list against a small internal food '
    'registry — an estimate that silently contributes nothing for any '
    'ingredient it cannot resolve, and which the app tells you about by listing '
    'what it did not count. Where a recipe came from elsewhere, the figures are '
    'whatever the original publisher stated.',
  ),
  LegalParagraph(
    'Do not rely on any of it for a medical, dietary or allergen decision. '
    'Secret-Sauce does not identify allergens and does not claim a recipe is '
    'free of anything. Cooking times and temperatures are one cook describing '
    'their own kitchen; judging whether food is safely cooked is yours to do.',
  ),

  LegalHeading('What you may not do'),
  LegalBullets([
    'Upload text or photographs you do not have the right to publish.',
    'Impersonate another person, or claim a chef page that is not you.',
    'Bulk-download or systematically scrape the app, or resell its content.',
    'Try to get at private recipes, other accounts or anything else you have '
        'not been given access to.',
    'Use the app to harass anyone, or to publish anything unlawful.',
  ]),
  LegalParagraph(
    'We can remove content or close an account that does these things.',
  ),

  LegalHeading('Recipes credited to other people'),
  LegalParagraph(
    'Some content in Secret-Sauce originates elsewhere on the web and is shown '
    'with its credit and a link to the original. The Content Rights page '
    'describes exactly what is stored, what is deliberately not stored, and how '
    'to ask for something to be removed.',
  ),

  LegalHeading('Availability'),
  LegalParagraph(
    'Secret-Sauce is pre-release software. It may be unavailable, it may change '
    'without notice, and data may be lost. Keep your own copy of anything you '
    'cannot afford to lose. The service is provided as-is, without warranties '
    'of any kind.',
  ),

  LegalHeading('Liability'),
  LegalParagraph(
    'To the fullest extent the law allows, ${LegalFacts.entity} is not liable '
    'for indirect or consequential loss, for lost data, or for anything arising '
    'from your reliance on nutrition information or cooking instructions in the '
    'app. Nothing here limits liability that cannot lawfully be limited.',
  ),

  LegalHeading('Ending it'),
  LegalParagraph(
    'You can delete your account at any time; what that removes and what it '
    'leaves behind is set out in the Privacy Policy. We can suspend or close an '
    'account that breaks these terms.',
  ),

  LegalHeading('Governing law'),
  LegalParagraph(LegalFacts.governingLaw),

  LegalHeading('Changes'),
  LegalParagraph(
    'The date at the top moves whenever these terms do. Continuing to use the '
    'app after a change means accepting it.',
  ),

  LegalHeading('Contact'),
  LegalParagraph('${LegalFacts.entity} — ${LegalFacts.contactEmail}'),
];

// ---------------------------------------------------------------------------
// Rights
// ---------------------------------------------------------------------------

const List<LegalBlock> kRightsBlocks = [
  LegalParagraph(
    'Secret-Sauce shows recipes that people other than us wrote. This page says '
    'what we store, what we deliberately do not, and how to make us stop.',
  ),

  LegalHeading('The short version'),
  LegalParagraph(
    'We keep the functional part of a recipe — the ingredients, the quantities '
    'and the steps — with the credit and a link to the original attached. We do '
    'not copy the writing around it, and we never re-host a photograph.',
  ),

  LegalHeading('Where recipes come from'),
  LegalBullets([
    'Written by people using Secret-Sauce. Those belong to their authors; the '
        'Terms describe the licence they grant us.',
    'Written by us, as the Secret Sauce Kitchen. The pictures on those '
        'recipes are AI-generated images, not photographs of the dish, and '
        'each one is marked “AI”.',
    'Harvested from the public web, with the credit attached. This is the part '
        'the rest of this page is about.',
  ]),

  LegalHeading('What travels with a harvested recipe'),
  LegalBullets([
    'The chef named on the page.',
    'The group that published it — a brand, a restaurant, a magazine, a '
        'community site or the chef’s own site.',
    'The address it came from, so a reader can go and read the original.',
    'When we fetched it.',
  ]),
  LegalParagraph(
    'The chef and the publisher are recorded separately and neither is ever '
    'inferred from the other. A recipe on a brand’s site written by a named '
    'person is credited to both; one with no byline is credited to the '
    'publisher and to nobody else.',
  ),

  LegalHeading('What we do not copy'),
  LegalBullets([
    'Photographs. A picture is the most clearly protected thing on a recipe '
        'page and the easiest to get wrong, so we take a strict line: an image '
        'is either shown from the publisher’s own address or not shown at '
        'all. We do not copy it onto our servers and we do not proxy it, which '
        'would be the same copy wearing a link’s clothes. A publisher who '
        'would rather we showed no image can have that, per source, on request.',
    'Headnotes, stories and editorial writing. That is the part of a recipe '
        'page that is unambiguously someone’s writing, so we link to it '
        'instead of reproducing it.',
    'Anything a publisher has asked us to stop showing.',
  ]),

  LegalHeading('How we crawl, and what stops us'),
  LegalBullets([
    'Every address is checked against the site’s own robots.txt before it '
        'is requested, evaluated the way the standard says — longest matching '
        'rule wins, and an explicit allow beats an equally specific disallow.',
    'If robots.txt cannot be reached, we treat that as no. An unknown answer is '
        'not permission.',
    'A Crawl-delay is honoured exactly as stated. Some sites ask for ten or '
        'thirty seconds between requests, and we are correspondingly slow there '
        'by instruction rather than by accident.',
    'One request at a time per site, always.',
    'A site that refuses this client while serving a browser is left alone. '
        'Getting past that would mean disguising who is asking, and a site '
        'saying no is a site that gets no requests.',
    'A site that keeps returning nothing useful is dropped, so we stop spending '
        'its bandwidth.',
  ]),

  LegalHeading('Asking us to stop'),
  LegalParagraph(
    'Write to ${LegalFacts.contactEmail} with the address or addresses '
    'concerned. You do not need to prove you own the site to ask us to stop '
    'crawling it, and you do not need to send a formal notice to ask us to take '
    'something down. We aim to answer within five working days.',
  ),
  LegalParagraph(
    'A removal is recorded permanently rather than simply deleted, so that a '
    'later crawl cannot quietly bring the same page back — a takedown that '
    'undoes itself is not a takedown. We can also switch a whole source to '
    'showing no images, or remove it from the crawl list entirely.',
  ),

  LegalHeading('Copycat recipes name a restaurant; they do not speak for it'),
  LegalParagraph(
    'A cook’s reconstruction of a restaurant dish is credited to that cook '
    'and to the site that published it. The restaurant is recorded as something '
    'the recipe mentions, never as its publisher, because writing a chain’s '
    'name into the publisher field would put words in that chain’s mouth '
    'about a recipe it had nothing to do with.',
  ),

  LegalHeading('If we have got something wrong'),
  LegalParagraph(
    'Attribution at scale gets things wrong: a byline can be missed, two people '
    'with the same first name can be conflated, a credit can land on the wrong '
    'site. Tell us at ${LegalFacts.contactEmail} and we will fix it. A wrong '
    'credit is worth reporting even when nothing is being copied — the point of '
    'the credit is that it is right.',
  ),

  LegalHeading('Contact'),
  LegalParagraph('${LegalFacts.entity} — ${LegalFacts.contactEmail}'),
];
