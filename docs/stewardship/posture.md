# Project posture

What plushie-ruby is, who it is for, and the disciplines that keep
it that way.

## What plushie-ruby is

The Ruby host SDK for Plushie. An Elm-architecture app runtime
that drives a renderer subprocess (Rust binary, native windows via
iced) over a typed wire protocol on stdin/stdout. The SDK ships as
a RubyGems package; user classes `include Plushie::App`, declare
their UI with the block DSL, and the runtime handles diffing,
command dispatch, subscriptions, thread management, and bridge
lifecycle.

This SDK is one of six host SDKs sharing the renderer (Elixir,
Rust, Gleam, Python, Ruby, TypeScript). The renderer binary is
shared; each SDK implements its own runtime against it.

## Audience

- App developers writing Plushie apps in Ruby. They see
  `Plushie::App`, the block DSL, the Event/Command/Subscription
  data classes, and the test framework.
- Widget authors writing pure-Ruby widgets via
  `Plushie::Widget.define` or `include Plushie::Widget`, or wiring
  native (Rust) widgets in via the same surface.
- SDK maintainers. The DSL surface, the Connection/Bridge/Runtime
  split, the wire codecs, the test backends, the threading
  contract.

The gem's public API is what `yardoc` documents. Modules and
methods marked `@api private` are internal regardless of where
they sit. Submodules under `Plushie::Runtime`, `Plushie::Protocol`,
`Plushie::Tree`, and the `Plushie::DSL` codegen are internal.
`Plushie::App`, `Plushie::Event`, `Plushie::Command`,
`Plushie::Subscription`, `Plushie::Model`, `Plushie::Node`,
`Plushie::Widget`, the test framework, and the top-level
`Plushie.run` / `Plushie.start` are public.

## Cross-SDK relationship

Six host SDKs is a load-bearing constraint, not an accident.

- **plushie-elixir is the canonical reference SDK for API shape.**
  When a concept's name, structure, or parameter ordering is
  contested, what plushie-elixir does is the answer. plushie-ruby
  follows. "More idiomatic in Ruby" alone is not justification
  for breaking parity.
- **plushie-rust is the protocol authority.** Wire format,
  message variants, codec details. Wire-format questions route
  there.
- **Cross-SDK parity is audited** via the sibling
  `plushie-sdk-parity/` repo. Findings about parity drift route
  through that workflow rather than as standalone work here.
- **Within-language idiom prevails on syntax.** Ruby-flavored DSL
  (block-based with thread-local context, snake_case methods,
  symbol keys, `Data.define` records, pattern matching with
  `case/in`), Ruby naming conventions, and Ruby's runtime shape
  (threads, queues, fibers if needed) are right and final.
  Concepts, names, parameter ordering, and behavior converge with
  the other SDKs.

A rename here that does not propagate to plushie-elixir (and
through it the rest) is drift, not refactoring. Where Ruby idiom
forces a syntactic divergence (block DSL vs macro DSL,
`Data.define` records vs structs, `case/in` pattern matching vs
multi-clause function heads), the divergence is in the syntax;
the concept, the field name, and the ordering hold.

## Stage

Pre-1.0. There is no backwards-compatibility obligation today.
When the best design requires renaming a method, a field, or
restructuring a module, that is the right call. The CHANGELOG
notes breaking changes explicitly.

The 1.0 boundary is when stability obligations begin. Until then,
the priority is getting the shape right, not preserving the
current shape. Pre-1.0 is the time to settle questions about API
shape, naming, and structure that will be expensive to revisit.

API stability hardening (deprecation warnings, sealed event types,
documented compatibility windows, frozen RBS surface) lands in a
single planned sweep at the 1.0 cut, not piecemeal during normal
development.

## Disciplines

Recurring decision rules. Not negotiable on a per-ticket basis.

- **Tests run through the real renderer.** The default test
  backend runs `plushie-renderer --mock`: real binary, real wire
  protocol, real codec, real Core engine, no GPU. A test that
  passes against a pure-Ruby mock and would fail against the
  binary is worse than no test. See `test-discipline.md`.
- **Cross-SDK claims are verified, not assumed.** When the
  question is "does plushie-elixir do this the same way," the
  answer comes from reading source on each side. "It looks like"
  is not a verification.
- **Design before code at boundaries.** The gem's public API,
  the DSL surface, the wire protocol on the Ruby side, the test
  backend contract. Internal refactors can iterate fast; boundary
  changes pay the design tax up front.
- **Clarity is the bar.** Code reads clearly to a Ruby engineer
  new to the file; abstractions earn their place by use, not by
  hypothesis; complexity is a cost. See `simplicity.md`.
- **No half-built features.** A feature lands fully or not at
  all. Half-built features create drift in the parity surface
  and accumulate into "the docs say it does X but three SDKs do
  not actually."
- **Local cleanup, not scope creep.** Small, low-risk
  improvements to code under active modification are welcome.
  Larger or risky adjacent improvements get noted and advocated
  for as follow-on work, not silently rolled into the current
  change.
- **No legacy or compatibility shims.** Pre-1.0; remove dead
  paths cleanly rather than preserving old behavior.
