// Restaurant and chain detection.
//
// A large share of the corpus is "copycat" cooking — a blogger's reconstruction of
// a dish a restaurant sells. The restaurant is the thing a reader searches for, and
// it is present only as prose: "Olive Garden Zuppa Toscana", "Copycat Chipotle
// Barbacoa". Nothing in schema.org carries it.
//
// So it is derived, and derived is labelled as such: the match lands in
// `attribution.restaurantMentioned` with `confidence`, never in `attribution.group`,
// which stays the site that actually published the page. A copycat recipe is not
// published BY the chain, and conflating the two would put words in a brand's mouth.
//
// Matching is whole-phrase and case-insensitive, with two guards learned from the
// first pass:
//   - Short generic names ("Subway", "Wendy's", "Five Guys") only count next to a
//     copycat cue, or a recipe about a metro station sandwich becomes a chain match.
//   - Possessives and the "-style"/"copycat" framing are part of the cue, not noise.

export const CHAINS = [
  // US fast food
  "McDonald's", 'Burger King', "Wendy's", 'Taco Bell', 'KFC', 'Kentucky Fried Chicken',
  'Chick-fil-A', 'Popeyes', 'Subway', 'Arby’s', "Arby's", 'Sonic Drive-In', 'Jack in the Box',
  'Whataburger', 'In-N-Out', 'Five Guys', 'Shake Shack', 'Culver’s', "Culver's",
  "Hardee's", "Carl's Jr", 'White Castle', "Zaxby's", "Bojangles", 'Raising Cane’s',
  "Raising Cane's", 'Del Taco', 'Chipotle', 'Qdoba', 'Moe’s Southwest Grill',
  'Panda Express', 'Panera', 'Panera Bread', 'Jimmy John’s', "Jimmy John's", 'Firehouse Subs',
  'Jersey Mike’s', "Jersey Mike's", 'Potbelly', 'Quiznos', 'Blimpie', 'Church’s Chicken',
  'Wingstop', 'Buffalo Wild Wings', 'Dave’s Hot Chicken', 'Nando’s', "Nando's",
  // Pizza
  "Domino's", 'Pizza Hut', 'Papa John’s', "Papa John's", 'Little Caesars', 'Sbarro',
  'California Pizza Kitchen', 'Marco’s Pizza', 'Pizza Express', 'Blaze Pizza',
  // Coffee / bakery / dessert
  'Starbucks', 'Dunkin', "Dunkin' Donuts", 'Krispy Kreme', 'Tim Hortons', 'Peet’s Coffee',
  'Costa Coffee', 'Caribou Coffee', 'Dutch Bros', 'Cinnabon', 'Auntie Anne’s',
  'Baskin-Robbins', 'Dairy Queen', 'Cold Stone Creamery', 'Ben & Jerry’s', "Ben & Jerry's",
  'Haagen-Dazs', 'Häagen-Dazs', 'Jamba Juice', 'Smoothie King', 'Orange Julius',
  'Insomnia Cookies', 'Crumbl', 'Nothing Bundt Cakes', 'Magnolia Bakery', 'Levain Bakery',
  'Greggs', 'Pret a Manger', 'Le Pain Quotidien', 'Panera',
  // Casual dining US
  'Olive Garden', 'Applebee’s', "Applebee's", 'Chili’s', "Chili's", 'TGI Fridays',
  'Red Lobster', 'Outback Steakhouse', 'Texas Roadhouse', 'LongHorn Steakhouse',
  'Cheesecake Factory', 'The Cheesecake Factory', 'P.F. Chang’s', "P.F. Chang's",
  'Cracker Barrel', 'Denny’s', "Denny's", 'IHOP', 'Waffle House', 'Bob Evans',
  'Golden Corral', 'Ruby Tuesday', 'Red Robin', 'Hooters', 'Buca di Beppo', 'Carrabba’s',
  'Maggiano’s', 'Bonefish Grill', 'Bahama Breeze', 'Yard House', 'BJ’s Restaurant',
  'Hard Rock Cafe', 'Rainforest Cafe', 'Benihana', 'Ruth’s Chris', 'Morton’s',
  'Fogo de Chão', 'Cheddar’s', 'Logan’s Roadhouse', 'Season 52', 'Eddie V’s',
  // Mexican / Asian / other chains
  'Taco Cabana', 'El Pollo Loco', 'Baja Fresh', 'Rubio’s', 'Taco John’s',
  'Pei Wei', 'Noodles & Company', 'Genghis Grill', 'Yoshinoya', 'Wagamama', 'Itsu',
  'Din Tai Fung', 'Yo! Sushi', 'Wasabi', 'Ippudo', 'Jollibee', 'Max’s Restaurant',
  // Grocery / retail kitchens and food halls
  'Trader Joe’s', "Trader Joe's", 'Costco', 'Whole Foods', 'Wegmans', 'Publix',
  'Cracker Barrel', 'IKEA', 'Disney World', 'Disneyland', 'Disney Parks', 'Universal Studios',
  // UK / IE / AU / CA
  'Wetherspoon', 'Harvester', 'Toby Carvery', 'Pizza Express', 'Bella Italia', 'Zizzi',
  'Prezzo', 'Byron', 'GBK', 'Gourmet Burger Kitchen', 'Leon', 'Wahaca', 'Dishoom',
  'Hawksmoor', 'The Ivy', 'Gordon Ramsay', 'Jamie’s Italian', 'Carluccio’s',
  'Bill’s', 'Cafe Rouge', 'Giraffe', 'Nando’s', 'Greggs', 'Hungry Jack’s',
  'Guzman y Gomez', 'Grill’d', 'Red Rooster', 'Boston Pizza', 'Swiss Chalet',
  'Harvey’s', 'St-Hubert', 'A&W',
  // Fine dining / chef restaurants worth naming when a recipe credits them
  'The French Laundry', 'Per Se', 'Noma', 'Osteria Francescana', 'El Bulli', 'Alinea',
  'Eleven Madison Park', 'Momofuku', 'Nobu', 'Zuni Cafe', 'Chez Panisse', 'The Fat Duck',
  'Le Bernardin', 'Gaggan', 'Central', 'Mugaritz', 'Arzak', 'Tickets', 'Dinner by Heston',
  'The Ledbury', 'Core by Clare Smyth', 'Sketch', 'St. John', 'Ottolenghi', 'Roka', 'Zuma',
  // Second pass, added once the corpus was large enough to show which chains people
  // actually cook at home. Regional US first — a copycat audience is regional.
  "Portillo's", 'Portillo’s', 'Skyline Chili', 'Gold Star Chili', 'Steak n Shake',
  'Steak ’n Shake', 'Freddy’s', 'Runza', 'Braum’s', 'Krystal', 'Checkers',
  'Rally’s', 'Biscuitville', 'Cook Out', 'Tudor’s Biscuit World', 'Pal’s',
  'Halo Burger', 'Original Tommy’s', 'Fatburger', 'The Habit', 'Farmer Boys',
  'Nathan’s Famous', 'Papa Murphy’s', 'Godfather’s Pizza', 'Round Table Pizza',
  'Mod Pizza', 'Donatos', 'Casey’s', 'Cicis', 'Hungry Howie’s',
  'Jet’s Pizza', 'Lou Malnati’s', 'Giordano’s', 'Uno Pizzeria',
  'Einstein Bros', 'Bruegger’s', 'Panera Bread', 'Corner Bakery', 'Which Wich',
  'Charleys', 'Schlotzsky’s', 'McAlister’s Deli', 'Newk’s', 'Jason’s Deli',
  'Boston Market', 'El Torito', 'On The Border', 'Chuy’s', 'Torchy’s Tacos',
  'Velvet Taco', 'Tijuana Flats', 'Pollo Tropical', 'Cava', 'Sweetgreen', 'Dig Inn',
  'Torchy’s', "Torchy's", 'Portillos',
  'Shake Shack', 'Portillos', 'Carl’s Jr', 'Long John Silver’s', 'Captain D’s',
  'Joe’s Crab Shack', 'Bubba Gump', 'Landry’s', 'Saltgrass', 'Black Angus',
  'Claim Jumper', 'Mimi’s Cafe', 'Marie Callender’s', 'Village Inn', 'Perkins',
  'Shoney’s', 'Friendly’s', 'Big Boy', 'Steak ’n Shake', 'Sizzler',
  'Furr’s', 'Luby’s', 'Piccadilly', 'Old Country Buffet', 'Hometown Buffet',
  // UK / IE
  'Wagamama', 'Franco Manca', 'Honest Burgers', 'Five Guys UK', 'Rosa’s Thai',
  'Busaba', 'Yo Sushi', 'Itsu', 'Chipotle UK', 'Pizza Pilgrims',
  'Flat Iron', 'Dishoom', 'Padella', 'Bancone', 'Homeslice', 'Pieminister',
  'Costa', 'Caffe Nero', 'Starbucks UK', 'Greggs', 'Subway UK', 'Domino’s UK',
  'Wimpy', 'Morley’s', 'Chicken Cottage', 'German Doner Kebab', 'Bella Italia',
  // Canada / Australia / NZ / Asia
  'Tim Hortons', 'Harvey’s', 'Swiss Chalet', 'New York Fries', 'Mary Brown’s',
  'Hungry Jack’s', 'Red Rooster', 'Oporto', 'Zambrero', 'Betty’s Burgers',
  'Schnitz', 'Roll’d', 'Fergburger', 'Burger Fuel',
  'Haidilao', 'Tim Ho Wan', 'Din Tai Fung', 'Paradise Biryani', 'Saravana Bhavan',
  'Haldiram’s', 'Bikanervala', 'Karim’s', 'Barbeque Nation', 'Wow Momo',
  'Mad Over Donuts', 'Faasos', 'Behrouz', 'Chaayos', 'Cafe Coffee Day',
  'Kyochon', 'Bonchon', 'Lotteria', 'MOS Burger', 'Ichiran',
  'Sukiya', 'Matsuya', 'CoCo Ichibanya', 'Marugame Udon', 'Pepper Lunch',
];

