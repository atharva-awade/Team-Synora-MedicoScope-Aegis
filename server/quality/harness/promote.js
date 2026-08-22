#!/usr/bin/env node
'use strict';
/**
 * PACK PROMOTION -- the only route from "an agent noticed something" to "the
 * gate enforces it".
 *
 * An advisory assertion proposed by the critic agent carries no authority (see
 * lib/critic.js). Promotion is what grants it authority, and promotion is
 * deliberately expensive:
 *
 *   1. the assertion is written into the pack as a real check
 *   2. the pack version is bumped, so the packDigest changes, so every future
 *      certificate records which rule set judged it
 *   3. THE ENTIRE GOLDEN CORPUS IS RE-EVALUATED. If the new rule changes any
 *      existing fixture's verdict, promotion is REFUSED unless a human passes
 *      --accept-drift and the corpus is re-locked.
 *
 * That last step is the whole point. A gate that can silently acquire rules is
 * not repeatable, and a gate that can silently LOSE them is worse. This makes
 * every change to the definition of quality a reviewable, versioned event.
 *
 * Usage:
 *   node harness/promote.js --pack medical --assertion ./advisory.json [--id PRO_MY_RULE]
 *        [--severity major] [--weight 2] [--dry-run] [--accept-drift]
 */
const fs = require('fs');
const path = require('path');
const qg = require('../index');
const engine = require('../lib/engine');

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[i + 1] : dflt;
}
const flag = (name) => process.argv.indexOf('--' + name) >= 0;

const packId = arg('pack', 'medical');
const assertionPath = arg('assertion', null);
const DRY = flag('dry-run');
const ACCEPT_DRIFT = flag('accept-drift');

if (!assertionPath) {
  console.error('usage: node harness/promote.js --pack <id> --assertion <file.json> [--dry-run] [--accept-drift]');
  process.exit(2);
}

const CORPUS_DIR = path.join(__dirname, '..', 'corpus');
const raw = JSON.parse(fs.readFileSync(assertionPath, 'utf8'));
const proposals = Array.isArray(raw) ? raw : [raw];

const current = qg.pack(packId);
const { accepted, rejected } = qg.critic.compile(proposals, current);

console.log('\nAEGIS QUALITY GATE -- PACK PROMOTION');
console.log(`pack ${current.packId}@${current.packVersion} (#${current.packDigest.slice(0, 12)})`);
console.log(`proposals: ${proposals.length}   accepted: ${accepted.length}   rejected: ${rejected.length}`);
for (const r of rejected) console.log(`  rejected ${r.predicate}: ${r.reason}`);
if (!accepted.length) { console.log('\nnothing to promote.\n'); process.exit(1); }

let next = current;
for (const a of accepted) {
  next = qg.critic.promote(next, a, {
    id: accepted.length === 1 ? arg('id', undefined) : undefined,
    severity: arg('severity', undefined),
    weight: arg('weight', undefined) !== undefined ? Number(arg('weight')) : undefined,
  });
  next = engine.loadPack(next);   // re-validate + re-address after every step
  console.log(`  promoted ${a.id} (${a.predicate}) -> ${next.packVersion}`);
}

// ---- re-evaluate the whole corpus under the new pack -----------------------
const fixtures = fs.readdirSync(CORPUS_DIR)
  .filter((f) => f.endsWith('.json') && !f.startsWith('CERTIFICATES') && !f.startsWith('PARITY'))
  .sort()
  .map((f) => JSON.parse(fs.readFileSync(path.join(CORPUS_DIR, f), 'utf8')))
  .filter((f) => (f.pack || 'medical') === packId);

const drift = [];
for (const fx of fixtures) {
  const before = engine.evaluate({ content: fx.content, pack: current, profile: fx.profile });
  const after = engine.evaluate({ content: fx.content, pack: next, profile: fx.profile });
  if (before.status !== after.status || before.score !== after.score) {
    drift.push({ id: fx.id, from: `${before.status} ${before.score}`, to: `${after.status} ${after.score}` });
  }
}

console.log(`\ncorpus re-evaluated: ${fixtures.length} fixture(s) under ${packId}@${next.packVersion}`);
if (drift.length) {
  console.log(`verdict drift on ${drift.length} fixture(s):`);
  for (const d of drift) console.log(`  ${d.id}: ${d.from}  ->  ${d.to}`);
} else {
  console.log('no verdict drift: the new rule adds coverage without moving any existing verdict.');
}

if (drift.length && !ACCEPT_DRIFT) {
  console.log('\nREFUSED. The promotion changes existing verdicts. Review each fixture above, then re-run with');
  console.log('--accept-drift, and re-lock certificates with `npm run gate:verify -- --update`.\n');
  process.exit(1);
}
if (DRY) { console.log('\n--dry-run: pack not written.\n'); process.exit(0); }

const file = path.join(qg.PACK_DIR, qg.PACK_FILES[packId]);
const toWrite = JSON.parse(JSON.stringify(next));
delete toWrite.packDigest;   // always derived, never stored
fs.writeFileSync(file, JSON.stringify(toWrite, null, 2) + '\n');
console.log(`\nwritten: ${path.relative(process.cwd(), file)}  (now ${next.packId}@${next.packVersion})`);
console.log('NEXT: npm run gate:verify -- --update && npm run gate:parity\n');
