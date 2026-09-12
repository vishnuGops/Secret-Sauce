// Reopen URLs a previous run closed out without an answer.
//
//   node repair_state.mjs --dry
//   node repair_state.mjs --only copykat
//
// The harvester's `done` set is "we have an answer about this URL". Before the
// backoff fix it also swallowed 429s and 5xxs, which are not answers — the site was
// asking us to come back. Those URLs can never be retried, because `done` records no
// reason and so cannot be filtered.
//
// This rebuilds `done` from the shard itself: a URL is done if its record is in the
// file. Everything else goes back into the queue, including pages that legitimately
// have no recipe — they will be re-fetched once and re-rejected, which is the price
// of not being able to tell the two apart after the fact. Run it with the harvester
// STOPPED.
import { readdir, readFile, writeFile, rm } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
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

const RETRYABLE = /^http-(429|5\d\d)$|^fetch-failed$/;

async function urlsInShard(file) {
  const out = new Set();
  try {
    const rl = createInterface({ input: createReadStream(file, 'utf8'), crlfDelay: Infinity });
    for await (const line of rl) {
      if (!line.trim()) continue;
      try {
        const r = JSON.parse(line);
        if (r.source) {
          if (r.source.sourceUrl) out.add(r.source.sourceUrl);
          if (r.source.finalUrl) out.add(r.source.finalUrl);
        }
      } catch {
        /* truncated tail */
      }
    }
  } catch {
    /* no shard yet */
  }
  return out;
}

async function main() {
  const argv = process.argv.slice(2);
  const dry = argv.includes('--dry');
  const onlyIdx = argv.indexOf('--only');
  const only = onlyIdx >= 0 ? argv[onlyIdx + 1] : null;
  const minIdx = argv.indexOf('--min');
  const minLost = minIdx >= 0 ? Number(argv[minIdx + 1]) : 20;

  let states = [];
  try {
    states = (await readdir(resolve(CORPUS, '_state'))).filter((f) => f.endsWith('.json'));
  } catch {
    console.log('no state');
    return;
  }

  let reopened = 0;
  for (const f of states) {
    const slug = f.replace(/\.json$/, '');
    if (only && !slug.includes(only)) continue;
    const stFile = resolve(CORPUS, '_state', f);
    const st = await readJson(stFile, null);
    if (!st || !st.done) continue;

    const lost = Object.entries(st.failed || {})
      .filter(([k]) => RETRYABLE.test(k))
      .reduce((a, [, v]) => a + v, 0);
    // Requeuing also re-opens every legitimately-rejected page, because `done` does
    // not say why. Below this threshold the waste is larger than the recovery.
    if (lost < minLost) continue;

    const kept = await urlsInShard(resolve(CORPUS, 'recipes', slug + '.jsonl'));
    const before = st.done.length;
    const after = st.done.filter((u) => kept.has(u));
    const back = before - after.length;
    reopened += back;
    console.log(
      slug.padEnd(40) + 'retryable=' + String(lost).padStart(5) +
      '  done ' + before + ' -> ' + after.length + '  (+' + back + ' requeued)',
    );
    if (!dry) {
      // The append-only done log is the other half of `done`; leaving it in place
      // would re-add every URL this repair just requeued on the next startup.
      await rm(resolve(CORPUS, '_state/done', slug + '.log'), { force: true });
      st.done = after;
      for (const k of Object.keys(st.failed || {})) if (RETRYABLE.test(k)) delete st.failed[k];
      st.repairedAt = new Date().toISOString();
      await writeFile(stFile, JSON.stringify(st, null, 2) + '\n', 'utf8');
    }
  }

  console.log('\n' + (dry ? 'would requeue ' : 'requeued ') + reopened + ' urls');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
