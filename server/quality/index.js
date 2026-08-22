'use strict';
/**
 * Aegis Quality Gate -- public module surface.
 *
 *   const qg = require('../../quality');
 *   const pack = qg.pack('medical');
 *   const verdict = qg.evaluate({ content, pack, profile: 'patient_report' });
 *
 * Packs are loaded once and cached by id; loading validates every check against
 * the predicate registry, so a malformed pack fails at boot rather than silently
 * skipping rules in production.
 */
const fs = require('fs');
const path = require('path');

const canonical = require('./lib/canonical');
const text = require('./lib/text');
const claims = require('./lib/claims');
const predicates = require('./lib/predicates');
const engine = require('./lib/engine');
const critic = require('./lib/critic');
const rewrite = require('./lib/rewrite');
const certificate = require('./lib/certificate');

const PACK_DIR = path.join(__dirname, 'packs');
const PACK_FILES = { medical: 'medical.v3.json', generic: 'generic.v1.json' };

const _cache = new Map();

function pack(id) {
  const key = id || 'medical';
  if (_cache.has(key)) return _cache.get(key);
  const file = PACK_FILES[key];
  if (!file) throw new Error(`unknown pack "${key}". Available: ${Object.keys(PACK_FILES).join(', ')}`);
  const raw = JSON.parse(fs.readFileSync(path.join(PACK_DIR, file), 'utf8'));
  const loaded = engine.loadPack(raw);
  _cache.set(key, loaded);
  return loaded;
}

function packIds() { return Object.keys(PACK_FILES).sort(); }

/** Reload from disk (used by the harness and by pack-promotion tooling). */
function reloadPacks() { _cache.clear(); }

/** Profile catalogue for a pack, for UI pickers and the /packs endpoint. */
function describePack(id) {
  const p = pack(id);
  return {
    packId: p.packId,
    packVersion: p.packVersion,
    packDigest: p.packDigest,
    title: p.title,
    description: p.description,
    engineVersion: engine.ENGINE_VERSION,
    defaultProfile: p.defaultProfile,
    dimensions: p.dimensions,
    profiles: Object.keys(p.profiles).sort().map((k) => ({
      id: k,
      title: p.profiles[k].title || k,
      audience: p.profiles[k].audience || null,
      thresholds: p.profiles[k].thresholds || {},
      checkCount: engine.applicableChecks(p, k).length,
    })),
    checks: p.checks.map((c) => ({
      id: c.id, dimension: c.dimension, predicate: c.predicate,
      severity: c.severity, weight: c.weight, message: c.message,
    })).sort((a, b) => (a.id < b.id ? -1 : 1)),
    predicateRegistry: predicates.ids(),
  };
}

module.exports = {
  ENGINE_VERSION: engine.ENGINE_VERSION,
  pack, packIds, reloadPacks, describePack, PACK_DIR, PACK_FILES,
  evaluate: engine.evaluate,
  loadPack: engine.loadPack,
  normalizeContent: engine.normalizeContent,
  buildContext: engine.buildContext,
  summarize: engine.summarize,
  applicableChecks: engine.applicableChecks,
  critic, rewrite, certificate, predicates, canonical, text, claims,
};
