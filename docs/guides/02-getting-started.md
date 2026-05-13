# Getting Started

This chapter walks from an empty directory to a running Plushie
application. By the end you will have a Ruby project with the gem
installed, the renderer binary in place, and a working counter app
on screen.

## Prerequisites

You need Ruby 3.2 or later. The gemspec pins
`required_ruby_version = ">= 3.2.0"` and CI covers 3.2, 3.3, and
4.0. Check your version with:

```bash
ruby --version
```

Plushie runs on Linux, macOS, and Windows. The renderer uses
[wgpu](https://wgpu.rs) for GPU rendering, so the machine needs a
working graphics stack: a native desktop session on Linux or macOS,
or a Windows desktop. Headless CI hosts need a headless
[weston](https://wayland.pages.freedesktop.org/weston/) socket
(preferred) or
[Xvfb](https://www.x.org/releases/current/doc/man/man1/Xvfb.1.xhtml)
for X11-only environments before `rake plushie:run` will open a
window. The Windowed test backend has the same requirement. The
Mock and Headless test backends work without a display server.

On Linux, most distributions ship the required GPU drivers by
default. If the renderer fails to start with a Vulkan or OpenGL
error, install your distribution's Vulkan user-space package
(`vulkan-icd-loader` on Arch, `mesa-vulkan-drivers` on Debian and
Ubuntu).

[Bundler](https://bundler.io) manages the gem. Most Ruby
installations include it. Check with:

```bash
bundle --version
```

## Creating a project

Start with an empty directory and a Gemfile.

```bash
mkdir hello_plushie
cd hello_plushie
```

Create `Gemfile`:

```ruby
source "https://rubygems.org"

gem "plushie"
gem "rake"
```

Pre-1.0, pin to an exact version once the gem is installed to avoid
surprise breakage from minor releases. After `bundle install`,
Bundler records the resolved version in `Gemfile.lock`, which is
enough for most projects; if you want the pin visible in the
Gemfile itself, change it to `gem "plushie", "== 0.6.0"` (or
whichever version `bundle install` resolved).

Create `Rakefile`:

```ruby
require "plushie/rake"
```

That single require registers every `plushie:` Rake task. See the
[Rake tasks reference](../reference/rake-tasks.md) for the full
list.

Fetch dependencies:

```bash
bundle install
```

## Installing the renderer binary

Plushie apps are two processes: your Ruby app and a Rust renderer
binary built on [Iced](https://github.com/iced-rs/iced). The Ruby
side owns state, events, and the widget tree. The renderer owns
windows, GPU rendering, and platform input. They talk over a pipe
using [MessagePack](https://msgpack.org) by default.

The renderer is not bundled with the gem. Install it one of two
ways.

### Option 1: download a precompiled binary

The fastest path. `rake plushie:download` fetches a precompiled
binary from GitHub releases, verifies its SHA-256 checksum, and
places it under `_build/plushie/bin/`:

```bash
bundle exec rake plushie:download
```

The version is pinned by the `Plushie::PLUSHIE_RUST_VERSION`
constant in the SDK, so the binary and the gem always match. The
download URL and destination are both derived from the current
platform (`plushie-renderer-linux-x86_64`,
`plushie-renderer-darwin-aarch64`, and so on). See the
[Versioning reference](../reference/versioning.md) for how the two
version numbers evolve.

To force a re-download, quote the argument for your shell:

```bash
bundle exec rake 'plushie:download[force]'
```

Checksum mismatches abort the download and leave any existing
binary in place. There is no flag to skip verification.

### Option 2: build from a local plushie-rust checkout

You need this path only when working on the renderer itself or
when adding native widgets (Rust-backed custom rendering). It
requires a [Rust toolchain](https://rustup.rs) with `cargo` on
`PATH`.

Clone plushie-rust as a sibling of your project:

```bash
git clone https://github.com/plushie-ui/plushie-rust ../plushie-rust
```

Then run the build task with the source path set:

```bash
PLUSHIE_RUST_SOURCE_PATH=../plushie-rust bundle exec rake plushie:build
```

The build drives `cargo-plushie` against the checkout and installs
the result where `Plushie::Binary.path!` will find it. For release
optimisations:

```bash
PLUSHIE_RUST_SOURCE_PATH=../plushie-rust \
  bundle exec rake 'plushie:build[release]'
```

Without `PLUSHIE_RUST_SOURCE_PATH`, the task expects
`cargo-plushie` on `PATH` at the version matching
`Plushie::PLUSHIE_RUST_VERSION`. Install it with:

```bash
cargo install cargo-plushie --version <version> --locked
```

The build task prints the right command on mismatch.

### Verifying the install

After either option, confirm the binary resolves:

```bash
bundle exec ruby -e "require 'plushie'; puts Plushie::Binary.path!"
```

This prints the absolute path to the renderer binary, or raises
with installation hints if nothing is resolvable.

## Your first app

Create `hello.rb`:

```ruby
require "plushie"

class Hello
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
    window("main", title: "Hello Plushie") do
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

Plushie.run(Hello)
```

Run it:

```bash
bundle exec ruby hello.rb
```

A native window opens titled "Hello Plushie" with a counter and
two buttons. Click `+` and `-` to change the count. Close the
window or press `Ctrl+C` in the terminal to stop.

## Reading the code

A quick tour of what each piece does.

- `include Plushie::App` mixes in the Elm loop callbacks
  (`init`, `update`, `view`, plus optional `settings`,
  `subscribe`, and `window_config`). It also imports the widget
  DSL (`window`, `column`, `row`, `text`, `button`, and the rest)
  directly into the class, so view methods read like HTML in
  Ruby.
- `Plushie::Model.define(:count)` returns a frozen struct based
  on Ruby's `Data`. `Model.new(count: 0)` creates one;
  `model.with(count: model.count + 1)` returns a new struct with
  the field replaced. Models are immutable by design.
- `case event / in Event::Widget[...]` uses Ruby's pattern
  matching. `Event::Widget` is a `Data.define` struct with
  fields `type`, `id`, `value`, `window_id`, and `scope`. The
  pattern only binds the fields it names, which makes each arm
  read cleanly.
- `window("main", title: "Hello Plushie") do ... end` declares a
  native OS window. The first argument is the window's ID, used
  for routing events back to `update`. Every view must return at
  least one `window(...)` node; widgets cannot live at the top
  level.
- `column(padding: 16, spacing: 8)` is a vertical layout
  container. `padding:` adds space around the edges (in pixels),
  `spacing:` adds space between children. `row(...)` is the
  horizontal counterpart.
- `button("inc", "+")` is a clickable button. First argument is
  the widget ID (`"inc"`), second is the label. Clicking it
  emits an `Event::Widget[type: :click, id: "inc"]` which the
  `update` pattern match catches.

The cycle: a click produces an event. The runtime calls
`update(model, event)` with the current model and the event. Your
function returns a new model. The runtime calls `view(new_model)`,
diffs the resulting tree against the previous one, and sends the
differences to the renderer. The renderer updates the display.
The round trip completes in milliseconds.

If `update` raises, the runtime catches the exception, logs it,
and keeps the previous model. The window stays open. This makes
it safe to iterate without worrying about a typo taking the app
down.

## Running with Rake

An alternative to `bundle exec ruby hello.rb` is the
`plushie:run` task, which resolves the app class by name and
forwards optional flags to `Plushie.run`:

```bash
bundle exec rake 'plushie:run[Hello]'
```

With dev mode (live reload):

```bash
bundle exec rake 'plushie:run[Hello,dev]'
```

With JSON on the wire (easier to inspect during debugging):

```bash
bundle exec rake 'plushie:run[Hello,json]'
```

Quote the bracketed argument. Both bash and zsh treat `[` and `]`
as glob metacharacters.

Rake expects the app class to be loadable by name. If `hello.rb`
is not on the load path, add the require to your Rakefile:

```ruby
require "plushie/rake"
require_relative "hello"
```

## Common setup gotchas

### plushie binary not found

If `Plushie.run` raises `Plushie::Error: plushie binary not
found`, the resolver could not find the renderer on any of its
search paths. The error message lists the three usable remedies:

```
rake plushie:download
rake plushie:build
export PLUSHIE_BINARY_PATH=/path/to/plushie
```

The resolution order, in full:

1. `PLUSHIE_BINARY_PATH` environment variable.
2. `Plushie.configuration.binary_path`.
3. Custom widget build under `_build/plushie/custom/target/`.
4. Downloaded binary under `_build/plushie/bin/`.

Explicit paths (the first two) raise if set but pointing to a
missing file. Implicit fallbacks stay within the current project.
See the
[Configuration reference](../reference/configuration.md).

### plushie binary not executable

On Linux and macOS the downloaded binary is chmod'd to `0755`
automatically. If you copied the binary manually or restored it
from an archive that lost permissions, re-apply them:

```bash
chmod +x _build/plushie/bin/plushie-renderer-*
```

### checksum mismatch on download

`rake plushie:download` verifies every download against a
`.sha256` sidecar fetched from the same GitHub release. A
mismatch means the release was tampered with, the CDN served a
stale response, or the SDK's `PLUSHIE_RUST_VERSION` does not
match any published release. Re-run the task. If it fails again,
check the release page directly at
`https://github.com/plushie-ui/plushie-renderer/releases`.

### cargo not found during build

`rake plushie:build` shells out to `cargo --version` first and
aborts early if `cargo` is not on `PATH`. Install Rust via
[rustup](https://rustup.rs) and open a new shell so the updated
`PATH` takes effect.

### cargo-plushie version mismatch

Without `PLUSHIE_RUST_SOURCE_PATH` set, the build task requires
`cargo-plushie` on `PATH` at the version matching
`Plushie::PLUSHIE_RUST_VERSION`. On mismatch the task prints the
exact `cargo install cargo-plushie --version X.Y.Z --locked`
command to run. With `PLUSHIE_RUST_SOURCE_PATH` set, this check
is bypassed because the workspace copy always matches the
checkout.

### No window appears on headless Linux

The `plushie:run` task needs a display server. On a headless CI
host or server, the preferred path is a headless
[weston](https://wayland.pages.freedesktop.org/weston/) socket:

```bash
export XDG_RUNTIME_DIR=$(mktemp -d)
weston -B headless --socket=plushie-run &
WAYLAND_DISPLAY=plushie-run XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR \
  bundle exec rake 'plushie:run[Hello]'
```

For X11-only environments, Xvfb works as an alternative:

```bash
Xvfb :99 -screen 0 1280x1024x24 &
DISPLAY=:99 bundle exec rake 'plushie:run[Hello]'
```

### Renderer log output is quiet

By default the renderer logs only errors. Enable verbose output
with `log_level:` on `Plushie.run`:

```ruby
Plushie.run(Hello, log_level: :debug)
```

Or with the `RUST_LOG` environment variable, which takes
precedence over `log_level:`:

```bash
RUST_LOG=plushie=debug bundle exec ruby hello.rb
```

`RUST_LOG` is forwarded to the renderer subprocess by
`Plushie::RendererEnv`.

## Troubleshooting

### The window opens but closes immediately

`Plushie.run` blocks until the last window closes. If your
`view` returns an empty `window { }` block with no non-widget
children, the window may still render (and you're done). If
`view` raises during the initial render, the runtime logs the
exception and exits. Run with `log_level: :debug` to see the
exception message.

### Events arrive but `update` never matches

Pattern matching with `case/in` is strict about field order and
names. `Event::Widget` is a `Data.define` struct with fields
`type`, `id`, `value`, `window_id`, and `scope`. Match only the
fields you care about:

```ruby
in Event::Widget[type: :click, id: "inc"]
```

A mismatched `type:` symbol (`"click"` vs `:click`) or a typo in
the widget ID will silently fall through to the `else` arm. When
debugging, print the event first:

```ruby
def update(model, event)
  puts event.inspect
  # ...
end
```

### Build hangs on first run

The first `rake plushie:build` compiles plushie-rust and a
workspace of native widgets from scratch, which takes several
minutes. Subsequent builds are incremental. If the first build
actually hangs (no progress for tens of minutes), check whether
`cargo` can reach crates.io:

```bash
cargo search plushie
```

Corporate networks sometimes block `index.crates.io`; see
[the cargo book](https://doc.rust-lang.org/cargo/reference/config.html#http)
for proxy configuration.

### Ruby 3.2 is too old for something I need

The SDK itself runs on 3.2. If a library you add to the same
project requires a newer Ruby, upgrade your Ruby version. Plushie
does not pin an upper bound on `required_ruby_version`.

## See also

- [Rake tasks reference](../reference/rake-tasks.md) for the full
  task listing, including arguments and environment overrides.
- [Configuration reference](../reference/configuration.md) for
  the binary resolution order, runtime options, and the
  `Plushie.configure` block.
- [Versioning reference](../reference/versioning.md) for the
  relationship between the gem version,
  `PLUSHIE_RUST_VERSION`, and the wire protocol.

## Next chapter

[Your first app](03-your-first-app.md) picks up where this one
leaves off and starts building a multi-file project from scratch.
