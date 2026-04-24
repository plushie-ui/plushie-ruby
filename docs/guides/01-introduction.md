# Introduction

## What is Plushie?

Plushie is a native desktop GUI platform with SDKs for several
languages. This guide covers the Ruby SDK.

When you build an app with Plushie, you get real native windows, not
Electron, not a web view. Your application is a plain Ruby process
that owns all the state. A separate Rust binary handles rendering,
input, and platform integration.

The renderer is built on [Iced](https://github.com/iced-rs/iced), a
mature cross-platform GUI toolkit for Rust. It handles GPU-accelerated
rendering, offers a software fallback for headless environments, and
covers accessibility (keyboard navigation, screen readers). You never
interact with Iced directly. Plushie talks to it over a wire protocol,
and you write everything in Ruby.

## The Elm architecture

Plushie follows the [Elm architecture](https://guide.elm-lang.org/architecture/),
a pattern for building UIs around one-way data flow. If you have used
Elm, Redux, or LiveView, the shape will feel familiar. It is the same
model, update, view cycle, just running on the desktop instead of the
browser.

There are three pieces:

**Model** is your application state. It can be any Ruby object:
usually a `Plushie::Model.define(...)` struct, but a hash, an array,
or a single integer all work. Plushie does not impose a schema.
Whatever your `init` callback returns becomes the initial model.

**Update** is a method that receives the current model and an event,
then returns the next model, optionally paired with commands. Events
come from user interaction (a button click, a key press), from the
system (a window resized, a timer fired), or from your own async
work. The update method is where all state transitions happen.

**View** is a method that takes the current model and returns a
window node, or an array of window nodes, describing what should be
on screen. The runtime calls `view` after every successful update.
You never mutate the UI directly, you return a description of what
the screen should look like based on the current state. A single
window app returns one window. A multi-window app returns several.

The cycle looks like this:

    event -> update -> new model -> view -> UI tree -> render

This is the entire control flow. Events go in, state comes out, the
view reflects it. There is no two-way binding and no hidden mutation.
When something looks wrong on screen, look at the model. When the
model is wrong, look at the event that changed it. Every bug has a
short trail.

Plushie also supports [subscriptions](../reference/subscriptions.md),
declarative specs for ongoing event sources like timers, keyboard
shortcuts, and window events. Your app declares which subscriptions
are active based on the current model, and the runtime starts and
stops them automatically.

One-off side effects (HTTP fetches, file dialogs, clipboard writes,
window operations) are expressed as [commands](../reference/commands.md)
returned from `update` alongside the new model. The runtime executes
them and feeds the results back as events.

## How it works

Your Ruby application and the renderer run as two OS processes that
exchange messages over stdio by default. Other transports (stdio
pipe, TCP socket) are available for remote and embedded scenarios.

Your application builds UI trees using the block DSL mixed in by
`Plushie::App`. The runtime holds the model and runs the update
and view cycle on a dedicated thread. When `view` produces a new
tree, the runtime diffs it against the previous one and sends only
the changes to the renderer over a wire protocol (MessagePack by
default, JSON Lines is available for debugging).

The renderer receives patches, updates its internal widget tree,
and renders frames. When the user interacts with the UI (clicks a
button, types in an input, resizes a window), the renderer sends
[events](../reference/events.md) back over the same connection. The
runtime decodes them and feeds them into your `update` method, and
the cycle continues.

The two process split gives you resilience. If the renderer crashes,
Plushie restarts it with exponential backoff and re-syncs your
application state. Your model is never lost. If your `update` method
raises, the runtime catches the exception, reverts to the previous
model, logs the error, and carries on. Neither process can take the
other down.

Because the processes communicate over a byte stream, they do not
need to run on the same machine. Your Ruby app can run on a server
or embedded device with no display and no GPU, while the renderer
runs wherever there is a screen. This is how you build desktop UIs
for headless infrastructure, remote sessions over SSH, or IoT
devices.

## A tiny working app

Here is a complete counter. Save it as `counter.rb`:

```ruby
require "plushie"

class Counter
  include Plushie::App

  Model = Plushie::Model.define(:count)

  def init(_opts) = Model.new(count: 0)

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "inc"]
      model.with(count: model.count + 1)
    in Event::Widget[type: :click, id: "dec"]
      model.with(count: model.count - 1)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Counter") do
      column(padding: 16, spacing: 8) do
        text("count", "Count: #{model.count}")
        row(spacing: 8) do
          button("inc", "+")
          button("dec", "-")
        end
      end
    end
  end
end

Plushie.run(Counter)
```

That is the whole app. One model, one `update` method that pattern
matches on events, one `view` method that describes the window
tree. Everything in this guide builds on this shape.

## The development loop

The typical workflow is short.

1. Write your app class.
2. Run it with `rake 'plushie:run[Counter]'` (or directly with
   `ruby counter.rb` once the renderer binary is installed).
3. The window opens, you interact with it, you close it.
4. Edit the code, run it again.

Plushie supports hot reloading in development mode. With
`Plushie.run(Counter, dev: true)`, the runtime watches source files
and reloads your code in place when they change, preserving the
current model. The [development loop guide](04-the-development-loop.md)
covers the workflow in detail.

## Why the Elm architecture

The same shape that made Elm pleasant in the browser pays off on
the desktop too.

**Pure `update`.** State transitions are an ordinary Ruby method
that takes a model and an event and returns a new model. You can
call it directly from a Minitest test with no renderer involved,
and you can replay a sequence of events against any starting model
to reproduce a bug.

**Immutable model.** `Plushie::Model.define` wraps `Data.define`, so
instances are frozen. The only way to produce a changed model is to
call `model.with(field: value)`, which returns a new frozen instance.
This rules out a large class of "who mutated what, and when" bugs.

**Explicit commands.** Side effects do not happen in the middle of
`update`. Instead `update` returns a command (or an array of them)
alongside the new model, and the runtime executes the commands after
the render. The result comes back as an event on the next cycle.
This means a glance at `update` tells you both what the state
becomes and which effects are about to run.

**One-way data flow.** Events flow from the renderer into `update`,
the new model flows into `view`, the resulting tree flows out to
the renderer. No callback reaches back to mutate something three
layers away. When something looks wrong, the trail is short.

## SDK layers

The Ruby SDK is organised in layers so you can drop down a level
when you need to.

| Layer | Module | Responsibility |
|---|---|---|
| Entry point | `Plushie.run`, `Plushie.start` | Instantiate the app and start the runtime |
| App mixin | `Plushie::App` | Mixes in the DSL, default callbacks, and aliases for `Event`, `Command`, and `Subscription` |
| Runtime | `Plushie::Runtime` | Event loop, tree diffing, command and subscription lifecycle |
| Bridge | `Plushie::Bridge` | Renderer process lifecycle, restart with exponential backoff |
| Connection | `Plushie::Connection` | Protocol framing and pipe I/O |
| Protocol | `Plushie::Protocol` | Encode and decode every wire message |

Most apps only touch the top two layers. `Plushie.run(Counter)`
instantiates your class, builds a runtime, opens the pipe to the
renderer, and blocks the calling thread until the runtime exits.
`Plushie.start(Counter)` does the same but on a background thread,
returning a handle you can stop later.

Inside an `App` class, the short names `Event`, `Command`, and
`Subscription` resolve to `Plushie::Event`, `Plushie::Command`, and
`Plushie::Subscription`. Reference prose in this guide uses the
fully qualified names, examples inside a class body use the
aliases.

## What you can build

Plushie is a general purpose desktop toolkit:

- Desktop tools and utilities: file managers, text editors, system
  monitors, anything you would reach for a native toolkit for.
- Dashboards and data visualisation: connect to your Ruby backend
  directly, no API layer needed. The built-in widget catalogue
  covers tables, charts via canvas, progress bars, and every
  common input control.
- Creative applications: the canvas system supports custom 2D
  drawing with shapes, paths, transforms, and interactive elements.
- Multi-window applications: your `view` returns an array of
  windows, each with its own layout, all managed from one model.
- Reusable widget libraries: compose existing widgets in pure Ruby,
  draw fully custom visuals with the canvas (including click,
  hover, drag, and keyboard interaction), or write Rust-backed
  native widgets when you need custom GPU rendering.
- Remote rendering: run your logic on a server or embedded device
  and render on a local display over SSH.

## Where to go next

The next chapter walks through installing the SDK, pulling down the
renderer binary, and running your first app end to end.

If you want a quick tour of a specific area before committing to
the guide in order, the reference pages are a good starting point:

- [App lifecycle](../reference/app-lifecycle.md) for the full
  callback contract.
- [Built-in widgets](../reference/built-in-widgets.md) for the
  widget catalogue.
- [Events](../reference/events.md) for every event type your
  `update` can receive.
- [Commands](../reference/commands.md) for the side-effect
  constructors.

## See also

- [App lifecycle reference](../reference/app-lifecycle.md)
- [Built-in widgets reference](../reference/built-in-widgets.md)
- [Events reference](../reference/events.md)
- [Commands reference](../reference/commands.md)
- [Subscriptions reference](../reference/subscriptions.md)

## Next chapter

[Getting Started](02-getting-started.md)
