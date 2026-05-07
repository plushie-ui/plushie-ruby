# Simplicity

The bar code in plushie-ruby has to clear, and the recurring
tradeoffs about structure and abstraction that decide what earns
its place. The other stewardship docs (`performance-bar.md`,
`resilience.md`, `test-discipline.md`, `dsl-discipline.md`,
`concurrency-shape.md`) each carry a flavor of this implicitly;
this doc states it directly so questions about "should we extract
this" or "is this clear enough" have an explicit reference.

This is not a style guide. Naming, formatting, lint rules, and
language-specific idioms live in `standardrb`, the project's
`.rubocop.yml` (via Standard), and the `frozen_string_literal`
magic comment. This doc is about the posture above those: when
to add complexity, when to refuse it, what clarity costs, and
what readability buys.

## Clarity is a constraint, not an aspiration

Code in plushie-ruby has to read clearly to a Ruby engineer who
has not been in this codebase before. "It works" is the floor;
"it can be understood without context" is the bar.

Every reader pays the cost of obscure code. The author writes
it once; many readers will read it. Small clarity wins compound
across hundreds of files; small obscurity losses compound the
other way. Same compounding argument that drives the lightweight-
by-default stance in `performance-bar.md`, applied to reader
cost instead of CPU cost.

The bar is not negotiable. Optimizations, abstractions,
defensive layers, refactors, and DSL additions all have to
clear it; the readability test wins ties.

## Abstraction has to earn its place

Extracting a helper, a module, a mixin, a class, a metaclass:
each carries cost. A reader has to follow the indirection, hold
the abstraction's contract in their head, and decide whether
what the call site shows reflects what the abstraction does
inside. The benefit has to clearly outweigh that cost.

Working rules:

- **Three similar lines is better than a premature abstraction.**
  Two pieces of code that look similar today might diverge
  tomorrow; extracting them now locks them together for reasons
  that may not survive contact with future requirements.
- **By the third use of a similar pattern, the abstraction
  earns consideration.** Not commitment, consideration. The
  question is whether the three uses are the same concept or
  three coincidentally similar ones.
- **An abstraction with one user is a costume, not an
  abstraction.** Single-use indirection is overhead. A mixin
  with one includer, a base class with one subclass, a method
  that wraps one call site.
- **"We might need this someday" is a reason not to extract.**
  Generic code written for hypothetical future users is the
  recurring source of half-built abstractions that nobody fully
  understands later. The DSL is especially vulnerable here; see
  `dsl-discipline.md`.
- **Generic where specific would do is harder to read.** A
  concrete `Data.define` record beats a generic `Hash` shape
  when the parameterization does not have at least two real
  uses.

These are working positions, not absolute rules. The burden is
on the proposed abstraction to push against them.

## Local complexity over global complexity

A 200-line method that does one thing clearly is preferable to
the same logic spread across five files in pursuit of "smaller
methods." Locality is a feature: a reader can hold the whole
thing in view. Following control flow across ten indirections
costs more than reading a longer linear sequence.

Module size on its own is not a problem. A large module is not
an invitation to split unless a real change is forced to bend
around its existing shape. Refactoring without a forcing
function is a non-goal (`goals-and-non-goals.md`); this is one
of the places that rule shows up most often. The runtime is
large because the runtime does a lot; that is fine.

Files split for the sake of "smaller files" frequently end up
with cross-file dependencies that obscure the same logic the
single file made obvious. Cohesion across a file beats brevity
of any one file.

## Mixed-paradigm flavor

Ruby is multi-paradigm. The codebase leans on the paradigm that
fits the situation:

- **Pure functions where possible.** The wire codec, value
  encoding, tree diff, type modules. They take inputs and
  return outputs; no side effects, no hidden state. Side
  effects push to the edges (Connection owns I/O, the runtime
  performs commands, user `update` is rescued).
- **Immutable data over in-place mutation.** `Data.define` for
  events, commands, models. The model `with` pattern returns
  a new frozen instance rather than mutating in place. Fields
  in normalized tree nodes use frozen hashes. Mutation that
  exists is local and visible (the runtime's instance state,
  the thread-local context stack).
- **Pattern matching for events.** The `case event in
  Event::Widget[type: :click, id: "save"]` shape is the natural
  fit for the event union. Branching `if`/`elsif` chains over
  symbol fields and hash keys are a less direct expression of
  the same dispatch. Where pattern matching does not earn its
  place (a single-shape lookup, a simple boolean), a `case` or
  `if` is fine.
- **Composition over inheritance.** `include Plushie::App` is a
  mixin; `include Plushie::Widget` is a mixin; the runtime
  composes `Commands` and `Subscriptions` modules into the
  Runtime class. There is no deep inheritance chain. Single-
  level inheritance from a base class (`Plushie::Test::Case <
  Minitest::Test`) is fine; multi-level "framework" hierarchies
  are not.
- **Errors as values where it reads cleanly; raise where it
  doesn't.** `Encode.encode_value` raises on unknown types
  because the caller cannot meaningfully recover; the
  `interact` API on `Test::Session` returns structured failure
  results because the caller's reaction matters. Both are
  fine; the wrong shape is `nil` returns from methods that
  should signal failure.
- **Blocks over higher-order callbacks.** Ruby blocks are
  ergonomic; the DSL leans on them. A method that takes both a
  block and a callback proc is usually doing two things.

Ruby idiom prevails on syntax (snake_case methods, symbol
keys, `keyword:` arguments, blocks, pattern matching). The
concept-level patterns above converge with the rest of the
project ecosystem (see `posture.md` on the cross-SDK story).

## Comments earn their place too

Code should explain itself. Comments answer questions the code
cannot:

- A non-obvious constraint or invariant the surrounding code
  holds.
- A surprising or subtle behavior a reader might trip on.
- A workaround for a specific external issue that the reader
  needs to understand to evaluate the code.

Comments are not for explaining what the next line does. If a
comment is needed to explain what, the code itself usually
wants to be clearer.

YARD docstrings (`@param`, `@return`, `@example`) are
documentation, not comments; they have a different purpose and
a different bar. Public methods carry docstrings that read as
user-facing documentation. Internal methods use `@api private`
rather than empty docstrings.

## RBS and Steep

RBS declarations under `sig/` are real type information, not
decoration. Steep checks the files listed in `Steepfile`;
files with heavy metaprogramming (the `Widget.define`
`class_eval` blocks, the `Data.define` block overrides) are
excluded because Steep cannot resolve `self` correctly inside
them, but the RBS declarations are retained for downstream
type consumers. Adding to or changing RBS without keeping it
in sync with the implementation is bug-class.

## Implications

- Abstractions added without justifying use are declined, even
  when technically correct.
- Refactors that fragment a coherent module into smaller files
  without a forcing function are declined.
- Half-built abstractions (extracted but only partially
  applied, or extracted with planned consumers never arriving)
  are bug-class. Either complete the application or fold the
  abstraction back into the call sites.
- Reviewer comments of the form "I had to re-read this three
  times" are first-class and earn a rewrite, regardless of
  whether the code is correct as written.
- RBS declarations that drift from the implementation are a
  real bug, not a documentation update.
