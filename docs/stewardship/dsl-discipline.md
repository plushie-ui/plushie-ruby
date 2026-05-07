# DSL discipline

The DSL is the largest user-facing surface in plushie-ruby.
`Plushie::UI` (the block DSL included by `Plushie::App`),
`Plushie::Widget` (custom widget authoring, both
`Widget.define` and `include`), the `Plushie::DSL::Buildable`
pattern, and the per-widget builder modules under
`Plushie::Widget::*` all sit here. It is also the surface most
prone to drift, the one most expensive to retroactively get
right, and the one with the highest readability stakes because
generated classes show up in stack traces and IDE tooling.

This doc describes the posture for adding to the DSL, the
discipline around Ruby's metaprogramming tools, and keeping
generated code honest.

## What the DSL is for

`include Plushie::App` gives the user the full widget
vocabulary as private methods on the app class. The shape is:

- Block-form children for containers: `column do ...; row do
  ...; end; end`. Blocks run in the caller's binding (no
  `instance_eval`), so `self` stays the app instance and
  private helpers work normally.
- Keyword arguments for props: `text("count", "Count: 0",
  size: 18)`.
- Auto-IDs for display widgets where the call site is a stable
  enough proxy: `text("Hello")` is fine; `text_input("name")`
  needs an explicit ID because it is stateful.
- Thread-local context tracking: the parent-child relationship
  comes from a `UI::Context` stack, not from block return
  values. Widget calls append to the current context as side
  effects; the block's value is discarded.

The DSL is not a backdoor for arbitrary code generation. Every
widget method is a thin shape over a runtime call; what a
declaration generates is what a user could have written by
hand using `Plushie::Node.new(...)`.

## When a new DSL form earns its place

The DSL is permissive about adding widgets (every widget uses
the same `Widget.define` or `include Plushie::Widget` shape;
no extension question). It is conservative about adding new
declaration forms (a new block scope, a new prop type, a new
event spec form, a new metaprogramming pattern).

A new DSL form earns its place when:

- At least two existing or imminent users want the same shape.
- The form replaces a runtime construct that is harder to read
  or harder to validate at the call site.
- A meaningful class of bugs becomes detectable at finalization
  time (when `Widget.define` returns or when the class is
  first instantiated) that runtime checks would catch only
  on first event.
- The generated code reads as cleanly as what the user would
  have written by hand.

A new DSL form does not earn its place when:

- The argument is "we could make this look prettier."
  Prettier alone is not the bar; readability of the resulting
  code at the call site and in stack traces is.
- The argument is "this would let users write less code." If
  the existing form already reads cleanly, fewer characters
  is not the bar.
- The argument is "this would be more idiomatic in Ruby." See
  `posture.md`. Cross-SDK shape is the constraint; Ruby idiom
  is downstream of that.

A new DSL form is rejected when:

- It hides indirection that a reader of the call site would
  not expect.
- The generated code reads worse than the equivalent hand-
  written form.
- The error messages it produces are vague or point at
  framework internals instead of the user's call site.

## Metaprogramming, judiciously

Ruby gives the DSL author rich metaprogramming tools. The same
power that makes a clean DSL possible makes an opaque DSL easy
to write. The codebase leans on a few patterns and avoids
others.

Used:

- **`define_method`** for generating widget setters
  (`set_<prop>`), structural mutators, and per-instance methods
  that close over computed defaults. This is straightforward
  codegen: each property declaration produces one method,
  predictable in shape and visible in `instance_methods`.
- **`class_eval(&block)`** for `Widget.define` to run the
  declaration block in the context of the new class.
  `Data.define`-style, returning a fully-formed class. The
  pattern is deliberate and documented; Steep cannot resolve
  `self` inside it, so widget files with this pattern are
  excluded from the Steepfile (with RBS retained for
  consumers).
