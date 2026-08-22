#!/usr/bin/env node
'use strict';
/**
 * DETERMINISM + THROUGHPUT BENCHMARK.
 *
 * Reports two things that matter when you claim a gate is safe to put on the
 * finalize path of a live product:
 *
 *   VARIANCE  -- population variance of the score across N runs of the same
 *                input. Anything but exactly 0 means the gate is not a
 *                function, and every certificate it ever issued is worthless.
 *
 *   LATENCY   -- p50/p99 per evaluation. A gate that costs a second is a gate
 *                a team switches off. This one runs in-process with no network
 *                and no model call, which is the reason it can be mandatory.
 *
 * Usage: node harness/bench.js [iterations]
 */
const fs = require('fs');
const path = require('path');
const qg = require('../index');

const ITER = Number(process.argv[2] || 400);
const CORPUS_DIR = path.join(__dirname, '..', 'corpus');

function fixtures() {
  return fs.readdirSync(CORPUS_DIR)
    .filter((f) => f.endsWith('.json') && !f.startsWith('CERTIFICATES') && !f.startsWith('PARITY'))
    .sort()
    .map((f) => JSON.parse(fs.readFileSync(path.join(CORPUS_DIR, f), 'utf8')));
}

function pctl(sorted, p) {
  if (!sorted.length) return 0;
  const i = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[i];
}

const fx = fixtures();
console.log(`\nAEGIS QUALITY GATE -- DETERMINISM & THROUGHPUT BENCHMARK`);
console.log(`engine ${qg.ENGINE_VERSION}   fixtures ${fx.length}   iterations ${ITER} each   total ${fx.length * ITER} evaluations\n`);

let worstVariance = 0;
let allDigestsStable = true;
let exactlyStable = true;
const allLatencies = [];
const rows = [];

for (const f of fx) {
  const pack = qg.pack(f.pack || 'medical');
  const scores = [];
  const digests = new Set();
  const lat = [];
  for (let i = 0; i < ITER; i++) {
    const t0 = process.hrtime.bigint();
    const v = qg.evaluate({ content: f.content, pack, profile: f.profile });
    const t1 = process.hrtime.bigint();
    lat.push(Number(t1 - t0) / 1e6);
    scores.push(v.score);
    digests.add(v.verdictDigest);
  }
  // The primary assertion is EXACT equality of the IEEE-754 bit patterns, not a
  // variance under some epsilon. Summing N identical doubles and dividing can
  // itself introduce ~1e-29 of rounding, so a "variance is tiny" claim would be
  // measuring the benchmark's own arithmetic rather than the gate's behaviour.
  const distinctScores = new Set(scores).size;
  if (distinctScores !== 1) exactlyStable = false;
  const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
  let acc = 0;
  for (const s of scores) acc += (s - mean) * (s - mean);
  const variance = distinctScores === 1 ? 0 : acc / scores.length;
  if (variance > worstVariance) worstVariance = variance;
  if (digests.size !== 1) allDigestsStable = false;
  lat.sort((a, b) => a - b);
  allLatencies.push.apply(allLatencies, lat);
  rows.push({ id: f.id, variance, distinctScores, uniqueDigests: digests.size, p50: pctl(lat, 50), p99: pctl(lat, 99) });
}

const W = (s, n) => String(s).padEnd(n).slice(0, n);
console.log(W('FIXTURE', 32) + W('VARIANCE', 10) + W('SCORES', 8) + W('HASHES', 8) + W('p50 ms', 10) + 'p99 ms');
console.log('-'.repeat(85));
for (const r of rows) {
  console.log(W(r.id, 32) + W(r.variance, 10) + W(r.distinctScores, 8) +
    W(r.uniqueDigests, 8) + W(r.p50.toFixed(3), 10) + r.p99.toFixed(3));
}
allLatencies.sort((a, b) => a - b);
console.log('-'.repeat(85));
console.log(`distinct scores/input: ${exactlyStable ? '1 (bit-identical)' : 'MORE THAN ONE -- NOT DETERMINISTIC'}`);
console.log(`distinct hashes/input: ${allDigestsStable ? '1 (stable)' : 'MORE THAN ONE -- NOT DETERMINISTIC'}`);
console.log(`worst score variance : ${worstVariance}`);
console.log(`latency p50 / p99    : ${pctl(allLatencies, 50).toFixed(3)} ms / ${pctl(allLatencies, 99).toFixed(3)} ms`);
console.log(`throughput           : ${Math.round(1000 / (allLatencies.reduce((a, b) => a + b, 0) / allLatencies.length))} evaluations/sec/core`);

const ok = exactlyStable && allDigestsStable && worstVariance === 0;
console.log(ok ? '\nRESULT: zero variance across every fixture. The gate is a function.\n'
  : '\nRESULT: FAILED -- the gate is not deterministic.\n');
process.exit(ok ? 0 : 1);
