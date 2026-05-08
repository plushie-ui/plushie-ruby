# plushie-ruby

This file is not version controlled. Do not reference it in commit
messages, pull requests, or documentation.

Native desktop GUI framework for Ruby, powered by iced. Implements
the Elm architecture (init/update/view) with commands and subscriptions.
Communicates with the Rust binary over stdin/stdout using MessagePack
(default) or JSONL.

## Stewardship

Direction, trust posture, goals, and explicit non-goals are captured
in `docs/stewardship/`. That directory is the authority on what work
the project takes on and what it declines. The summary below is enough
for routine work; pull the relevant doc when an axis is in play. Use
`docs/stewardship/triage.md` as the routing tool when the answer is
not self-evident.

Pre-1.0: no backcompat, right design wins, rename across SDKs is fine.
Post-1.0: stability obligations begin (Hyrum's Law). plushie-rust =
protocol authority. plushie-elixir = canonical API-shape reference;
plushie-ruby follows. Cross-SDK parity audited in sibling
`plushie-sdk-parity/`. Gem is a library, not an auto-bootstrap
framework.

### Disciplines (non-negotiable)

Tests through real renderer; cross-SDK claims verified by reading
source on each side; design before code at boundaries (public API,
DSL surface, wire codec, transport contract); clarity is the bar; no
half-built features; local cleanup not scope creep; no legacy shims
pre-1.0.

### Goals

Wire codec fidelity on host side; cross-SDK concept parity (semantics
converge, syntax diverges per language); Elm-architecture purity
(init/update/view, return-shape validation, commands as pure data,
pure view, declarative subs); lightweight runtime (no idle work, no
polling, minimal tree diff via LIS); fault tolerance (renderer crash
auto-recovers + state re-syncs with bounded backoff, app exception
reverts to last good model, neither side takes the other down); DSL
clarity.

### Non-goals (declined, not deprioritized)

Backcompat before 1.0; per-Ruby API ergonomics that diverge from
cross-SDK shape; API stability hardening pre-1.0 (single 1.0 sweep,
not piecemeal); coverage targets as a metric; mocking renderer for
speed; micro-optimization at cost of readability; refactoring without
a forcing function; DSL extensions for hypothetical future widgets;
heavy metaprogramming where ordinary code would do; fiber/ractor
runtime architectures; defending against speculative deployment shapes.

### Trust model

Asymmetric. Renderer-to-host = closed and typed; host structurally
protected today (typed event decoding, no opaque-blob path, effect/
query response correlation by wire ID, no host-side eval, no `to_sym`
on renderer-supplied strings on hot paths, strict enums via Parsers).
Host-to-renderer = broad by design (file paths, fonts, images,
screenshots, effects, `--exec`); bounding it is the capability-manifest
roadmap in plushie-rust. Wire = byte-stream agnostic; confidentiality
+ integrity delegated to outer transport. Same-access (user attacking
themselves) out of scope.

### Resilience

Things-go-wrong axis, not adversary axis. App exception revert in
init/update/view (rescue StandardError, not Exception); renderer crash
auto-recovery via Bridge with exponential backoff + fresh snapshot
re-sync; bridge heartbeat watchdog catches hung renderers; defensive
parsing on the wire (reject + structured error); return-shape
validation in `unwrap_result` raises immediately; bounded queue +
coalescable events for high-frequency sources; subscription failure
isolated; thread isolation for async commands. Fail-fast on programming-
error invariant violations and unrecoverable bridge startup. Degrade
gracefully on user-facing input. Log suppression after 100 consecutive
errors. Don't `rescue Exception` (swallows interrupts).

### Performance

Lightweight = baseline, not optimization-after-fact. Don't do
unnecessary work in the first place; cost compounds. Worth doing
without benchmark (readability preserved/improved): consolidate
redundant traversals, right data structure, avoid unnecessary `each`/
`map` passes, move per-frame work that doesn't depend on per-frame
inputs to the edge. Need benchmark first (readability cost real):
clever encoding, big-O without realistic N, optimization on idle paths.
Ruby axes: GVL serializes Ruby across threads (push CPU-bound user
work to `Command.task`); allocation discipline (`frozen_string_literal`
everywhere, `Data.define` over Struct, avoid runtime string building
on hot paths); GC pauses; no `to_sym` on untrusted strings. Numeric
direction: 16.67ms frame budget at a few hundred to ~1000 nodes; idle
CPU = no measurable work; tree diff is the load-bearing piece (LIS-
based child reorder, memo cache, widget view cache).

### Test discipline

Integration spine: tests exercise real renderer (default `mock`
backend = real binary, real wire, real Core, no GPU). Three modes
(cross-SDK contract): mock (default, fastest), headless (tiny-skia,
pixels), windowed (headless weston preferred, Xvfb works for X11).
Pooled mock backend
multiplexes via `--max-sessions N`. Both Minitest (`Plushie::Test::Case`)
and RSpec (`Plushie::Test::RSpec`) are first-class. Stubs acceptable
only for forced crash sim, malformed wire bytes, direct `update` shape
tests, test infra. Sync via the Session API, never via
`instance_variable_get` into the runtime. Tests as documentation;
slow tests = slow code; failing test before fix. Flaky tests are real
bugs, not tests to retry.

### Simplicity

Clarity = constraint, not aspiration. Reader-cost compounds.
Readability wins ties. Abstraction earns its place: 3 similar lines
> premature abstraction; 3rd use earns consideration not commitment;
single-user mixin = costume; "we might need this someday" = reason
not to extract. Local complexity > global. Cohesion across file >
brevity of any one file. Mixed-paradigm flavor: pure where possible,
immutable (`Data.define` records, frozen `with` semantics), pattern
matching for events, composition over inheritance (single-level
mixins, no multi-level framework hierarchies), errors as values where
clean else raise, blocks over higher-order callbacks. Comments answer
why-not-what. RBS in `sig/` is real type info; drift from
implementation = bug.

### Elm invariants

`init` and `update` return: bare model | `[model, Command::Cmd]` |
`[model, [Command::Cmd, ...]]`. Anything else raises `ArgumentError`
from `unwrap_result`. Commands are pure data; runtime executes.
`view(model)` is pure function of model; top level must be `window(...)`
node or array of windows (`Tree.normalize` raises otherwise). Subs
declarative; runtime diffs each cycle (short-circuits when only
`max_rate` changed). Widget event flow walks scope chain innermost-
first; handlers return `:ignored`/`:consumed`/`[:update_state, _]`/
`[:emit, family, data]`. Canvas-internal events auto-consumed if not
captured. Wire IDs: `window#scope/path/id`; events split into
`id`/`scope`/`window_id`; `Event.target(event)` reconstructs forward
path; commands use forward-order path strings.

### DSL discipline

Block-based DSL via `include Plushie::App`. Blocks yield in caller's
binding (no `instance_eval` against user blocks; `self` stays the
app instance, private helpers work). Thread-local context stack tracks
parent-child. New DSL form earns its place when: 2+ real users,
replaces harder-to-read runtime construct, real bug class detectable
at finalization time, generated code reads as cleanly as hand-written,
errors point at user's call site. Used: `define_method` for setters,
`class_eval(&block)` for `Widget.define`, module hooks, frozen
`Data.define` records. Avoided: `instance_eval` against user blocks
for the UI DSL, `method_missing` as routing, broad refinements, deep
inheritance. Generated code is what users read in stack traces; stable
predictable structure, named methods match expectations, errors name
DSL context.

### Concurrency shape

Three layers: Connection (pipe + framing + writer mutex + reader
thread), Bridge (restart logic + heartbeat watchdog + exponential
backoff), Runtime (Elm loop + model + tree + commands). Runtime
thread is the only thread that touches app state; other threads push
tagged tuples through a `BoundedQueue`. Dedicated threads for
`Command.task`/`Command.stream` (cancellable); single `TimerScheduler`
thread (deadline-based `IO.select`). GVL-aware: CPU-bound user work
belongs in `Command.task`; runtime doesn't block on I/O. Transport
adapters (spawn/stdio/iostream) earn their place. SessionPool
multiplexes mock/headless via `--max-sessions N`. No `Mutex` for app
state, no concurrent-ruby, no Async reactor, no fibers/ractors, no
auto-bootstrap.

### Common shapes -> outcomes

- "mock the renderer for speed" -> decline
- "reach into runtime via `instance_variable_get`" -> rewrite to
  Session API
- "add deprecation warnings / API hardening" -> decline; 1.0 sweep
- "this is O(n) on a hot path" -> need realistic N
- "split this large module" -> need forcing function
- "harden against malicious renderer" -> structurally protected;
  check if proposal loosens that, otherwise misframed
- "harden against malicious host" -> defer to capability-manifest
  (plushie-rust roadmap)
- "wire should encrypt / sign" -> outer transport's job
- "consolidate N redundant traversals" -> do
- "extract this single-use mixin" -> decline; costume
- "rescue Exception in this loop" -> no, `rescue StandardError`
- "let users return `nil` from update" -> no, bare model is no-change
- "rename field across SDKs" -> route through parity workflow
- "use `instance_eval` for the block DSL" -> no, breaks user `self`
- "switch runtime to fibers / ractors" -> stewardship-level question
- "add `method_missing` routing" -> default no; explicit definition
- "add a new DSL declaration form" -> run dsl-discipline criteria

## Before committing

Run `bundle exec rake`. It mirrors CI: tests, linter, type check.

For full preflight (including headless renderer tests against a fresh
build), run `bundle exec rake plushie:preflight`. When
`PLUSHIE_RUST_SOURCE_PATH` is set to a plushie-rust checkout, preflight
runs `cargo build --release -p plushie-renderer` against that workspace
first and exports `PLUSHIE_BINARY_PATH` so the headless tests use the
freshly built binary. Without it, the existing binary resolution chain
runs unchanged.

## Commit hygiene

Every commit should be self-contained and functional. Preflight
should pass at each commit, not just at the tip.

Commits after `origin/main` are unpublished and can be freely
amended, squashed, or reordered to keep the history clean. Run
`git fetch origin` first to ensure the boundary is current. Use
`--amend` to fold small fixes into the commit they belong to
rather than creating "fix the fix" commits. If a later commit
fixes a bug introduced by an earlier unpublished commit, squash
them together.

Never amend or rebase commits that are already on `origin/main`.

## Commit messages

Commit messages should describe what changed and why. Do not include:
- Counts of any kind (findings, files, tests, items). If the
  content is listed, the reader can count. Counts add noise.
- Ticket, review, or tracking IDs (R-001, PROJ-123, etc.)
- References to this file

More broadly, think carefully before including counts anywhere
(code comments, docs, log messages). If the count is derivable
from the surrounding content, it doesn't add value.

## Writing style

Do not use `--` (double dash) as a separator or em-dash substitute
in prose, docs, comments, or bullet lists. Use a single `-` for
list item separators and reword sentences to avoid inline dashes
(use commas, periods, colons, or parentheses instead). `--` should
only appear as part of CLI flag names (e.g. `--watch`, `--release`).

## Quick reference

```
bundle exec rake              # tests + linter + type check
bundle exec rake test         # tests only
bundle exec rake standard     # linter only
bundle exec rake steep        # type check only
bundle exec rake yard         # generate API docs to doc/
bundle exec ruby examples/counter.rb  # run an example (needs binary)
```

Test backend selection:
```
bundle exec rake test                              # mock (default, fastest)
PLUSHIE_TEST_BACKEND=headless bundle exec rake test  # real rendering, no display
PLUSHIE_TEST_BACKEND=windowed bundle exec rake test  # real windows (needs weston or Xvfb)
```

## Configuration

Environment variables:
- `PLUSHIE_BINARY_PATH`: path to the renderer binary (overrides all resolution)
- `PLUSHIE_RUST_SOURCE_PATH`: path to a local plushie-rust checkout.
  When set, `rake plushie:build` runs cargo-plushie out of that
  checkout via `cargo run -p cargo-plushie` (no install required).
- `PLUSHIE_TEST_BACKEND`: test backend: `mock`, `headless`, `windowed`
- `PLUSHIE_BIN_FILE`: override binary destination for download/build tasks
- `PLUSHIE_WASM_DIR`: override WASM output directory for download tasks

The native widget build delegates workspace generation and
`cargo build` to `cargo-plushie`. See `docs/versioning.md` for how
the installed cargo-plushie version is pinned to
`Plushie::PLUSHIE_RUST_VERSION`.

## Known gotchas

- **`width: "fill"` on intermediate containers.** Iced containers
  default to shrink-wrapping. If a row or column doesn't have
  `width: "fill"`, its children's `width: "fill"` has nothing to
  fill. This is the most common layout bug. Always check parent
  containers when a widget collapses to zero width.

- **Event field access: `event.value` not `event.data`.**
  All event payloads use the `value` field. Scalar events
  (input, slider) carry the value directly; structured events
  (pointer, key) carry a symbol-keyed Hash. There is no `data`
  field. Tests with manually constructed events hide type
  mismatches; always test through the renderer with
  `Plushie::Test::Case`.

- **Native widget tests need `new_instance()` in Rust.** The
  test framework's session pool multiplexes sessions over one
  renderer process. Native widgets that don't implement
  `new_instance()` cause the pool to hang. Add it to every
  PlushieWidget impl.

- **Steep and Widget.define blocks.** Steep cannot analyze the
  `class_eval` block inside `Widget.define` because it resolves
  `self` to the Widget module, not the new class. Widget files
  are excluded from the Steepfile check list. Their RBS
  declarations are retained for downstream type consumers.

## Ruby version

Requires Ruby >= 3.2 for `Data.define` and stable pattern matching.
Developed on Ruby 4.0+.

## Dependencies

Required (gemspec):
- `msgpack`: MessagePack encoding/decoding
- `logger`: standard Ruby logging (extracted from stdlib in Ruby 4.0)

Dev/test (Gemfile only):
- `minitest`: testing framework
- `standard`: linting (zero-config RuboCop)
- `rake`: task runner

## Project layout

```
lib/
  plushie.rb                      # top-level: Plushie.run / Plushie.start API
  plushie/
    version.rb                    # VERSION + PLUSHIE_RUST_VERSION constants
    model.rb                      # Model.define wrapper (Data.define + #with)
    node.rb                       # Node: immutable UI tree node (Data.define)
    app.rb                        # App module (include in user classes)
    ui.rb                         # block-based DSL (thread-local context stack)
    event.rb                      # all event Data types (Widget, Key, Ime, etc.)
    event/
      specs.rb                    # canonical event type catalog (BuiltinSpecs)
    command.rb                    # Command.Cmd Data type + constructor facade
    command/
      text.rb scroll.rb           # command submodules (text, scroll,
      window.rb window_query.rb   #   window, window_query, image)
      image.rb
    subscription.rb               # Subscription.Sub Data type + constructors
    effect.rb                     # platform effects (file dialogs, clipboard, etc.)
    tree.rb                       # normalization, delegation to search/diff
    tree/
      search.rb                   # find, exists?, ids, find_first, find_all
      diff.rb                     # LIS-based tree diff (patch generation)
    connection.rb                 # low-level protocol client (pipe management)
    bridge.rb                     # renderer lifecycle (restart, backoff)
    runtime.rb                    # Elm update loop, command/subscription engine
    runtime/
      commands.rb                 # command execution engine
      subscriptions.rb            # subscription lifecycle diffing
    protocol.rb                   # wire protocol facade
    protocol/
      encode.rb                   # outbound encoding (all message types)
      decode.rb                   # inbound decoding (all event families)
      keys.rb                     # named key and physical key wire maps
      parsers.rb                  # string-to-symbol parsers (mouse, modifiers)
    binary.rb                     # renderer binary resolution + download
    cargo_plushie.rb              # cargo-plushie resolver (source vs PATH)
    thread_pool.rb                # simple bounded thread pool for async
    encode.rb                     # canonical value encoding (fail-fast)
    widget.rb                     # unified widget system (Widget.define + include)
    widget_set.rb                 # widget DSL overrides (WidgetSet.create)
    canvas_widget.rb              # canvas widget extension system
    renderer_env.rb               # filtered subprocess environment (whitelist)
    dsl/
      buildable.rb                # Buildable pattern for DSL block types
    type/                         # property type modules
      a11y.rb alignment.rb anchor.rb border.rb color.rb
      content_fit.rb direction.rb filter_method.rb font.rb
      gradient.rb length.rb line_height.rb padding.rb position.rb
      shadow.rb shaping.rb style_map.rb theme.rb wrapping.rb
    widget/                       # typed builder modules
      build.rb                    # shared build helpers
      native_build.rb             # native widget build: virtual manifest + cargo-plushie shell-out
      button.rb canvas.rb checkbox.rb column.rb combo_box.rb
      container.rb floating.rb grid.rb image.rb keyed_column.rb
      markdown.rb overlay.rb pane_grid.rb pick_list.rb pin.rb
      pointer_area.rb progress_bar.rb qr_code.rb radio.rb
      responsive.rb rich_text.rb row.rb rule.rb scrollable.rb
      sensor.rb slider.rb space.rb stack.rb svg.rb table.rb
      text.rb text_editor.rb text_input.rb themer.rb toggler.rb
      tooltip.rb vertical_slider.rb window.rb
    canvas/
      shape.rb                    # pure shape builder functions
      shape/                      # typed shape structs
        canvas_image.rb canvas_svg.rb canvas_text.rb circle.rb
        clip.rb dash.rb drag_bounds.rb group.rb hit_rect.rb
        line.rb linear_gradient.rb path.rb rect.rb
        shape_style.rb stroke.rb transform.rb
    transport/
      framing.rb                  # frame encode/decode for raw byte streams
      tcp_adapter.rb              # iostream adapter for TCP sockets
    animation.rb                  # animation system (descriptors + SDK-side tween)
    animation/
      transition.rb               # renderer-side timed transition descriptor
      spring.rb                   # renderer-side spring physics descriptor
      sequence.rb                 # renderer-side sequential animation chain
      tween.rb                    # SDK-side interpolation (host-driven)
    route.rb                      # navigation stack
    selection.rb                  # single/multi/range selection
    undo.rb                       # undo/redo with coalescing
    data.rb                       # DataQuery: filter/search/sort/paginate
    state.rb                      # path-based state with revisions
    key_modifiers.rb              # modifier query predicates
    dev_server.rb                 # file watcher + hot reload
    rake.rb                       # Rake task definitions
    test.rb                       # test framework loader
    test/
      case.rb                     # Minitest case with setup/teardown
      rspec.rb                    # RSpec integration helpers
      helpers.rb                  # test DSL (click/find/assert_text/etc.)
      session.rb                  # test session (Elm loop + renderer I/O)
      session_pool.rb             # shared renderer process, session mux
      snapshot.rb                 # tree hash + screenshot assertions
      script.rb                   # .plushie script parser
      script/
        runner.rb                 # script executor
examples/
  counter.rb clock.rb todo.rb async_fetch.rb
  notes.rb shortcuts.rb color_picker.rb rate_plushie.rb
  widgets/                        # example custom widget extensions
    color_picker_widget.rb star_rating.rb theme_toggle.rb
```

## Architecture

### Layered design

- **Layer 0: Wire** (`Protocol::Encode`, `Protocol::Decode`).
  Pure encoding/decoding for every message type in protocol.md.
  No I/O; works with any data source.

- **Layer 1: Connection** (`Plushie::Connection`).
  Manages the pipe to the renderer binary. Spawns the process,
  handles framing, thread-safe writes via Mutex, reader thread
  pushes decoded messages to a Queue. Usable standalone for
  scripting and custom architectures.

- **Layer 2: Runtime** (`Plushie::Runtime`).
  The Elm update loop. init/update/view cycle, tree diffing,
  command execution (async via ThreadPool, timers, widget/window
  ops, effects), subscription lifecycle, error recovery, renderer
  restart (exponential backoff).

- **Layer 3: App** (`Plushie::App`).
  `include Plushie::App` gives the UI DSL, default callbacks,
  convenience aliases (Event, Command, Subscription).

- **Layer 4: Test** (`Plushie::Test`).
  Session pool manages a shared `plushie --mock --max-sessions N`
  process. Each test gets an isolated session. All three backends
  (mock/headless/windowed) are transparent.

### Concurrency model

All state lives in the runtime thread. Events are processed
sequentially from a `Thread::Queue`. No shared mutable state
between threads; the Queue is the sole synchronization point.

- **Runtime thread**: sequential event processing
- **Bridge thread**: reads renderer stdout, pushes to queue
- **Thread pool**: bounded (CPU count) for Command.async work
- **Timer threads**: for send_after and subscription timers
- **Write mutex**: Connection#send_message is thread-safe

## Testing

All app testing goes through the renderer binary. No Ruby-side
mocks or stubs. The mock backend is fast enough for TDD.

Test flow:
1. Session pool starts `plushie --mock --max-sessions N`.
2. Test gets a session ID, sends Settings + initial Snapshot.
3. `click("#btn")` sends Interact to the renderer.
4. Renderer returns synthetic events via interact_response.
5. Test feeds events through app.update, re-renders, patches.
6. `assert_text("#count", "1")` sends Query and checks result.

Headless mode uses interact_step round-trips (renderer injects
real iced events, waits for snapshot back after each step).

## Non-obvious patterns

**Thread-local DSL context.** The block-based UI DSL uses a
thread-local stack (`UI::Context`) to track parent-child
relationships. Blocks execute in the caller's binding (no
`instance_eval`), so `self` stays the app instance and private
helpers work. Widget calls (e.g. `button(...)`) append to the
current context as side effects, not return values.

