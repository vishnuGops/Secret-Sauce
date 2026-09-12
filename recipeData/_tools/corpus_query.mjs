// Ask the corpus a question, from the table of contents rather than the shards.
//
//   node corpus_query.mjs --chain "Olive Garden"
//   node corpus_query.mjs --chef Nagi --limit 5
//   node corpus_query.mjs --cuisine Italian --category Dessert --count
//   node corpus_query.mjs --group "King Arthur" --json > kab.jsonl
//   node corpus_query.mjs --text "chocolate chip" --max-minutes 30
//
// `index.jsonl` is one line per recipe and about 400 bytes of it, so a full scan of
// 70,000 recipes costs a second and needs no database. Run `corpus_index.mjs` first;
// the index is generated, so it is exactly as fresh as the last time you built it.
import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const INDEX = resolve(HERE, '../../corpus/index.jsonl');

const argv = process.argv.slice(2);
const arg = (f) => {
  const i = argv.indexOf(f);
  return i >= 0 ? argv[i + 1] : null;
};
const has = (f) => argv.includes(f);

const ci = (needle) => {
  const n = String(needle).toLowerCase();
  return (hay) => String(hay == null ? '' : hay).toLowerCase().includes(n);
};

async function main() {
  if (has('--help') || argv.length === 0) {
    console.log(
      'usage: node corpus_query.mjs [--chef X] [--group X] [--chain X] [--cuisine X]\n' +
      '                            [--category X] [--source X] [--kind X] [--text X]\n' +
      '                            [--copycat] [--max-minutes N] [--min-ingredients N]\n' +
      '                            [--limit N] [--count] [--json] [--fields a,b,c]',
    );
    return;
  }

  const tests = [];
  const add = (flag, get) => {
    const v = arg(flag);
    if (v != null) {
      const m = ci(v);
      tests.push((r) => m(get(r)));
    }
  };
  add('--chef', (r) => r.chef);
  add('--group', (r) => r.group);
  add('--cuisine', (r) => r.cuisine);
  add('--category', (r) => r.category);
  add('--source', (r) => r.source);
  add('--kind', (r) => r.kind);
  add('--chain', (r) => (r.chains || []).join(' | '));
  add('--text', (r) => r.title);
  if (has('--copycat')) tests.push((r) => !!r.copycat);
  const maxMin = arg('--max-minutes');
  if (maxMin) tests.push((r) => r.minutes != null && r.minutes <= Number(maxMin));
  const minIng = arg('--min-ingredients');
  if (minIng) tests.push((r) => (r.ingredients || 0) >= Number(minIng));

  const limit = Number(arg('--limit')) || 20;
  const asJson = has('--json');
  const countOnly = has('--count');
  const fields = (arg('--fields') || '').split(',').filter(Boolean);

  let scanned = 0;
  let matched = 0;
  const shown = [];

  const rl = createInterface({ input: createReadStream(INDEX, 'utf8'), crlfDelay: Infinity });
  for await (const line of rl) {
    if (!line.trim()) continue;
    let r;
    try {
      r = JSON.parse(line);
    } catch {
      continue;
    }
    scanned++;
    if (!tests.every((t) => t(r))) continue;
    matched++;
    if (!countOnly && shown.length < limit) shown.push(r);
  }

  if (countOnly) {
    console.log(matched + ' of ' + scanned);
    return;
  }
  for (const r of shown) {
    if (asJson) {
      console.log(JSON.stringify(fields.length ? Object.fromEntries(fields.map((f) => [f, r[f]])) : r));
      continue;
    }
    console.log(
      (r.title || '').slice(0, 58).padEnd(60) +
      (r.chef || '—').slice(0, 22).padEnd(24) +
      (r.group || '').slice(0, 22).padEnd(24) +
      (r.chains && r.chains.length ? '[' + r.chains.join(', ') + '] ' : '') +
      (r.url || ''),
    );
  }
  console.log('\n' + matched + ' matched of ' + scanned + ' indexed' + (matched > shown.length ? ' (showing ' + shown.length + ')' : ''));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
