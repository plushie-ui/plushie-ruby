# The Development Loop

The pad has a layout but the preview does not work yet. In this
chapter we bring it to life with two complementary techniques:
**hot reload** for editing the pad's own source code, and
**runtime compilation** for evaluating experiment code typed into
the pad's editor.

Along the way we will learn how to inspect a running app, a useful
debugging skill.

## Hot reload

Chapter 2 introduced `dev: true` on `Plushie.run`. Make it the
default for local development by flipping it on in the launcher.
Edit `bin/plushie_pad` to watch `lib/` whenever you run the pad:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "plushie_pad"

Plushie.run(PlushiePad::App, dev: true)
```

Or use the Rake task shipped with the gem, which wires the same
flag through a positional argument:

```bash
bundle exec rake 'plushie:run[PlushiePad::App,dev]'
```

Hot reload depends on the [listen](https://rubygems.org/gems/listen)
gem. Add it to the development group of your Gemfile:

```ruby
group :development do
  gem "listen"
end
```

Without `listen`, `dev: true` logs a warning and runs without
watching (see `lib/plushie/dev_server.rb`). Everything else still
works, but you lose the auto-reload behaviour.

Start the pad with `bin/plushie_pad`, edit any `.rb` file under
`lib/`, save, and the running app re-reads the file and re-renders.
The model is preserved across reloads: text you typed into the
editor stays put, the file list stays populated, the undo history
survives.

Hot reload works because `Plushie::DevServer` watches the
configured directories (default `["lib/"]`), debounces rapid saves,
calls `Kernel#load` on each changed file, and pushes a
`:force_rerender` message into the runtime's event queue. The
runtime re-runs `view(model)`, diffs the result against the
previous tree, and sends only the changed patches to the renderer.
The model object is never touched.

Customise the watched directories with `dev_dirs:` when the source
is spread across more than `lib/`:

```ruby
Plushie.run(PlushiePad::App, dev: true, dev_dirs: ["lib/", "experiments/"])
```