**Model.define immutability.** `Model.define` wraps `Data.define`
and adds `.with()` for partial updates returning new frozen
instances. Forgetting to reassign the result is a silent no-op.

**Encode fail-fast.** `Encode.encode_value` raises `ArgumentError`
on unknown types immediately, never silently passing through.
Custom types implement `.to_wire()` for wire serialization.

**Return validation.** `update` must return a bare model or
`[model, command]`. Invalid shapes raise with a helpful message.

**Error recovery.** Exceptions in update/view are rescued
(`StandardError` only), logged, and the previous model is
preserved. After 100 consecutive errors, log output is suppressed
entirely until every 1000th error.
`NoMatchingPatternError` gets a special message suggesting an
`else` clause.

**Bridge restart.** When the renderer crashes, exponential backoff
restart (100ms to 1600ms, max 5 retries). The Bridge handles
connection lifecycle; the Runtime owns the resync (re-sends
settings, fresh snapshot, subscription sync).

**Effect tracking.** Effects use a two-way wire ID mapping
(`@effect_tags`, `@effect_ids`). Responses arrive with a wire ID
that the runtime maps back to the user's tag for delivery as
`Event::Effect`.

**Subscription diffing.** After each update, `sync_subscriptions`
diffs the new set against active ones. If only `max_rate` changed
(keys unchanged), it short-circuits and updates rates without
re-creating subscriptions. Renderer subscriptions (key press, etc.)
do not take a tag; the management key is `[type, window_id]`.

