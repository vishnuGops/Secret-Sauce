// Signed-in screenshots of the Flutter web build, for ui-overhaul audits and fidelity loops.
//
// Flutter web (CanvasKit) exposes no DOM form to fill, so this signs in through GoTrue's password
// grant and injects the session into localStorage under the key supabase_flutter 2.17 reads on web:
// `sb-<first label of the Supabase host>-auth-token` (`sb-127-auth-token` for the local stack),
// value = the session JSON. The app boots already signed in.
//
// LOCAL STACK ONLY. Credentials come from the git-ignored `env.test-account.local.json` at the repo
// root ({ "email", "password" }); never put them in this file, a dart-define file, or docs (B018/B034).
//
// Setup (once, in a scratch dir — not in the repo):  npm i playwright@1.63.0
// Run from that dir:
//   node <repo>/.claude/skills/ui-overhaul/scripts/capture_signed_in.mjs <port> <list.json> <outDir>
//   node … <port> - - --fork <recipeId>     # fork as the test user (owner views); prints the new id
//   node … <port> - - --delete <recipeId>   # delete that fork afterwards — always clean up
// list.json: [{ "name", "path" (hash route, e.g. "/my"), "w", "h", "scroll"?, "clicks"?: [[x,y]] }]
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Resolve playwright from the CWD (the scratch dir it was installed in), not from this file's
// folder: a bare ESM import resolves relative to the importing file, which lives in the repo.
const pwPath = createRequire(path.join(process.cwd(), 'noop.js')).resolve('playwright');
const pw = await import(pathToFileURL(pwPath).href);
const chromium = pw.chromium ?? pw.default.chromium; // CJS package: exports land on `default`

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
const env = JSON.parse(fs.readFileSync(path.join(REPO, 'apps/app/env.local.json'), 'utf8'));
const creds = JSON.parse(fs.readFileSync(path.join(REPO, 'env.test-account.local.json'), 'utf8'));
const [port, listFile, outDir, flag, flagArg] = process.argv.slice(2);
const base = env.SUPABASE_URL;
const key = env.SUPABASE_ANON_KEY;
if (!/^http:\/\/(127\.0\.0\.1|localhost)/.test(base)) {
  throw new Error(`refusing: env.local.json points at ${base}, not the local stack`);
}

const tokRes = await fetch(`${base}/auth/v1/token?grant_type=password`, {
  method: 'POST',
  headers: { apikey: key, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: creds.email, password: creds.password }),
});
if (!tokRes.ok) throw new Error(`sign-in failed: ${tokRes.status} ${await tokRes.text()}`);
const session = await tokRes.json();
const auth = { apikey: key, Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' };
const storageKey = `sb-${new URL(base).hostname.split('.')[0]}-auth-token`;

if (flag === '--fork') {
  const r = await fetch(`${base}/rest/v1/rpc/fork_recipe`, { method: 'POST', headers: auth, body: JSON.stringify({ p_source: flagArg }) });
  console.log('fork', r.status, await r.text());
  process.exit(r.ok ? 0 : 1);
}
if (flag === '--delete') {
  const r = await fetch(`${base}/rest/v1/recipes?id=eq.${flagArg}`, { method: 'DELETE', headers: { ...auth, Prefer: 'return=representation' } });
  const body = await r.text();
  // An RLS miss deletes 0 rows and still returns 200 (Gotcha 2) — check the representation.
  console.log('delete', r.status, body === '[]' ? 'NOTHING DELETED' : 'deleted');
  process.exit(r.ok && body !== '[]' ? 0 : 1);
}

fs.mkdirSync(outDir, { recursive: true });
const list = JSON.parse(fs.readFileSync(listFile, 'utf8'));
const browser = await chromium.launch();
for (const t of list) {
  const ctx = await browser.newContext({ viewport: { width: t.w, height: t.h } });
  await ctx.addInitScript(([k, v]) => localStorage.setItem(k, v), [storageKey, JSON.stringify(session)]);
  const page = await ctx.newPage();
  await page.goto(`http://localhost:${port}/#${t.path}`);
  await page.waitForTimeout(7000); // CanvasKit boot + first data load
  if (t.scroll) {
    await page.mouse.move(t.w / 2, t.h / 2);
    await page.mouse.wheel(0, t.scroll);
    await page.waitForTimeout(1500);
  }
  for (const [x, y] of t.clicks ?? []) {
    await page.mouse.click(x, y); // canvas: coordinates, not selectors
    await page.waitForTimeout(1500);
  }
  const f = path.join(outDir, `${t.name}-${t.w}-signedin.png`);
  await page.screenshot({ path: f });
  console.log('ok', path.basename(f));
  await ctx.close();
}
await browser.close();
