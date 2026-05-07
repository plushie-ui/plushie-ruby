# Performance bar

plushie-ruby is meant to feel lightweight in use and lightweight
in the process listing. That is a baseline expectation, not an
optimization target chased after the fact.

The runtime sits between every event and every render. Work it
does on a hot path is paid by every interaction in every app.
Idle apps that draw CPU draw battery; runtimes that walk the
tree multiple times per update are felt on larger trees even
when each walk profiles cleanly. The whole point of going native
through a typed wire is that the host should feel lighter than
what it replaces; a runtime that pegs CPU loses that on its own
merits.

## Working principle

Lightweight is achieved by not doing unnecessary work in the
first place. Optimizing a hot path after the fact is sometimes
necessary; far more of the win comes from never letting the work
appear.

Each piece of work has a cost. Individually most of them are
cheap; the cost compounds across a frame, an interaction, an
app's lifetime, the user's battery. A tree walk that runs in
0.3ms looks fine in isolation; six of them per update on a
medium tree is visible latency. Watch the compounding, not just
the individual microbenchmark.

## Readability is the bound

Optimizations that obscure intent trade a forever cost (every
future reader) against a one-time benefit. Decline that trade
by default.

Worth doing without a benchmark because the win is obvious in
shape and readability is preserved or improved:

- Consolidating redundant traversals, dispatches, or
  serialization passes.
- Picking the right data structure for a known access pattern
  (Hash by ID over linear scan; frozen literals where the value
  never changes).
- Avoiding a clearly unnecessary allocation, copy, or `each`/`map`
  pass that another method on the same data already did.
- Localized refactors where the optimized form is also the
  cleaner form.
- Removing per-frame work that does not depend on per-frame
  inputs (move it to startup, to subscription diff, or to the
  edge where the input changes).

Need a benchmark, profile, or repro before they land, because
the readability cost is real:

- Clever encoding, lookup, or layout schemes that change how the
  code reads.
- Big-O claims of the form "this is O(n) on a hot path" without
  realistic N. Many such claims have N in the dozens, where the
  constant factor of `Hash#fetch` or `Array#find` is worse than
  the linear scan over a small array.
- Optimizations on idle or rarely-hit paths (startup, settings
  parsing, error paths, dev-mode overlays).
- Anything that asks the reader to look up a comment to
  understand what the code is doing.

Measurement is a tiebreaker for the second list, not a gate on
the first.

## Ruby-specific axes

Ruby's runtime adds a few axes worth keeping in view:

- **GVL.** CRuby's Global VM Lock means CPU-bound Ruby work in
  a thread blocks every other Ruby thread. The runtime thread
  is the hot path; CPU-bound work in it is felt by every event.
  Push CPU-bound user work to `Command.task` (a dedicated
  thread; the GVL still serializes Ruby execution, but I/O and
  blocking C extensions release it). Push CPU-bound framework
  work to startup or to deferred scheduling, not to the per-event
  path.
- **Allocation discipline.** Ruby's GC is generational and tuned
  for short-lived objects, but the per-frame path still pays
  for every allocation. Frozen string literals (the project
  uses `# frozen_string_literal: true` everywhere), reusing
  hashes where the shape is fixed, avoiding `Array#+` (which
  copies) where `concat` (which mutates) is local and visible
  are the recurring shapes.
- **`Data.define` over `Struct`.** The codebase uses
  `Data.define` for immutable records (events, commands,
  models). They allocate less than `Struct` on update (the
  `with` pattern returns a new frozen instance) and the freezing
  prevents accidental mutation that GC cannot help with.
- **Frozen by default.** The `# frozen_string_literal` magic
  comment is on every file. String literals are frozen at parse
  time; runtime allocation is only for genuinely dynamic
  strings. A `+` that builds a runtime string is a real
  allocation; the codebase avoids that on hot paths.
- **GC pauses.** Ruby's GC pauses are short on modern
  generational collectors but not zero. A runtime that allocates
  in the hot path under load will pause more often. The same
  compounding argument applies: do not allocate where you do
  not have to.
- **Symbol vs String.** Symbols are interned; converting
  arbitrary strings to symbols on the hot path leaks symbols.
  The codec uses a fixed enumeration parsed against
  `Plushie::Protocol::Parsers`, not `String#to_sym` against
  renderer-supplied strings.

## What lightweight looks like

Numeric direction for the realistic application profile (a few
hundred to about a thousand active tree nodes, dozens of images,
one to five fonts):

- **Frame budget.** 16.67ms (60fps) for a single update cycle
  end-to-end (event arrival, app `update`, `view`, tree diff,
  wire emit). Most of that budget belongs to the renderer; the
  SDK side should be a small slice.
- **Event-to-update.** Visible by the next frame.
  Sub-millisecond wire round-trip on a local pipe.
- **Idle CPU.** When nothing is happening, the runtime does no
  measurable work. No periodic polling, no animation tick when
  no animation is active, no spinning subscription threads, no
  per-frame walks when the tree has not changed. The timer
  scheduler uses a single thread with a deadline-based
  `IO.select`; one thread per timer is a non-pattern.
- **Subscription cost.** Subscribing to a high-frequency source
  is the user's choice; the runtime applies coalescing
  (`max_rate` per subscription) so the cost is bounded by what
  the user opts into.
- **Resident memory.** Tens of MiB for an idle small app.
  Memory grows with widget state and tree size, not with
  runtime bookkeeping. Internal caches (memo, widget view
  cache) bound their size.

These are direction, not contracts. There is no benchmark
infrastructure in the repo today; numbers should be tightened
or relaxed when measurement disagrees.

## Tree diff is the load-bearing piece

`Plushie::Tree::Diff` is the hot path that runs every cycle the
view tree changes. Worth preserving:

- Single-pass diff with LIS-based child reorder. The cost of an
  unnecessary full re-emit on a large tree is far worse than the
  cost of computing minimal moves.
- Memo-based skipping (`memo` nodes via the thread-local
  `MemoCache`) for expensive subtrees with stable cache keys.
- Per-widget view cache so behavioral widgets do not re-render
  when neither props nor state changed.

Changes to the diff path that look like cleanups but actually
inflate work per node (extra hash lookups, redundant key
stringification, repeated `Hash#fetch` chains where a destructure
would do) get caught here because the compounding is most
visible.