// Two chains were REMOVED from the list rather than gated: "BBQ Chicken" (a Korean
// chain) matched 852 recipes for barbecue chicken, and "Tortilla" (a UK burrito chain)
// matched 255 recipes containing tortillas. A name that is a common dish before it is a
// restaurant cannot be rescued by a cue — "BBQ chicken, restaurant style" is still a
// dish — so the honest answer is not to carry it.

/** Names too generic to match on their own; they need a copycat cue nearby. */
const NEEDS_CUE = new Set(
  ['subway', 'central', 'tickets', 'core by clare smyth', 'costco', 'publix', 'wegmans',
    'a&w', 'leon', 'byron', 'gbk', 'per se', 'sketch', 'st. john', 'whole foods', 'ikea',
    'five guys', 'wasabi', 'harvester', 'giraffe', 'panera',
    // `chipotle` is a chilli before it is a burrito chain, and the chilli is far more
    // common in a recipe title. Matching it bare put the chain on 35 recipes, most of
    // them chipotle mayo. With a cue required, "Copycat Chipotle Barbacoa" still counts
    // and "chipotle black bean soup" does not.
    'chipotle', 'guinness', 'nobu', 'momofuku', 'hooters',
    // Second-pass additions that are ordinary words before they are chains.
    'cava', 'dig inn', 'the habit', 'checkers', 'perkins', 'big boy', 'village inn',
    'cook out', 'schnitz', 'padella', 'bancone', 'homeslice', 'tortilla', 'costa',
    'oporto', 'runza', 'krystal', 'landry’s', "landry's", 'donatos', 'charleys'],
);