**Widget system.** One unified system for all widgets. Two entry
points: `Widget.define(:type) { ... }` for declarative widgets
(leaf, container, native) and `include Plushie::Widget` for
behavioral widgets (with view/state/events). Both share the same
DSL (prop, children, positional, default_a11y, state, event,
cache_key) and finalization pipeline. Widget.define returns a
fully-formed class (mirrors Data.define). Classes using `include`
are lazily finalized on first instantiation. Widget view output
is rendered during tree normalization. Events flow through the
scope chain before reaching `app.update()`.

**A11y defaults.** Widgets declare `default_a11y role: :button,
label_from: :label`. During build, `Build.resolve_a11y` produces
a string-keyed hash (wire-ready format). The `:label_from`
directive copies the named prop value into the `label` field.
User-provided a11y overrides win per field.

**Event::Specs.** Canonical catalog of all built-in widget event
types with carrier (:none/:value), field declarations, and type
hints. Widget events have category predicates: `event.pointer?`,
`event.keyboard?`, `event.pane?`, `event.focus?`, `event.drag?`.

**Canvas widget registry.** Registry keys are scoped IDs directly
(e.g. `"main#form/rating"`), matching the normalized tree ID
format. No separate composite key; `widget_key(window, local)`
just joins with `#`.

**Tree submodules.** Search and diff are extracted into
`Tree::Search` and `Tree::Diff`. Tree delegates to them. Both
are type-checked by Steep. The LIS-based diff algorithm produces
minimal patches for reordered children.

