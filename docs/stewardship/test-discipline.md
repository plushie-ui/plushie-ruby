# Test discipline

How tests are written, what they cost, and what they commit to.
The discipline below shows up in plushie-ruby's own test suite
and in parallel form across every host SDK. It is one of the
project's load-bearing conventions.

## The integration spine

Tests exercise the real renderer. The default test backend
(`mock`) runs `plushie-renderer --mock`: real binary, real wire
protocol, real codec, real Core engine. The only thing the
default backend strips is the GPU rendering step. Tests dispatch
events, read model and tree state, and assert on observable
behavior through the same API user apps use.

A test that passes against a pure-Ruby mock and would fail
against the binary is worse than no test. It gives confidence
on the exact class of bugs the integration is meant to catch:
wire format drift between encoder and renderer, startup
handshake ordering, codec edge cases, lifecycle on bridge
restart, the small protocol-level details that pure-language
mocks have no mechanism to diverge on.

This is not about coverage as a metric. It is about catching
the bugs that matter where they actually live, which is at
boundaries.

## Three test modes

The renderer offers three runtime modes; the test backends
follow them by name. The naming is a cross-SDK contract.

- **mock**: microseconds to milliseconds per test.
  Protocol-only. Real binary, real wire, real Core, no
  rendering. The default for most tests; fast enough that a
  full suite runs through the binary without flinching.
  `bundle exec rake test` uses this.
- **headless**: tens to low hundreds of milliseconds per test.
  Real rendering via tiny-skia, no display server. Used when
  the test cares about pixels: screenshot golden files, tree-
  hash assertions, layout-affecting bugs.
  `PLUSHIE_TEST_BACKEND=headless bundle exec rake test`.
- **windowed**: seconds per test. Full iced rendering with a
  real display (Xvfb on Linux, native display elsewhere). Used
  when the test cares about full window lifecycle, focus
  events, or platform-specific behavior.

The names mean the same thing in plushie-rust, plushie-elixir,
plushie-gleam, plushie-typescript, plushie-python. Findings
about naming or behavior drift between the three modes route
through the parity workflow.

## Pooled mock backend

`Plushie::Test::SessionPool` starts a single
`plushie-renderer --mock --max-sessions N` process and
multiplexes tests over it. Each test gets isolated state via
session IDs in every wire message. This keeps mock-mode startup
amortized across the suite rather than paid per test. Windowed
mode does not pool: each test gets its own renderer.

Tests use either `Plushie::Test::Case` (Minitest) or
`Plushie::Test::RSpec` (RSpec). Both wire up session lifecycle
through `setup`/`teardown` (Minitest) or `before`/`after`
(RSpec) hooks; the same `Helpers` module supplies the
interaction DSL (`click`, `find!`, `assert_text`, `model`,
`tree`, etc.) so tests are interchangeable between frameworks.

## Synchronous test API

Tests synchronize with the runtime through the `Session` object.
`click("#btn")` blocks until the resulting events have been
applied; `assert_text` blocks until the rendered tree reflects
the assertion (or the timeout fires). The user does not need to
sleep, poll, or pump events manually.

Reading state through the session API ensures tests exercise
the real code path and that the synchronization barriers tests
rely on also exist for production callers. Direct poking at
the runtime's internal instance variables is not a pattern;
when an internal state question shows up in a test, the right
move is to expose it through the session, not to reach in.

## When stubs are acceptable

A pure-Ruby stub that does not go through the renderer is
acceptable only for failure modes the binary cannot exhibit
cleanly:

- Forced renderer crash simulation (the binary cannot be told
  "panic now" via the protocol).
- Malformed wire bytes the codec rejects before any typed
  delivery path runs.
- Direct `update` calls to test pure return-shape behavior
  where no runtime context is needed (e.g., asserting that an
  unsupported return shape raises with the expected message).
- Test infrastructure that wraps the integration primitives
  themselves.

If a test can run against the binary, it does. The bar for
adding a non-binary stub is "what failure mode does this
expose that nothing else can," answered concretely.

## Tests as documentation

Tests should read as a story for the next person who opens the
file. A clear setup, an explicit action, an assertion that
names what is being verified. Behavior-driven shape: the test
framework is incidental; what is being verified should be
obvious from the test name and the body.

Both Minitest and RSpec are first-class. Minitest's `def
test_<name>` and RSpec's `it "<description>"` both serve as
section headers; comment-based section headers are noise.

The corollary: tests are not allowed to be slow. If a test is
slow, the underlying code path is usually slow in production
too. Speed up the code; do not accept the slow test. mock-mode
exists to skip the GPU step, not to hide a slow code path
behind a faster harness.

## Failing test before fix

For a bug fix, write the failing test first when possible. A
test added alongside the fix that would have passed without
the fix proves nothing about the bug. The failing test is the
definition of done.

Exceptions: refactors with no behavior change (the existing
suite is the regression net), and new features where the test
and the implementation arrive together.

## Implications

- A feature has to be testable through the renderer. If a
  feature cannot be exercised through the integration spine,
  that is a design problem with the feature, not a problem
  with the test discipline.
- "Let's mock the renderer for speed" proposals are declined.
  Speed comes from mock-mode in the real binary, which is
  already fast; the cost of a pure-Ruby mock is the bug class
  it hides.
- Coverage as a percentage is a non-goal (see
  `goals-and-non-goals.md`). Coverage of real surfaces is what
  matters; the integration spine is what produces it.
- Tests that reach into runtime internals via
  `instance_variable_get` (or similar) are a regression and get
  rewritten to use the public session API.
- A test that passes occasionally and fails occasionally is
  almost always a real concurrency bug in the runtime or the
  test setup, not a "flaky test" to be retried. Diagnose
  before papering over.