// Two different jobs, so two different tests.
//
// COPYCAT answers "is this page framed as a copy of a restaurant's dish". It has to
// be narrow: the first version also accepted `homemade`, `at home`, `the best` and
// `famous`, which made "Homemade Chocolate Chip Cookies" a copycat recipe and put
// the flag on thousands of ordinary bakes.
//
// CUE is the looser one, and it is only ever used to *admit a name we already
// matched* — "Subway" next to "copycat" or "-style" is the sandwich chain; "Subway"
// on its own is a train. A loose test is safe there and unsafe in COPYCAT.
const COPYCAT = /\b(copycat|copy ?cat|knock-?off|clone of|dupe of|secret menu)\b/i;

const CUE = /\b(copycat|copy ?cat|knock-?off|clone of|dupe of|secret menu|style|inspired by|better than|at home|famous|restaurant)\b/i;

const norm = (s) =>
  String(s || '')
    .replace(/[‘’ʼ]/g, "'")
    .replace(/\s+/g, ' ')
    .trim();

const escapeRe = (s) => [...s].map((c) => ('.+?^${}()|[]\\*'.includes(c) ? '\\' + c : c)).join('');

// Built once: chain name -> word-boundary regex over the normalised text.
const MATCHERS = CHAINS.map((name) => {
  const n = norm(name);
  return {
    name,
    key: n.toLowerCase(),
    // `\b` does not fire after an apostrophe-s or a `-`, so bound on a non-word class.
    re: new RegExp('(^|[^A-Za-z0-9])' + escapeRe(n) + '($|[^A-Za-z0-9])', 'i'),
  };
});

/**
 * Chains named anywhere in the given text. `confidence` is 'high' when the phrase is
 * distinctive on its own, 'cue' when a generic name was accepted only because a
 * copycat cue sits in the same text.
 */
export function detectBrands(...parts) {
  const text = norm(parts.filter(Boolean).join(' — '));
  if (!text) return [];
  const hasCue = CUE.test(text);
  const out = [];
  const seen = new Set();
  for (const m of MATCHERS) {
    if (seen.has(m.key)) continue;
    if (!m.re.test(text)) continue;
    const generic = NEEDS_CUE.has(m.key);
    if (generic && !hasCue) continue;
    seen.add(m.key);
    out.push({ name: m.name, confidence: generic ? 'cue' : 'high', key: m.key });
  }
  // The list carries spelling variants of one chain ("Portillo's" / "Portillos") and
  // longer names that contain shorter ones ("Torchy's Tacos" / "Torchy's"). Keep the
  // most specific match and drop anything contained in it, or one restaurant is
  // reported twice under two names.
  const keys = out.map((o) => o.key.replace(/[^a-z0-9]/g, ''));
  return out
    .filter((o, i) => !keys.some((k, j) => j !== i && k.length > keys[i].length && k.includes(keys[i])))
    .map(({ key, ...rest }) => rest);
}

/** True when the page frames itself as a copy of someone else's dish. */
export const isCopycat = (...parts) => COPYCAT.test(norm(parts.filter(Boolean).join(' ')));
