# Configuration

Plushie is configured at three levels: environment variables for
deployment and CI, the `Plushie.configure` block for project-wide
defaults, and runtime options on `Plushie.run` or `Plushie.start` for
per-instance control. Most projects need minimal configuration: build
or download the renderer binary and go.

Configuration lives on `Plushie::Configuration` (the singleton exposed
as `Plushie.configuration`). App-level render settings and per-window
defaults come from the `settings` and `window_config` callbacks on
`Plushie::App`.

## Environment variables

| Variable | Purpose |
|---|---|
| `PLUSHIE_BINARY_PATH` | Explicit path to the renderer binary. Overrides all other resolution. |
| `PLUSHIE_RUST_SOURCE_PATH` | Path to a local [plushie-rust](https://github.com/plushie-ui/plushie-rust) checkout for source builds. |
| `PLUSHIE_TEST_BACKEND` | Test backend: `mock` (default), `headless`, or `windowed`. |
| `PLUSHIE_BIN_FILE` | Override binary destination for `rake plushie:download` and `rake plushie:build`. |
| `PLUSHIE_WASM_DIR` | Override WASM output directory for `rake plushie:download`. |
| `RUST_LOG` | Renderer log verbosity. Set to `plushie=debug` for full protocol logging. |

### PLUSHIE_BINARY_PATH

Forces a specific renderer binary. Useful in CI where the binary is
pre-built and stored at a known path, or in production deployments
where the binary ships alongside the gem. If set but pointing to a
missing file, resolution raises immediately rather than falling
through to other paths.

### PLUSHIE_RUST_SOURCE_PATH

Points to a local checkout of the plushie-rust repository. When set,
`rake plushie:build` runs the workspace copy of `cargo-plushie` via
`cargo run -p cargo-plushie` (no install required), and `Binary.path!`
will fall through to a `target/release` or `target/debug` binary built
inside that checkout. Typical setup is a sibling directory:

```bash
git clone https://github.com/plushie-ui/plushie-rust ../plushie-rust
PLUSHIE_RUST_SOURCE_PATH=../plushie-rust bundle exec rake plushie:build
```

### RUST_LOG

Controls the renderer's log output using the standard `env_logger`
format. The renderer subprocess inherits this variable. Common values:

- `plushie=debug`, full protocol and rendering detail
- `plushie=info`, connection events and major state changes
- `plushie=warn`, warnings only

When `RUST_LOG` is not set, the runtime derives the renderer's log
level from the `log_level:` option on `Plushie.run`.

## Binary resolution order

`Plushie::Binary.path!` is the single source of truth for locating the
renderer. Explicit paths raise on a missing file; implicit fallbacks
silently advance to the next option:

1. `PLUSHIE_BINARY_PATH` environment variable
2. `Plushie.configuration.binary_path`
3. Custom extension build under `_build/plushie/custom/target/`
4. Downloaded binary under `_build/plushie/bin/`
5. Sibling plushie-rust checkout's `target/{release,debug}/`
6. `plushie` on system `PATH`

If nothing resolves, the error message lists the three usable
remedies: `rake plushie:download`, `rake plushie:build`, or exporting
`PLUSHIE_BINARY_PATH`.

## The configure block

Global settings live on `Plushie::Configuration`. Set them once at
boot:

```ruby
Plushie.configure do |config|
  config.binary_path = "/opt/plushie/bin/plushie"
  config.source_path = "~/projects/plushie-rust"
  config.widgets     = [MyGauge, MyChart]
  config.build_name  = "my-dashboard-plushie"
  config.widget_config = {
    "sparkline" => { "max_samples" => 1000 }
  }
end
```

The same values are readable as `Plushie.configuration.binary_path`
and friends. The configure block is idempotent: each call updates the
shared singleton in place.

| Attribute | Type | Default | Purpose |
|---|---|---|---|
| `binary_path` | `String, nil` | `nil` | Explicit renderer binary path. `PLUSHIE_BINARY_PATH` takes precedence. |
| `source_path` | `String, nil` | `nil` | Local plushie-rust checkout. `PLUSHIE_RUST_SOURCE_PATH` takes precedence. |
| `build_name` | `String` | `"plushie-custom"` | Cargo binary target and installed filename for custom-widget builds. |
| `widgets` | `Array<Class>` | `[]` | Widget classes to include in custom builds via `rake plushie:build`. |
| `widget_config` | `Hash` | `{}` | Per-widget runtime config, forwarded to the renderer in the `settings` message. Keyed by widget namespace. |
| `test_backend` | `Symbol, nil` | `nil` | Preferred test backend. `PLUSHIE_TEST_BACKEND` takes precedence. |
| `artifacts` | `Array<Symbol>` | `[:bin]` | Artifacts installed by download and build tasks. Set to `[:bin, :wasm]` for projects that need the WASM renderer too. |
| `bin_file` | `String, nil` | `nil` | Override binary destination for download and build. `PLUSHIE_BIN_FILE` takes precedence. |
| `wasm_dir` | `String, nil` | `nil` | Override WASM output directory for download. `PLUSHIE_WASM_DIR` takes precedence. |
| `validate_props` | `Boolean` | `false` | Enable renderer-side prop validation. The renderer emits diagnostic events for unknown or invalid props. Useful in dev and test to catch typos and type mismatches. |

When both the env var and the config attribute are set, the env var
wins. This keeps CI overrides working without requiring changes to
application code.

## Runtime options

`Plushie.run(app_class, **opts)` starts an app in the foreground and
blocks until exit. `Plushie.start(app_class, **opts)` returns a
runtime handle for background use. Both forward keyword arguments to
`Plushie::Runtime.new`:

```ruby
Plushie.run(MyApp, transport: :spawn, format: :msgpack, log_level: :debug)

handle = Plushie.start(MyApp)
handle.stop
```

| Option | Type | Default | Purpose |
|---|---|---|---|
| `transport` | `:spawn`, `:stdio`, `[:iostream, adapter]` | `:spawn` | How the SDK talks to the renderer. |
| `format` | `:msgpack`, `:json` | `:msgpack` | Wire format. JSON is human-readable for debugging. |
| `daemon` | `Boolean` | `false` | When `true`, the runtime keeps running after the last window closes so it can open new ones. |
| `binary` | `String, nil` | auto-resolved | Renderer binary path. Defaults to `Plushie::Binary.path!`. |
| `log_level` | `Symbol` | `:error` | Renderer log verbosity (`:off`, `:error`, `:warn`, `:info`, `:debug`, `:trace`). Mapped to `RUST_LOG` via `Plushie::RendererEnv`. |
| `token` | `String, nil` | `nil` | Authentication token sent on the initial handshake. |
| `dev` | `Boolean` | `false` | Enable live code reloading via `Plushie::DevServer`. |
| `dev_dirs` | `Array<String>, nil` | `["lib/"]` | Directories the dev server watches for changes. |

## App settings callback

`Plushie::App` defines an optional `settings` callback that provides
application-level defaults to the renderer. The result is sent once
during the initial handshake and applies to every window the app
opens. Override it alongside `init`, `update`, and `view`:

```ruby
class MyApp
  include Plushie::App

  def settings
    {
      default_text_size:  16,
      theme:              :dark,
      fonts:              ["assets/fonts/inter.ttf"],
      default_event_rate: 60,
      antialiasing:       true
    }
  end

  def init(_opts) = Model.new(count: 0)
  def update(model, _event) = model
  def view(_model)
    window("main", title: "MyApp") { text("hello", "Hello") }
  end
end
```

| Key | Type | Purpose |
|---|---|---|
| `default_font` | `Hash` | Default font spec (same shape as the `font:` prop on text widgets). |
| `default_text_size` | `Numeric` | Default text size in pixels for every text widget. |
| `antialiasing` | `Boolean` | Enable font antialiasing. |
| `vsync` | `Boolean` | Synchronise frame presentation with the display refresh rate. |
| `scale_factor` | `Numeric` | Multiplier on top of OS DPI scaling. `2.0` on a 2x HiDPI display gives 4x physical pixels per logical pixel. Per-window overrides use the `scale_factor` window prop. |
| `theme` | `Symbol, Hash` | Built-in theme (`:dark`, `:light`, `:nord`, `:catppuccin_mocha`, ...), `:system` for the OS preference, or a custom palette built with `Plushie::Type::Theme.custom`. |
| `fonts` | `Array<String>` | Paths to font files to load at startup. Loaded fonts are available by family name in any widget's `font:` prop. |
| `default_event_rate` | `Integer` | Maximum events per second for coalescable event types (pointer moves, scroll, slider drags, animation frames). Per-subscription `max_rate` and per-widget `event_rate` override this. |
| `widget_config` | `Hash` | Per-namespace config for native widgets. Keys match the widget's Rust-side namespace; values pass through to the widget on the renderer side. Also settable via `Plushie.configuration.widget_config`. |
| `required_widgets` | `Array<String>` | Native widget namespaces the renderer must advertise at handshake. Missing widgets produce a diagnostic and, on strict mode, refuse the session. |

If `Plushie.configuration.widget_config` is non-empty, the runtime
merges it into whatever `settings` returns before encoding. Setting
`Plushie.configuration.validate_props = true` appends
`validate_props: true` the same way. Values from `settings` win over
configuration values on conflict.

## Window configuration callback

`window_config(model)` is called every time the runtime opens a new
window. It returns a hash of default window props that are merged
with, and overridden by, the per-window props declared on the
`window(...)` node in `view`:

```ruby
class MyApp
  include Plushie::App

  def window_config(_model)
    {
      width:  1024,
      height: 768,
      decorations: true,
      resizable:   true,
      theme:       :dark
    }
  end

  def view(model)
    [
      window("main", title: "Main"),
      window("prefs", title: "Preferences", width: 480, height: 360)
    ]
  end
end
```

The main window inherits the callback's width and height; the prefs
window overrides them with its own values.

Recognised window prop keys: `title`, `size`, `width`, `height`,
`position`, `min_size`, `max_size`, `maximized`, `fullscreen`,
`visible`, `resizable`, `closeable`, `minimizable`, `decorations`,
`transparent`, `blur`, `level`, `exit_on_close_request`,
`scale_factor`, `theme`. Unknown keys are dropped during extraction.

The `size:` tuple form (`[width, height]`) decomposes into separate
`width:` and `height:` entries on the wire, matching the renderer's
expected shape. The same decomposition applies to `min_size:` and
`max_size:`.

## Handshake order

Startup sequences the handshake in a fixed order so the renderer
always sees configuration before content:

1. The runtime connects to the renderer subprocess and reads the
   `hello` message. `required_widgets` from `settings` are validated
   against the renderer's advertised extensions. A mismatch produces
   a `RequiredWidgetsMissing` diagnostic.
2. `encode_settings` sends the merged app `settings` plus any
   `widget_config` and `validate_props` overrides from
   `Plushie.configuration`. The runtime prepends the current
   `PROTOCOL_VERSION`.
3. `init(opts)` runs, the initial view renders, and the first
   snapshot is sent.
4. `window_config(model)` runs for each window node in the tree. Its
   return value is merged with the node's own props, with node props
   winning. The combined hash is sent as an `open` window op.
5. Subscriptions declared by `subscribe(model)` are synchronised
   against the renderer.

On a renderer restart, the runtime repeats steps 2, 3 (as a fresh
snapshot from the preserved model), 4, and 5. The app's model is
preserved across restarts.

## Renderer subprocess environment

`Plushie::RendererEnv` builds a filtered environment for the renderer
subprocess. By default, spawned children inherit the parent's full
environment, which can leak secrets (API keys, database credentials,
tokens) to the renderer. `RendererEnv` passes only what the renderer
actually needs: display server variables (`DISPLAY`, `WAYLAND_DISPLAY`,
`XDG_*`), GPU and Vulkan (`VK_*`, `MESA_*`, `LIBGL_*`, `GALLIUM_*`,
`WGPU_BACKEND`), fonts (`FONTCONFIG_*`), locale (`LANG`, `LANGUAGE`,
`LC_*`), accessibility (`AT_SPI_*`, `NO_AT_BRIDGE`), and Rust
diagnostics (`RUST_LOG`, `RUST_BACKTRACE`). Any variable prefixed with
`PLUSHIE_` passes through as a catch-all for renderer debug toggles.

`RUST_LOG` is always set from the `log_level:` runtime option
(overriding any inherited value), and `RUST_BACKTRACE` defaults to
`1` when the parent did not set it.

## Test configuration

The test backend is chosen in this order: `PLUSHIE_TEST_BACKEND` env
var, `Plushie.configuration.test_backend`, then the default of
`:mock`. Backend names match the other SDKs:

- `:mock`, pure protocol loop with no rendering (fastest, default)
- `:headless`, software rendering without a display server
- `:windowed`, real iced windows (needs a display server or Xvfb)

```bash
bundle exec rake test                              # :mock
PLUSHIE_TEST_BACKEND=headless bundle exec rake test
PLUSHIE_TEST_BACKEND=windowed bundle exec rake test
```

All three backends go through the same `Plushie::Test::SessionPool`
and share a renderer process across tests. See the testing guide for
assertion helpers and fixture patterns.

## See also

- [Versioning reference](versioning.md), how the pinned
  `PLUSHIE_RUST_VERSION` maps to the renderer and `cargo-plushie`
- [Commands reference](commands.md), the `Plushie::Command` and
  `Plushie::Effect` surfaces returned from `update`
- [Subscriptions reference](subscriptions.md), the `subscribe`
  callback and the three-level event-rate hierarchy
- [Built-in Widgets reference](built-in-widgets.md), the `window`
  widget and its per-window props
