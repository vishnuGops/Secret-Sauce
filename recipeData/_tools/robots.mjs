// robots.txt fetch + parse + cache, so the scale harvester asks permission once
// per host instead of never.
//
// Batch 1 and 2 recorded each site's rules by hand in `crawl_policy.mjs`. That does
// not survive going from 6 domains to dozens: the note gets copied, the site
// changes, and nothing notices. This reads the real file, evaluates the real rules,
// and caches the answer for the run.
//
//   const r = await robotsFor('https://example.com/recipes/x');
//   r.allows('/recipes/x')   // boolean
//   r.crawlDelayMs           // number | null
//   r.sitemaps               // string[]
//
// Group selection is deliberately conservative. We present a browser user-agent, so
// the `*` group is the one that applies to us; where a host names a crawler we are
// not, its rules are ignored. A host that 404s its robots.txt is treated as
// allow-all (RFC 9309); a host that 5xx's or is unreachable is treated as
// DISALLOW-all, because an unreachable policy is not the same as an absent one.
import { fetchHtml } from './extract.mjs';

const CACHE = new Map();

/** One `User-agent:` group's rules. */
function emptyGroup() {
  return { agents: [], allow: [], disallow: [], crawlDelay: null };
}

export function parseRobots(txt) {
  const groups = [];
  const sitemaps = [];
  let current = null;
  let lastWasAgent = false;

  for (const rawLine of String(txt).split(/\r?\n/)) {
    const line = rawLine.replace(/#.*$/, '').trim();
    if (!line) continue;
    const idx = line.indexOf(':');
    if (idx < 0) continue;
    const field = line.slice(0, idx).trim().toLowerCase();
    const value = line.slice(idx + 1).trim();

    if (field === 'sitemap') {
      sitemaps.push(value);
      continue;
    }
    if (field === 'user-agent') {
      // Consecutive User-agent lines share one rule block.
      if (!current || !lastWasAgent) {
        current = emptyGroup();
        groups.push(current);
      }
      current.agents.push(value.toLowerCase());
      lastWasAgent = true;
      continue;
    }
    lastWasAgent = false;
    if (!current) continue;
    if (field === 'allow') current.allow.push(value);
    else if (field === 'disallow') current.disallow.push(value);
    else if (field === 'crawl-delay') {
      const n = Number(value.replace(',', '.'));
      if (Number.isFinite(n)) current.crawlDelay = n;
    }
  }
  return { groups, sitemaps };
}

const RE_SPECIALS = new Set(['.', '+', '?', '^', '$', '{', '}', '(', ')', '|', '[', ']', '\\']);

/** A robots path pattern -> RegExp. `*` is any run, `$` anchors the end. */
function patternToRegex(p) {
  let re = '';
  for (const ch of p) {
    if (ch === '*') re += '.*';
    else if (ch === '$') re += '$';
    else if (RE_SPECIALS.has(ch)) re += '\\' + ch;
    else re += ch;
  }
  return new RegExp('^' + re);
}

/** Longest-match wins; on a tie Allow wins (RFC 9309 2.2.2). */
function decide(group, path) {
  if (!group) return true;
  let best = { len: -1, allow: true };
  for (const [rules, allow] of [[group.allow, true], [group.disallow, false]]) {
    for (const rule of rules) {
      // `Disallow:` with an empty value means allow-all; it never wins a match.
      if (rule === '') continue;
      if (!patternToRegex(rule).test(path)) continue;
      const len = rule.replace(/\*/g, '').length;
      if (len > best.len || (len === best.len && allow)) best = { len, allow };
    }
  }
  return best.allow;
}

function selectGroup(groups, token) {
  const named = groups.find((g) => g.agents.includes(token));
  if (named) return named;
  return groups.find((g) => g.agents.includes('*')) || null;
}

export async function robotsFor(url, { token = '*' } = {}) {
  const origin = new URL(url).origin;
  if (CACHE.has(origin)) return CACHE.get(origin);

  const promise = (async () => {
    let txt = '';
    let status = 0;
    let reachable = true;
    try {
      const res = await fetchHtml(origin + '/robots.txt');
      status = res.status;
      txt = res.html;
    } catch {
      reachable = false;
    }

    // 4xx means no policy exists -> allow. 5xx or unreachable means the policy is
    // unknown, and unknown is not permission.
    const openField = reachable && status >= 400 && status < 500;
    const parsed = openField ? { groups: [], sitemaps: [] } : parseRobots(txt);
    const group = selectGroup(parsed.groups, token);
    const blind = !reachable || status >= 500;

    return {
      origin,
      status,
      reachable,
      fetchFailed: blind,
      raw: txt.slice(0, 20000),
      sitemaps: parsed.sitemaps,
      crawlDelaySec: group && group.crawlDelay != null ? group.crawlDelay : null,
      crawlDelayMs: group && group.crawlDelay != null ? Math.round(group.crawlDelay * 1000) : null,
      agentGroup: group ? group.agents.join(', ') : null,
      summary: blind
        ? 'robots.txt unreachable (' + status + ') — treated as disallow'
        : group
          ? 'allow=' + group.allow.length + ' disallow=' + group.disallow.length +
            (group.crawlDelay != null ? ' crawl-delay=' + group.crawlDelay : '')
          : openField
            ? 'no robots.txt (' + status + ') — allow all'
            : 'no matching group — allow all',
      allows(pathOrUrl) {
        if (blind) return false;
        let path = pathOrUrl;
        try {
          const u = new URL(pathOrUrl, origin);
          path = u.pathname + (u.search || '');
        } catch {
          /* already a path */
        }
        return decide(group, path);
      },
    };
  })();

  CACHE.set(origin, promise);
  return promise;
}
