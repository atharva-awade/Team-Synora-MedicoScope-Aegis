# Aegis Quality Gate — engine specification

> A repeatable quality check that runs before important work is finalized.
> One engine, rules as data, a certificate anyone can recompute.

---

## 1. The one invariant

```
verdict = f(contentDigest, packDigest, engineVersion)
```

`f` is a pure function. No clock, no randomness, no network, no database, no
locale, no language model. Feed it the same content and the same policy pack and
it returns the same certificate id on a different machine in a different year.

Everything else in this document exists to protect that line.

**Consequence that is easy to miss:** the issuing timestamp is *outside* the
hash. It is very tempting to fold `Date.now()` into an "audit hash" because it
feels more secure. It is strictly worse — a hash that includes the moment it was
taken can never be recomputed, so it proves nothing to anyone. Identity is
reproducible; issuance is attributable. They are separate fields.

---

## 2. Layout

```
server/quality/
├── SPEC.md                      this document
├── index.js                     public surface: pack(), evaluate(), describePack()
├── lib/
│   ├── canonical.js             canonical JSON, sha256, certificate ids, rounding
│   ├── text.js                  tokenization + real Flesch–Kincaid
│   ├── claims.js                claim extraction + evidence binding
│   ├── predicates.js            the 28 pure check primitives (the only executable surface)
│   ├── engine.js                the policy interpreter
│   ├── critic.js                agent-proposed assertions: compile / run / promote
│   ├── rewrite.js               fact-preserving rewrite contract + change attribution
│   └── certificate.js           certificate envelope, verification, attestation
├── packs/
│   ├── medical.v3.json          26 checks, 4 profiles — the clinical opinion
│   └── generic.v1.json          19 checks, 2 profiles — proof the engine is domain-neutral
├── corpus/
│   ├── *.json                   26 labelled fixtures
│   ├── CERTIFICATES.lock.json   committed certificate ids (drift detector)
│   ├── PARITY_VECTORS.json      end-to-end conformance vectors
│   └── PARITY_UNITS.json        function-level conformance vectors
└── harness/
    ├── verify.js                behaviour + determinism + hash lock
    ├── bench.js                 zero-variance + latency
    ├── fuzz.js                  adversarial mutation + negative controls
    ├── parity.js                conformance vector generation / staleness check
    ├── route-smoke.js           HTTP contract
    └── promote.js               the only route from advisory to enforced
```

---

## 3. Rules are data, not code

A policy pack is a JSON document. It may *reference* predicates by id and pass
them arguments. It can never introduce behaviour: there is no `eval`, no
`Function` constructor, and regex-bearing arguments are only accepted for the two
predicates that declare them, after a catastrophic-backtracking screen.

```json
{
  "id": "GRD_NO_UNGROUNDED_CLAIMS",
  "dimension": "grounding",
  "predicate": "noUngroundedClaims",
  "severity": "critical",
  "weight": 4,
  "args": { "maxUnbound": 0 },
  "message": "Every numeric claim binds to real evidence",
  "remedy": "Each flagged number appears in the prose but matches no measurement the system holds."
}
```

`loadPack()` validates at load time, not at evaluation time. A pack naming a
predicate the engine does not implement **throws at boot**. A rule that quietly
does nothing is worse than no rule, so it is not allowed to exist.

The pack is then content-addressed: `packDigest = sha256(canonical(pack))`.
Every certificate records which rules judged it.

**This is also the answer to "without forcing the team into a specific theme or
domain".** The engine has no clinical vocabulary in it. `generic.v1.json` runs on
the same engine, the same certificate mechanics, and the same harness, and it
grades an infrastructure spend review. The medical pack is one opinion among
several, not the engine's identity.

### Profiles

One pack, several audiences. A profile picks thresholds, dimension weights, and
per-check overrides:

| Profile | Reading grade cap | Ungrounded claim | Jargon must be glossed |
|---|---|---|---|
| `patient_report` | 8 | **critical** | yes |
| `clinician_report` | 14 (minor) | **critical** | no |
| `consult_summary` | 8 | major *(flag, don't brick a chat)* | yes |
| `ai_explanation` | 7 | **critical**, coverage must be 1.0 | yes |

---

## 4. Scoring and status

```
cost(check)      = weight × { critical: 1.0, major: 0.6, minor: 0.25, info: 0 }
dimensionScore   = 1 − Σ cost(failed) / Σ cost(all)
score            = Σ (dimensionWeight × dimensionScore) / Σ dimensionWeight

BLOCK  if any failed check is `critical`, or score < thresholds.block
WARN   if any failed check is `major`,    or score < thresholds.pass
PASS   otherwise
```

A `critical` failure blocks regardless of score. That matters: a report can be
95% excellent and still be unfit to sign because one number in it was invented.
A single weighted average would have averaged that away.

All published numbers go through one rounding function, written as
`floor(x + 0.5)` rather than a library `round`, because JavaScript and Dart
disagree on exact negative halves and a cross-runtime hash cannot rest on that.

---

## 5. What is actually checked

Five dimensions, 28 predicates. Four dimensions are what any content checker
does. The fifth is the one that matters here.

### Grounding — the flagship

The dominant failure mode of AI-written clinical content is not bad grammar and
not jargon. It is **a number no sensor ever produced.**

> "Your haemoglobin is 9.2 g/dL, which is low."

That sentence is fluent, well structured, correctly hedged, at a grade-6 reading
level, and carries a disclaimer. Every readability-and-tone checker on earth
passes it. If no haemoglobin measurement exists in the episode, it is also the
most dangerous output the product can emit.

So prose is treated as a set of **claims** that must **bind** to evidence:

1. Extract numeric claims — paired readings (`128/84 mmHg`), single readings
   (`72 bpm`, `6.8%`), and label-anchored bare numbers (`haemoglobin of 9.2`).
2. Classify each as `patient` or `threshold`. *"A normal range sits below 120/80"*
   is a threshold statement, not a claim about this person, and demanding that it
   bind to a sensor would punish the writer for being helpful. Thresholds still
   appear in the certificate, marked, so the exemption is auditable rather than
   silent.
3. Bind each patient claim to an evidence fact by unit+value, label+value, or
   value alone, within a per-unit tolerance from the pack.
4. **Unbound ⇒ `GRD_NO_UNGROUNDED_CLAIMS` ⇒ BLOCK.**

`groundingCoverage = bound / total` is published on every certificate.

### Fidelity overclaim

The platform already tags every tool output with a fidelity tier
(`server/aegis/envelopes.js`): `real`, `partial`, `heuristic`,
`fabricated_scale`, `roadmap`. The gate reads those tiers and enforces them **in
prose**:

- *"Your blood pressure was estimated at 128/84 mmHg"* — fine, the estimator is hedged.
- *"Your blood pressure is 128/84 mmHg"* — **BLOCK**. That value came from a
  camera-PPG heuristic and is being narrated as a measurement.

The honesty contract already existed in the tool layer. This extends it to the
sentence the patient actually reads.

### Internal contradiction

`riskLabelConsistent` cross-checks the stated risk label against the numeric
score. A report that says *"low risk"* over a 0.82 score is not a wording defect.
It is a wrong document, and it blocks.

### Scope guard

A screening product must not emit therapy. `outOfScopeAdviceAbsent` blocks
prescriptive language and dosage expressions — while deliberately *not* firing on
`9.2 g/dL`, because a lab result is not a dose. Referral is in scope; prescribing
is not.

### Readability, measured

`readabilityGradeAtMost` computes an actual Flesch–Kincaid grade from a
deterministic syllable estimator, and publishes every intermediate count
(words, sentences, syllables, polysyllables) so the number can be reproduced by
hand. The previous implementation returned one of four hard-coded strings from a
words-per-sentence lookup table, which could not move and therefore could not
fail.

---

## 6. Where the LLM is allowed to stand

Judges want agentic AI in the loop. An LLM is non-deterministic. Anything an LLM
decides cannot be part of a repeatable verdict. Putting a model inside the gate
destroys the only property the gate exists to provide.

The resolution: **the agent never scores. It writes tests.**

```
critic agent  →  proposes ASSERTIONS (predicate id + args, never code)
compile()     →  validates against the registry + an argument allowlist,
                 rejects unknown predicates, non-data args, ReDoS-shaped regex,
                 and any attempt to claim `critical` severity
runAdvisory() →  executes them and reports ADVISORY findings
```

Advisory findings are recorded on the certificate and **excluded from the verdict
digest by construction**. They cannot move PASS/WARN/BLOCK. The certificate stays
byte-reproducible even though a stochastic model touched the workflow — there is
an API test asserting exactly that.

The only route to authority is `promote()`: the assertion is written into the
pack as a real check, the pack version is bumped, and **the whole golden corpus
is re-evaluated**. If promotion changes any existing fixture's verdict, it is
refused until a human passes `--accept-drift` and re-locks the certificates.

So the gate can learn, and it is still a pure function. Non-determinism is
quarantined, not invited in.

---

## 7. The fact-preserving rewrite contract

The gate does not just say no. It hands the failure to an agent and asks for a
better draft. This is where most "AI fixes its own output" demos quietly become
dangerous: the model does not only improve the prose, it rounds a number, drops a
negation, softens a risk level. The document gets more readable and less true,
and every readability metric applauds.

So a rewrite is a proposal under contract. Before the new draft is even *scored*,
`checkRewrite()` proves that four things are byte-identical:

- the multiset of patient-facing numeric claims (value + unit + role)
- the declared risk level and numeric risk score
- the set of cited evidence envelopes
- the negation polarity attached to each clinical term

**Prose is free. Facts are frozen.** A rewrite that changes a number is rejected
before scoring — which means the gate can block its own fix, and that is what
makes the loop safe to run unattended.

`attributeChange()` closes the other loophole: it re-runs the *old* pack on the
*new* content, so "the score went up" can be attributed to the content rather
than to a quietly loosened rule.

---

## 8. Proof, not assertion

`npm test` in `server/` runs all of this. Any failure is a red build.

| Harness | What it proves | Current |
|---|---|---|
| `test:aegis` | the pre-existing Aegis gate unit tests, now actually wired to CI | **57 pass** |
| `gate:verify` | 26 labelled fixtures reach their specified verdicts; the exact checks each was written to trip do trip | **26/26** |
| `gate:verify` | each fixture re-evaluated 12× returns the identical certificate | **26/26 deterministic** |
| `gate:verify` | certificate ids match `CERTIFICATES.lock.json` | **26/26 locked** |
| `gate:bench` | bit-identical scores and hashes over 400 runs/fixture | **variance 0** |
| `gate:bench` | latency, because a slow gate gets switched off | **p50 0.5 ms / p99 1.1 ms** |
| `gate:fuzz` | 15 injected defect classes are caught | **66/66 (100%)** |
| `gate:fuzz` | semantically empty edits do **not** move a certificate | **20/20 unchanged** |
| `gate:api` | the HTTP contract, incl. advisory findings never moving a verdict | **15/15** |
| `gate:parity` | published conformance vectors are current | **656 check assertions** |

Two things worth calling out.

**The hash lock is the anti-drift mechanism.** You cannot quietly loosen a rule
and keep a green CI, because every certificate id would move and `gate:verify`
fails until a human re-locks with `--update`. Every change to the definition of
quality becomes a reviewable, versioned event.

**The negative controls matter as much as the catch rate.** A gate that reacts to
whitespace, CRLF line endings, JSON key order, or the order the tools happened to
run in would issue a fresh certificate for an unchanged document — making
"repeatable" false in the other direction. `fuzz.js` asserts both directions.

The fuzzer also refuses to inflate its own number: a mutation that does not apply
to a fixture (wrong pack, wrong risk level, or a transform that produced no
change) is reported as **n/a**, never counted as caught.

---

## 9. Certificates

```
certificateId  = crockfordBase32(verdictDigest)[0:10]     e.g. 42F2M-XMESW
verdictDigest  = sha256(canonical({ engineVersion, packId, packVersion,
                                    packDigest, profile, contentDigest,
                                    status, score,
                                    checks: [{ id, ok, severity, data }] }))
contentDigest  = sha256(canonical(normalizeContent(content)))
```

Excluded from the digest, on purpose: `issuedAt`, `issuer`, `attestation`,
`advisory`, and every human-facing `detail`/`message` string. Prose is excluded
so that a copy-edit to a message — or a runtime's number-to-string formatting —
can never fork a hash.

`certificateId` is Crockford base32 (no I, L, O, U) so it survives being read
aloud on a demo stage or typed off a printed page.

Two independent things you can check:

- **`certificate.verify({ certificate, content, pack })`** — re-derives the
  verdict and compares digests. Needs no database and no trust in our server.
- **`certificate.verifyAttestation(cert, secret)`** — an HMAC over
  `(verdictDigest, issuedAt, issuer)`, so issuance is attributable and revocable
  *without ever changing the id*.

---

## 10. Enforcement

`server/src/routes/quality-gate.js` — the design rule is one sentence:
**the server never trusts a score it did not compute.**

| Route | Purpose |
|---|---|
| `GET /packs` | the published rule set — a gate whose rules are secret cannot be argued with |
| `POST /evaluate` | pure verdict, nothing persisted, safe to call while typing |
| `POST /certify` | verdict + persisted certificate + hash-chained ledger row |
| `POST /finalize` | **the only sanctioned way to sign content** |
| `POST /verify` | re-derive a certificate from content |
| `GET /verify/:id` | public seal check — no auth, no clinical content |
| `POST /rewrite/check` | the fact-preserving contract |
| `POST /critique/compile` | validate agent-proposed assertions |

`POST /finalize` re-evaluates the content it is sent and returns **409 on BLOCK**
with the remediation list. A doctor or admin may override by supplying a written
reason, which is appended to the existing hash-chained `DecisionAudit` ledger as
`quality_gate_override` with their identity attached. There is no route that
signs content without a verdict, and no offline path either: with no gate, there
is no signature.

Quality verdicts join the *same* tamper-evident chain as the clinical decisions
they govern (`decisionType: 'quality_gate' | 'quality_gate_final' |
'quality_gate_override'`), and `GET /verify/:id` reports `ledgerIntegrity` from
`ledger.verifyChain`.

---

## 11. Why the client has no rules in it

The app previously shipped a second implementation of the rules in Dart, under a
different version string (`QG-CLINICAL-2026.2` vs the server's
`QG-SERVER-2026.2`), with different logic. Two implementations of a quality rule
are two definitions of quality — and the second one lived on the device belonging
to the person being audited.

One of them was deleted. The app keeps a **pre-flight**
(`lib/services/quality/qg_preflight.dart`) that:

- issues no certificate and computes no hash,
- implements only checks that need nothing but the text,
- deliberately does **not** attempt evidence binding, fidelity overclaim, or
  risk-label consistency — the checks that actually gate a report,
- omits the dimensions it cannot evaluate rather than scoring them, and
- always renders as `PROVISIONAL`, never as passed.

A local hint that could be read as a pass is worse than no local hint.

`PARITY_VECTORS.json` and `PARITY_UNITS.json` remain published as a **conformance
suite**: any future re-implementation, in any language, can be held to the same
656 assertions before it is allowed to call itself the same gate.

---

## 12. Adding a rule

```bash
cd server

# 1. add the check to packs/medical.v3.json (data only)
# 2. add a fixture to corpus/ that the new rule is supposed to catch
npm run gate:verify          # fails: the fixture's certificate is not locked
npm run gate:verify -- --update
npm run gate:fuzz            # does the new rule survive adversarial injection?
npm run gate:parity          # refresh the conformance vectors
npm test                     # the whole chain
```

If the new rule changes an existing fixture's verdict, that shows up as
certificate drift and the build stays red until a human looks at it and says so
explicitly. That friction is the feature.
