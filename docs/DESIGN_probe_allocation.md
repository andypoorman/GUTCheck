# Design: Inject-time probe allocation

**Status:** Implemented.
**Scope:** `addons/gut_check/` — parser, instrumenter, collector, report, export.
**Goal:** A coverage probe should exist *if and only if* the instrumenter emitted
a collector call for it. No probe should ever be "allocated but never injected,"
because that is the root of every false-uncovered / false-covered bug GUTCheck
has chased.

---

## 1. The problem this solves

A probe is just an index into the per-script hit array. Historically three
passes each decided, independently, what was "instrumentable" and could disagree:

1. **Allocation** handed out a probe ID for every executable line / branch the
   classifier saw.
2. **Injection** rewrote each line to call `GUTCheckCollector.hit(...)` /
   `hit_br2(...)` / etc. — but several paths *silently declined* (no block colon,
   a dense `1 if(c)else 2`, a multiline header whose wrapped form changed the
   physical line count).
3. **Emission** read `hits[probe_id]`. A probe allocated in (1) but skipped in
   (2) read a permanent `0`, so a line/branch that actually ran was reported as
   uncovered — or, via body derivation, the reverse.

The disagreement was silent: nothing recorded that an allocated probe was never
wired up.

A prior fix ("Option A") detected the gap *after the fact* — regex-scan the
emitted source for the probe IDs actually present, then drop the rest. It worked
but it was a reconciliation between two authorities that shouldn't disagree in
the first place.

## 2. The design — one authority, assigned at injection

Make allocation and injection the *same act*. `GUTCheckProbeAllocator`
(`instrumenter/probe_allocator.gd`) is the **sole** authority on probe identity,
and the only way an ID is born is a call into it at the moment a collector call
is emitted:

- `GUTCheckScriptMap` is passive data. It no longer numbers probes; it only
  derives its branch **structure** from its lines (`build_branches()` — which
  lines are branches and how if/elif/else and match arms group into decision
  blocks). Structure is a property of the source; identity is not.
- `GUTCheckLineClassifier.classify()` produces that structure with **no** probe
  IDs.
- `GUTCheckInstrumenter.instrument()` walks the lines and dispatches to the
  `GUTCheckProbeInjector` wrappers, threading one allocator through the whole
  script. Each wrapper pulls `allocator.line()` / `allocator.branch(info)` *only
  on the path where it actually emits the call*. A wrapper that declines pulls
  nothing, so that probe never exists — there is no orphan to reconcile and no
  post-hoc scan. After the walk, the instrumenter overwrites
  `script_map.{probe_to_line, branches, probe_count}` with the allocator's
  result.

Two wrinkles the design handles directly rather than after the fact:

- **Multiline round-trip bail.** A parenthesized/continued header is joined,
  wrapped, and split back; if the wrapper changed the physical line count the
  statement is abandoned. `savepoint()` / `rollback_to()` undo exactly the IDs
  that statement allocated, so the discarded text leaves nothing behind.
- **Derived branches.** A block `else:` / match pattern with its body on the
  following lines can't hold its own counter. Instead of allocating a slot that
  is never written and deriving its hit at report time, the allocator binds the
  branch's `probe_id` to the **first body line's probe** (`resolve_derived()`,
  indent-bounded to the block). So a branch is covered iff the probe that proves
  it ran is — `get_branch_hit_count()` is simply `hits[probe_id]` for every
  branch, with no special derivation step. An else/pattern whose body can't be
  instrumented binds to nothing and is dropped (honestly absent rather than a
  false zero).

The result: **every probe ID in a registered map appears as a collector call in
the instrumented source.** That is the invariant, and it holds by construction.

## 3. Tests build maps the same way

Exporter/computer unit tests that hand-build a `GUTCheckScriptMap` (no source to
inject) get their probes from the *same* authority via
`GUTCheckProbeAllocator.assign_all(map)`, which numbers a fully-structured map in
the canonical line-sorted layout and applies the same derived-branch binding.
There is no second "allocate probes" method living on the map for tests to call.

The string wrappers are still unit-tested in isolation with pinned IDs via
`GUTCheckProbeAllocator.passthrough(seed)` — a non-allocating mode that echoes
fixed IDs so a wrapper's emitted string is fully determined by the caller.
Production never uses passthrough.

## 4. Invariant & how it's guarded

`test/test_accuracy_fixes.gd::_assert_probe_invariant` re-derives the truth from
the emitted source: it scans the instrumented text for the probe IDs actually
present and asserts every surviving probe ID in the map appears there. It runs
over a corpus of resource scripts. Any future wrapper change that orphans a
probe fails it immediately.

## 5. Alternatives considered (and rejected)

- **A ledger** — record, per probe, whether injection succeeded plus a reason,
  attach it to the map, and have emission honor it. Additive and observable, but
  it *institutionalizes* the allocation-vs-injection gap instead of closing it:
  you keep two authorities and add a third structure to reconcile them. Rejected
  as overengineered once inject-time allocation made the gap impossible.
- **Pre-injection feasibility check** — let the classifier allocate a probe only
  if a *simulated* injection would succeed. This requires the classifier to
  replicate the injector's string logic (colon-finding, `in`-finding, ternary
  boundary matching) — two copies of the most bug-prone code, kept in lockstep —
  and still can't predict the multiline round-trip mismatch, which is only known
  after the split. Rejected.

## Appendix: file/symbol index

| Concern | File:symbol |
|---|---|
| Probe-ID authority | `instrumenter/probe_allocator.gd` `GUTCheckProbeAllocator` |
| Line probe / branch probe | `probe_allocator.gd` `line()`, `branch()` |
| Derived-branch binding | `probe_allocator.gd` `derive_branch()`, `resolve_derived()` |
| Multiline rollback | `probe_allocator.gd` `savepoint()`, `rollback_to()` |
| Batch numbering (tests) | `probe_allocator.gd` `assign_all()`, `passthrough()` |
| Branch structure (no IDs) | `parser/script_map.gd` `build_branches()` |
| Classify → structure only | `parser/line_classifier.gd` `classify()` |
| Inject loop / overwrite map | `instrumenter/instrumenter.gd` `instrument()` |
| Wrapper dispatch | `instrumenter/probe_injector.gd` `instrument_line()` |
| Branch hit = `hits[probe_id]` | `report/coverage_computer.gd` `get_branch_hit_count()` |
| Source-presence invariant | `test/test_accuracy_fixes.gd` `_assert_probe_invariant` |