**Memo caching.** `UI::MemoCache` is a thread-local prev/current
cache. The runtime seeds it before each render and captures it
after. Memo nodes (`__memo__`) check the cache by deps; widget
`cache_key` checks by props+state. Both skip re-rendering on
cache hit.

**Status-based focus tracking.** The renderer emits `status`
events for interactive widgets. The runtime intercepts these to
track `@focused_widget_id` and derives `:focused`/`:blurred`
Widget events from status transitions. No per-widget opt-in
needed.

**Bridge heartbeat.** A watchdog timer detects hung renderers.
When no message arrives within `heartbeat_interval` (default
30s), a synthetic close is pushed to trigger the restart path.

## Reference SDK

The plushie-elixir SDK (`../plushie-elixir/`) is the primary
reference for Ruby due to similar dynamic language conventions.
Consult it for architecture patterns when adding features.

## Related repositories

These are expected as sibling directories (e.g. `../plushie-rust/`):

- plushie-rust - Rust workspace (SDK, widget SDK, renderer)
- plushie-elixir - Elixir SDK (reference implementation)
- plushie-gleam - Gleam SDK
- plushie-iced - vendored iced fork

## Protocol reference

The wire protocol is defined in `../plushie-rust/docs/protocol.md`.
That document is the source of truth for all message types, event
families, and interaction semantics.
