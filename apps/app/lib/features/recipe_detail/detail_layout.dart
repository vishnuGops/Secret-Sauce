/// Layout tokens for the v2 (expanded) recipe-detail page.
///
/// Their own file because the page, the ingredients rail and the method column
/// all measure against them — putting them beside any one of those widgets
/// makes the other two import that widget's file for a number, which is an
/// import cycle in exchange for nothing.
library;

/// Content column width on the v2 page — the canvas's `.page` measure. Content
/// is centred inside it, so no line runs the window's full width.
const double kDetailPageWidth = 1140;

/// Base width of the ingredients rail at 1.0× text scale; the method column
/// takes whatever is left.
const double kDetailRailWidth = 352;

/// Width of the quantity column inside the rail at 1.0× text scale — the gutter
/// that lets the numbers scan vertically while shopping.
const double kIngredientQuantityGutter = 86;

/// How far the rail and its gutter may grow with text scale.
///
/// They are bounded rather than fixed because a fixed 352px column turns every
/// ingredient name into a three-line wrap at 2.0× (Gotcha 22); capped because
/// past this the method column would be narrower than the rail that exists to
/// support it.
const double kDetailRailMaxScale = 1.4;
