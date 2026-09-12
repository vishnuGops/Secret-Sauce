// Turn off sources that are spending requests and returning nothing.
//
//   node prune.mjs --dry
//   node prune.mjs                 # writes enabled:false + a reason into sources.json
//
// A probe samples three URLs; a harvest runs thousands. Some sites pass the probe and
// then yield almost nothing — the sitemap is mostly non-recipe posts, or the recipe
// markup is only on the handful of pages the sample happened to hit. Left alone, one
// of those costs 2,700 requests to learn what 60 would have told us, and those are
// requests the site did not need to serve.
//
// The thresholds are deliberately forgiving, because a false positive here silently
// deletes a source from the corpus:
//
//   attempted >= 80 and kept == 0      -> off. Nothing, not "not much".
//   attempted >= 250 and rate < 4%     -> off. A long tail that is not worth the load.
//
// `enabled: false` is never flipped back by `promote.mjs` (it preserves a hand-set
// value), so a decision made here survives a re-probe. Reverse it by hand.
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const CORPUS = resolve(HERE, '../../corpus');

const readJson = async (p, fb) => {
  try {
    return JSON.parse(await readFile(p, 'utf8'));
  } catch {
    return fb;
  }
};

async function main() {
  const dry = process.argv.includes('--dry');
  const reg = await readJson(resolve(CORPUS, 'sources.json'), null);
  if (!reg) throw new Error('no sources.json');

  const off = [];
  const keep = [];
  for (const s of reg.sources) {
    if (s.enabled === false) continue;
    const st = await readJson(resolve(CORPUS, '_state', s.slug + '.json'), null);
    if (!st) continue;
    const attempted = (st.done || []).length;
    const kept = st.kept || 0;
    const rate = attempted ? kept / attempted : 0;
    const reason =
      attempted >= 80 && kept === 0
        ? 'no recipes in ' + attempted + ' pages'
        : attempted >= 250 && rate < 0.04
          ? 'yield ' + (rate * 100).toFixed(1) + '% over ' + attempted + ' pages'
          : null;
    if (reason) {
      off.push({ s, reason, attempted, kept, failed: st.failed || {} });
    } else if (attempted > 50) {
      keep.push({ slug: s.slug, attempted, kept, rate });
    }
  }

  for (const o of off) {
    console.log(
      'OFF  ' + o.s.slug.padEnd(36) + o.reason.padEnd(34) +
      Object.entries(o.failed).map(([k, v]) => k + '=' + v).join(' ').slice(0, 60),
    );
    if (!dry) {
      o.s.enabled = false;
      o.s.disabledReason = o.reason;
      o.s.disabledAt = new Date().toISOString().slice(0, 10);
    }
  }

  if (!dry && off.length) {
    reg.updatedAt = new Date().toISOString();
    await writeFile(resolve(CORPUS, 'sources.json'), JSON.stringify(reg, null, 2) + '\n', 'utf8');
  }

  const worst = keep.sort((a, b) => a.rate - b.rate).slice(0, 8);
  console.log(
    '\n' + (dry ? 'would disable ' : 'disabled ') + off.length + ' source(s); ' +
    keep.length + ' still producing',
  );
  if (worst.length) {
    console.log('lowest yield still enabled:');
    for (const w of worst) {
      console.log('  ' + w.slug.padEnd(36) + (w.rate * 100).toFixed(0) + '%  ' + w.kept + '/' + w.attempted);
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
