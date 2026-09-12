// Per-domain crawl policy, read off each site's robots.txt and content signals
// before batch 2 was scraped, and recorded here so the constraint travels with
// the code instead of living in someone's memory.
//
// Two of these are real obligations, not defaults:
//
//   seonkyounglongest.com declares `Crawl-delay: 30`. Ten recipes therefore take
//   five minutes, and that is the correct speed.
//
//   justonecookbook.com declares `Content-Signal: search=yes, ai-train=no,
//   use=reference`. This corpus is reference material for internal app testing
//   and is never used as training data or redistributed, which is consistent with
//   that signal — but the signal is stamped onto every recipe captured from the
//   site so the constraint is visible at the row level, not just here.

export const DEFAULT_DELAY_MS = 1500;

export const POLICY = {
  'bbc.co.uk': {
    delayMs: 1500,
    robots: 'allows /food/; no crawl-delay',
    rights: 'BBC Food. Functional content plus a link, for internal app testing. Not redistributed.',
  },
  'mygreekdish.com': {
    delayMs: 2000,
    robots: 'Disallow: (empty) — all allowed',
    rights: 'My Greek Dish. Functional content plus a link, for internal app testing. Not redistributed.',
  },
  'hungryhuy.com': {
    delayMs: 2000,
    robots: 'Disallow: (empty) — all allowed',
    rights: 'Hungry Huy. Functional content plus a link, for internal app testing. Not redistributed.',
  },
  'feelgoodfoodie.net': {
    delayMs: 2000,
    robots: 'allows recipe paths; /wp-admin/ and /signup/ disallowed',
    rights: 'Feel Good Foodie. Functional content plus a link, for internal app testing. Not redistributed.',
  },
  'cheflolaskitchen.com': {
    delayMs: 2000,
    robots: 'allows recipe paths; /wp-admin/, /wp-json/ and query URLs disallowed',
    rights: "Chef Lola's Kitchen. Functional content plus a link, for internal app testing. Not redistributed.",
  },
  'easyanddelish.com': {
    delayMs: 2000,
    robots: 'Disallow: (empty) — all allowed',
    rights: 'Easy and Delish. Functional content plus a link, for internal app testing. Not redistributed.',
  },
};

const hostOf = (url) => {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return '';
  }
};

/** The policy for a URL, matched on the registrable domain suffix. */
export function policyFor(url) {
  const host = hostOf(url);
  const hit = Object.keys(POLICY).find((d) => host === d || host.endsWith('.' + d));
  return hit ? { domain: hit, ...POLICY[hit] } : { domain: host, delayMs: DEFAULT_DELAY_MS };
}

export const delayFor = (url) => policyFor(url).delayMs ?? DEFAULT_DELAY_MS;
