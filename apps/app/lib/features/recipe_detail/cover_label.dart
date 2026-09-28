import 'package:core/core.dart';

/// What a screen reader hears for a recipe's cover (UX-047), shared by both
/// detail layouts so they cannot disagree.
///
/// "Photo of …" was true of every cover until generated ones existed; saying it
/// of a generated image is the one claim DESIGN §2.2 exists to avoid, so a
/// generated cover says what it is instead.
String coverAltText(Recipe recipe) =>
    recipe.coverIsGenerated
        ? 'AI-generated image of ${recipe.title}'
        : 'Photo of ${recipe.title}';