See the [Configuration reference](../reference/configuration.md#runtime-options)
for the full list of runtime options.

## Making the preview work

The editor holds Ruby source. We want to evaluate that source and
render the resulting widget tree in the preview pane. Ruby makes
this easy: a string of source can be fed to `Module#module_eval`
on a fresh anonymous `Module`, keeping the experiment's constants
isolated from the pad's own namespace.

Three steps, each a single standard-library call:

1. **Create an anonymous module** with `Module.new`.
2. **Evaluate** the source inside it with `module_eval`.
3. **Invoke** the module's `view` method and return the node.

Create `lib/plushie_pad/compile.rb`:

```ruby
# frozen_string_literal: true

module PlushiePad
  # Compile a user-typed Ruby experiment at runtime.
  #
  # An experiment is a Ruby module (or class) that exposes a
  # zero-arity `view` method returning a Plushie node tree. The
  # source is evaluated inside an anonymous Module to isolate it
  # from the pad's own namespace; the module's `view` is then
  # invoked.
  module Compile
    def self.compile_and_render(source)
      mod = Module.new
      mod.module_eval(source)
      experiment = mod.const_defined?(:Experiment) ? mod.const_get(:Experiment) : mod
      unless experiment.respond_to?(:view)
        return [:error, "experiment must define Experiment.view"]
      end
      tree = experiment.view
      [:ok, tree]
    rescue ScriptError, StandardError => e
      [:error, "#{e.class}: #{e.message}"]
    end
  end
end
```

Every failure mode (syntax error, missing constant, typo in a
widget name, nil returned from `view`, exception raised mid-build)
collapses to `[:error, message]`. The pad displays the message in
the preview pane and never crashes. `ScriptError` catches
`SyntaxError` and its friends; `StandardError` catches runtime
failures like `NoMethodError` and `NameError`.

A fresh anonymous module on every save means redefining
`Experiment` or any constant does not collide with the previous
save.

## Wiring up the save button

`compile_and_render` returns either `[:ok, tree]` or
`[:error, message]`. Store both outcomes on the model: a
successful tree in `preview`, a failure message in `error`. The
view shows whichever is set.

Extend the pad's model with the new fields and add a starter
source:

```ruby
Model = Plushie::Model.define(
  :source,   # current editor buffer (String)
  :preview,  # last successful render (Node or nil)
  :error    # compile error text (String or nil)
)

STARTER = <<~RUBY
  module Experiment
    def self.view
      Plushie::Widget::Column.new("root", padding: 16, spacing: 8)
        .push(Plushie::Widget::Text.new("greeting", "Hello, Plushie!", size: 24))
        .push(Plushie::Widget::Button.new("btn", "Click me"))
        .build
    end
  end
RUBY
```

Experiments use the struct API (`Plushie::Widget::X.new(...).build`)
rather than the block DSL. The DSL relies on a thread-local
`Plushie::UI::Context` that is only active inside `view(model)`;
evaluating it from `module_eval` has no active context and the
calls produce orphan nodes. Struct construction has no such
dependency and works in any context.

Compile the starter on init so the preview pane is populated
before the user touches anything:

```ruby
def init(_opts)
  preview, error = render(STARTER)
  Model.new(source: STARTER, preview: preview, error: error)
end

private

def render(source)
  case PlushiePad::Compile.compile_and_render(source)
  in [:ok, tree]
    [tree, nil]
  in [:error, msg]
    [nil, msg]
  end
end
```

Add two `update` arms: one for editor input (store the new
source), one for the save button (recompile). Remember that
`model.with(...)` returns a new frozen struct; you must return
it from `update` for the change to stick.

```ruby
def update(model, event)
  case event
  in Event::Widget[type: :input, id: "editor", value: source]
    model.with(source: source)

  in Event::Widget[type: :click, id: "save"]
    preview, error = render(model.source)
    model.with(preview: preview, error: error)

  else
    model
  end
end
```

Render whichever of `preview` or `error` is currently set in the
preview pane:

```ruby
def preview_pane(model)
  container("preview", width: [:fill_portion, 2], height: :fill, padding: 16) do
    if model.error
      text("error", model.error, color: "#cc3333")
    elsif model.preview
      Plushie::UI::Context.current&.push(model.preview) || model.preview
    else
      text("placeholder", "Press Save to compile")
    end
  end
end
```

The `Context.current&.push` line embeds an already-built subtree
into the block DSL's current context. Without it, the node would
be returned but never attached as a child of the `container`.

Type experiment code in the editor, click Save, and the preview
updates. Break the syntax and the error text replaces the preview.
Fix it, save again, and the tree returns.

See the [Events reference](../reference/events.md) for the event
taxonomy, particularly the `Event::Widget` shapes that the save
and editor handlers match on.

## The experiment format

An experiment is a Ruby source string that defines a module named
`Experiment` with a class method `view`:

```ruby
module Experiment
  def self.view
    Plushie::Widget::Column.new("root", padding: 16, spacing: 8)
      .push(Plushie::Widget::Text.new("title", "Hello, Plushie!", size: 20))
      .push(Plushie::Widget::Button.new("btn", "Click me"))
      .build
  end
end
```

Experiments are pure: no state, no `update`, just a `view` that
builds a widget tree. The preview pane embeds the returned node
directly under `container("preview")`, which scopes every child ID
under `preview/` (see the
[Scoped IDs reference](../reference/scoped-ids.md)).

## Iterating on experiments

The meta-demonstration: use the pad to iterate on experiment code
without restarting the pad, while you also iterate on the pad's
own view without restarting either.

Two loops run simultaneously:

- **The pad's loop.** Edit `lib/plushie_pad/app.rb`, save, and the
  `DevServer` reloads the file. The running runtime re-renders
  with the updated `view` and `update` definitions.
- **The experiment's loop.** Type code into the pad's editor, hit
  Save (or Ctrl+S), and `Compile.compile_and_render` evaluates the
  new source in a fresh module. The preview pane updates.

Neither loop restarts the renderer. The renderer subprocess stays
alive, windows stay open, scroll positions stay put, focus stays
where the user left it. Only the view tree changes.

## Debugging techniques

### The event log

The pad already keeps an event log pane at the bottom of the
window. Every event that does not match an explicit `update` arm
falls through to the catch-all branch and gets formatted into the
log. When a widget is not doing what you expect, watch the log as
you interact with it: you will see the exact event variant
dispatched, including `id`, `scope`, and payload.

Chapter 5 expands the log into a full event inspector.

### Logging

`Plushie::Runtime` exposes its logger on the handle returned from
`Plushie.start`. Set the log level at runtime-option time:

```ruby
Plushie.run(PlushiePad::App, dev: true, log_level: :debug)
```

`log_level:` applies to both the SDK's Ruby-side logger and the
renderer subprocess (via `RUST_LOG`). For just the renderer, set
`RUST_LOG` explicitly:

```bash
RUST_LOG=plushie=debug bin/plushie_pad
```

See the [Configuration reference](../reference/configuration.md#rust_log)
for the RUST_LOG value table.

### Printing the tree

`rake plushie:inspect` renders `init`'s initial view to JSON
without starting a renderer. It is the fastest way to confirm that
your view builds what you think it builds:

```bash
bundle exec rake 'plushie:inspect[PlushiePad::App]'
```

The output is the normalised tree (scoped IDs applied, widget
expansion done) pretty-printed with `JSON.pretty_generate`. Pipe
it through `jq` to navigate a large tree.

### Recording `.plushie` scripts

Once you have a repeatable bug or a flow worth pinning, capture it
as a `.plushie` script and replay it. Scripts live under
`test/scripts/` by default:

```bash
bundle exec rake 'plushie:script[test/scripts/save_flow.plushie]'
bundle exec rake 'plushie:replay[test/scripts/save_flow.plushie]'
```

`plushie:script` runs against the mock backend (fast, no window);
`plushie:replay` uses the windowed backend so you can watch the
sequence visually. See the
[Testing reference](../reference/testing.md) for the script syntax
and the [Rake Tasks reference](../reference/rake-tasks.md) for the
task details.

### Inspecting a running app from IRB

Ruby has no built-in REPL-attach-to-process story, but
`Plushie.start` returns the runtime handle on the current process,
and the handle exposes the current model directly. Use it from a
script or a `binding.irb` checkpoint:

```ruby
require "plushie_pad"

runtime = Plushie.start(PlushiePad::App, dev: true)

# ... interact with the window ...

binding.irb  # drops you into IRB in the same process
```

At the IRB prompt:

```
irb> runtime.model
=> #<data PlushiePad::App::Model source: "...", preview: ..., error: nil, ...>
irb> runtime.model.active_file
=> "hello.rb"
irb> runtime.get_focused
=> "editor"
irb> runtime.view_error?
=> false
```

| Handle method | Returns |
|---|---|
| `runtime.model` | The current model (a frozen `Data` instance) |
| `runtime.get_focused` | ID of the focused widget, or `nil` |
| `runtime.view_error?` | `true` if the last `view` call raised |
| `runtime.get_diagnostics` | Prop-validation diagnostics, when enabled |

Because the model is a `Data` instance, `pp runtime.model` prints
field names and values in readable form. Drop into IRB any time
the UI looks wrong and read the model; the mismatch is usually
obvious.

For a mid-session checkpoint without restarting, add a debug
button to the pad that prints the model to stderr:

```ruby
in Event::Widget[type: :click, id: "debug"]
  warn(model.inspect)
  model
```

See the [App Lifecycle reference](../reference/app-lifecycle.md)
for the complete list of runtime queries.

## Common pitfalls

### Forgetting to return `model.with(...)`

`with` returns a new frozen instance; it does not mutate. A
branch that calls `with` without returning the result is a silent
no-op:

```ruby
# Bug: the new model is discarded.
in Event::Widget[type: :input, id: "editor", value: source]
  model.with(source: source)
  model
```

The branch returns the original `model`, the editor content never
sticks, and the view shows the stale source. The fix is to drop
the extra `model` and return the `with` call directly. If the
pad's editor seems to forget what you type, check for this.

### Frozen model mutations

Every model built with `Plushie::Model.define` is frozen.
Attempting to write to it raises `FrozenError`:

```ruby
model.source = source  # FrozenError
```

The error message names the field, so it is easy to diagnose the
first time. Use `model.with(source: source)` instead.

### Stale renderer binary

Pulling a new version of the gem updates the SDK's wire protocol
but not the renderer binary under `bin/`. The
handshake will fail with a protocol-version mismatch and the
runtime will exit with a message pointing at the version
disagreement. Re-download the binary:

```bash
bundle exec rake 'plushie:download[force]'
```

For local plushie-rust development, rebuild it:

```bash
PLUSHIE_RUST_SOURCE_PATH=../plushie-rust bundle exec rake 'plushie:build[release]'
```

See the [Rake Tasks reference](../reference/rake-tasks.md) for the
download and build tasks in detail.

### `listen` not installed

With `dev: true` but no `listen` gem, the dev server logs a
warning and proceeds without watching. Saves do not trigger
reloads. Add `gem "listen"` to the development group of your
Gemfile and rerun `bundle install`.

### Experiments using the block DSL

The block DSL (`column do ... end`) depends on a thread-local
context that is only active inside the `view(model)` call the
runtime makes. Experiments are evaluated outside that context, so
block-form widget calls attach to nothing and the rendered tree is
empty or oddly shaped. Use the struct form
(`Plushie::Widget::Column.new(...).push(...).build`) in experiment
source. The pad's own `view` continues to use the DSL.

## Try it

With the pad running under `dev: true`:

- Break an experiment: remove a closing `end`, save, and read the
  error in the preview. Fix it and save again.
- Change the pad's own `view` (colours, spacing, toolbar order)
  while the pad is running. Watch the window update without losing
  the editor contents.
- Drop a `binding.irb` into an `update` arm. The pad window will
  pause until you exit IRB. At the prompt, poke at `self` (the
  app), `model`, and `event`.
- Record a `.plushie` script that opens the pad, types a syntax
  error, and verifies the error text. Replay it with
  `rake 'plushie:replay[...]'` and watch it happen in a real
  window.

In the next chapter we extend the event log into a full event
inspector, so you can see exactly what each widget emits when you
interact with it.

## See also

- [App Lifecycle reference](../reference/app-lifecycle.md), the
  full list of runtime query methods and the update cycle
- [Configuration reference](../reference/configuration.md), the
  `dev`, `dev_dirs`, and `log_level` runtime options
- [Rake Tasks reference](../reference/rake-tasks.md), `plushie:run`,
  `plushie:inspect`, `plushie:script`, and `plushie:replay`
- [Testing reference](../reference/testing.md), `.plushie` script
  syntax and replay behaviour

## Next chapter

[Events](05-events.md)