- **Module hooks (`included`, `extended`)** for wiring
  behavior into classes that mix in `Plushie::App` or
  `Plushie::Widget`. Predictable, documented, and surfaces
  in stack traces under the mixing class's name.
- **Frozen `Data.define` records** for events, commands, and
  subscriptions. Allocation is paid once at class definition;
  per-instance allocation is a single object; equality and
  hashing are correct by default.

Avoided unless there is a real win that ordinary code cannot
deliver:

- **`instance_eval` against user-supplied blocks** for the UI
  DSL. The cost is real: `self` shifts inside the block, so
  user helper methods on the app class stop working. The DSL
  uses thread-local context tracking and yields to the block
  in the caller's binding instead, which keeps `self` stable.
  Where `instance_eval` is the right tool (a builder object
  that explicitly is the new context, like
  `Plushie.configure { |c| ... }` passing the configuration
  to the block as an argument), it is fine; against a block
  that is supposed to look like normal Ruby code in the user's
  class, it is not.
- **`method_missing`** as a routing mechanism. Every
  `method_missing` site has to also implement `respond_to?`
  correctly, document the resolution rules clearly, and accept
  that typos silently route to the missing-method handler
  instead of producing a clear `NoMethodError`. The DSL uses
  explicit method definition; widgets are real methods on
  the app class.
- **Refinements applied broadly.** Refinements are scoped, so
  they do not leak across files, but the scoping rules are
  subtle and tooling support is uneven. The codebase does not
  use them.
- **Deep inheritance chains.** Single-level mixins (`include
  Plushie::App`, `include Plushie::Widget`) are clear; multi-
  level "framework hierarchies" obscure where behavior comes
  from. Composition through smaller mixins with explicit
  hooks is the shape that scales.

## Generated code is what users read

Stack traces from generated code show up in user error
reports. Errors raised from inside generated methods land in
the user's debugging session. The shape of generated code
matters:

- Generated method bodies have stable, predictable structure.
  A user reading `MyWidget.instance_method(:set_value).source`
  in `irb` should not be confused about what they are
  looking at.
- Generated names match user expectation. `new`, `with_*`,
  `set_*`, `build`. No unstable internal names that change
  between versions.
- Errors from generated code name the macro context. A prop
  type validation failure says "unknown prop type :foo for
  :value in MyWidget," not "Plushie::DSL::Buildable raised."

The DSL authors hold this line. A change to codegen that makes
the runtime path clearer at the cost of generated-code
readability is the wrong direction.

## Errors point at the call site

A DSL error that points at framework internals is broken. The
user wants to know which line of their code is wrong, not
which line of `Plushie::Widget` is doing the checking.
Backtrace cleanup, `caller_locations`, and `raise ..., caller`
where appropriate; line tracking through nested DSL
invocations where it matters.

A useful error message:

- Names what is wrong in the user's terms (the prop name, the
  widget name, the container name).
- Names what was expected (the supported types, the supported
  containers, the required form).
- Points at the user's source line, not the framework source
  line.

Vague error messages from the DSL are bug-class. They cost
users time and they cost us issue triage.

## What this looks like in practice

- A user proposes "let widgets declare deprecated props with
  custom messages." Real bug class? Maybe (cross-SDK rename
  windows). Two real users? Currently no. Outcome: defer until
  a rename actually needs it; pre-1.0 we just rename.
- A user proposes "the block DSL should support bare top-level
  widget calls without a `view` method." Could work, but the
  cost is a separate evaluation context that does not match
  what the rest of the codebase does. Outcome: decline; the
  `view` method shape is the contract.
- A user proposes "auto-derive `to_wire` for new prop types
  from a declarative schema." Real bug class? Type drift
  between similar prop types is a recurring issue. Two real
  users? Yes, every new prop type. The generated `to_wire`
  reads as cleanly as hand-written? Yes for primitive
  composites; no for types with custom coercion rules.
  Outcome: incremental - auto-derive for simple cases, hand-
  written for complex ones, with the line documented.
