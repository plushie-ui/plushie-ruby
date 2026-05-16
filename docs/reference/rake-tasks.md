# Rake Tasks

Plushie ships a set of Rake tasks for building, downloading, running,
inspecting, and scripting Plushie applications. The task definitions
live in `lib/plushie/rake.rb` and are wired into your project's
`Rakefile` with a single require:

```ruby
# Rakefile
require "plushie/rake"
```

Once loaded, every task lives under the `plushie:` namespace and is
invoked with `rake plushie:<task>`.

| Task | Purpose |
|---|---|
| [`plushie:download`](#plushiedownload) | Download a precompiled renderer binary or WASM bundle |
| [`plushie:build`](#plushiebuild) | Build the renderer from Rust source |
| [`plushie:clean`](#plushieclean) | Remove build artifacts |
| [`plushie:run`](#plushierun) | Run a Plushie app |
| [`plushie:connect`](#plushieconnect) | Run a Plushie app over stdio transport |
| [`plushie:package`](#plushiepackage) | Build a standalone package payload and manifest |
| [`plushie:inspect`](#plushieinspect) | Print the initial UI tree as JSON |
| [`plushie:script`](#plushiescript) | Run `.plushie` automation scripts |
| [`plushie:replay`](#plushiereplay) | Replay a `.plushie` script with real windows |
| [`plushie:preflight`](#plushiepreflight) | Run all CI checks locally |

## Shell quoting

Rake passes positional arguments in square brackets. Both bash and
zsh treat unquoted `[` and `]` as glob metacharacters, so always
quote the full invocation when you pass arguments:

```bash
rake 'plushie:download[force]'
rake 'plushie:build[release]'
rake 'plushie:run[Counter,dev]'
```

Examples below assume the surrounding single quotes.

## plushie:download

Downloads the precompiled native tool set (and/or WASM bundle) from
GitHub releases. This is the fastest way to get a working renderer.
The release assets are platform-specific (OS plus architecture) and
version-matched to the SDK via `Plushie::PLUSHIE_RUST_VERSION`.

```bash
rake plushie:download           # download anything that is missing
rake 'plushie:download[force]'  # re-download even if the files are present
```

### Positional argument

| Position | Value | Description |
|---|---|---|
| `arg1` | `force` | Re-download even when the file already exists |

Any value other than the literal string `force` is treated as the
default "download if missing" behaviour.

### Configuration inputs

The task reads `Plushie.configuration` (and a few environment
variables) to decide what to download and where to put it:

| Input | Source | Effect |
|---|---|---|
| `artifacts` | `Plushie.configuration.artifacts` | Which artifacts to install. Default: `[:bin]`. Set to `[:bin, :wasm]` to also fetch the WASM renderer |
| `bin_file` | `PLUSHIE_BIN_FILE` or `Plushie.configuration.bin_file` | Override destination path for the native binary |
| `wasm_dir` | `PLUSHIE_WASM_DIR` or `Plushie.configuration.wasm_dir` | Override destination directory for the WASM bundle |

Default destinations:

- Native tool set: `bin/plushie`, `bin/plushie-renderer`, and
  `bin/plushie-launcher` (with `.exe` on Windows). `bin/plushie` owns
  renderer and launcher sync.
- WASM bundle: `_build/plushie-renderer/wasm/` (contains
  `plushie_renderer_wasm.js` and `plushie_renderer_wasm_bg.wasm`)

### Checksum verification

Every download is verified against a `.sha256` sidecar fetched from
the same GitHub release. On mismatch, the downloaded file is deleted
and the task raises. There is no flag to skip verification, since the
binary runs as a child process of your application.

### Release mirrors

By default downloads come from GitHub releases. Set
`PLUSHIE_RELEASE_BASE_URL` to verify the same flow against another
release mirror. The mirror must expose assets as
`BASE/vVERSION/ARTIFACT` with checksum sidecars at
`BASE/vVERSION/ARTIFACT.sha256`.

Remote mirrors must use HTTPS. `file://` mirrors and loopback HTTP are
for local release verification before assets are uploaded.

## plushie:build

Builds the renderer binary from Rust source by delegating to the
`cargo-plushie` Cargo subcommand.

```bash
rake plushie:build               # debug build
rake 'plushie:build[release]'    # optimised build
rake 'plushie:build[update]'     # force a clean regen of the virtual manifest
rake 'plushie:build[release,update]'
```

Most apps use `plushie:download` for a precompiled binary and never
build from source. Building is required when you have
[native widgets](custom-widgets.md) (Rust-backed custom rendering) or
want to work against a local `plushie-rust` checkout.

### Positional arguments

| Position | Value | Description |
|---|---|---|
| `arg1` / `arg2` | `release` | Build with optimisations |
| `arg1` / `arg2` | `update` | Currently accepted for forward compatibility; cargo-plushie owns incremental workspace regeneration |

Both flags may appear in either slot, in any order.

### What it generates

The task writes a small virtual app crate that `cargo-plushie` reads
via `cargo metadata`:

- `_build/plushie-renderer-spec/Cargo.toml` - minimal manifest
  listing each configured native widget crate as a path dependency
  and carrying `[package.metadata.plushie]` with the binary name.
- `_build/plushie-renderer-spec/src/lib.rs` - empty placeholder so
  the manifest parses.

`cargo-plushie` produces the real renderer workspace under
`_build/plushie-renderer-spec/target/plushie-renderer/`. On success,
the compiled binary is copied to `bin/`, where the
renderer discovery chain will find it.

### cargo-plushie resolution

The task's resolver (`Plushie::CargoPlushie.resolve`) decides how to
invoke `cargo-plushie`:

1. **`PLUSHIE_RUST_SOURCE_PATH` set** (or
   `Plushie.configuration.source_path`): runs `cargo run -p
   cargo-plushie --release --quiet -- ...` against the checkout.
   Always works during local plushie-rust development.
2. **`cargo-plushie` on `PATH` at the matching version**: used
   directly. The pinned version is `Plushie::PLUSHIE_RUST_VERSION`.
3. **Missing or mismatched**: the task raises with an install hint,
   no auto-install.

See the [Versioning reference](versioning.md) for the relationship
between the gem version, `PLUSHIE_RUST_VERSION`, and `cargo-plushie`.

### Native widget discovery

Native widgets are listed explicitly:

```ruby
Plushie.configure do |config|
  config.widgets = [MyGauge, MyChart]
  config.build_name = "my-dashboard-plushie"
end
```

Or via the `PLUSHIE_WIDGETS` environment variable (comma-separated
class names) for CI. Non-native entries are skipped with a warning.

Each widget crate must declare `[package.metadata.plushie.widget]`
with `type_name` and `constructor` keys in its own `Cargo.toml`. The
task checks for these keys up front; missing metadata raises with a
message naming the widget class.

### Local source versus crates.io

By default, Rust dependencies come from crates.io at
`PLUSHIE_RUST_VERSION`. To build against a local plushie-rust
checkout:

```bash
git clone https://github.com/plushie-ui/plushie-rust ../plushie-rust
PLUSHIE_RUST_SOURCE_PATH=../plushie-rust rake 'plushie:build[release]'
```

Or permanently via configuration:

```ruby
Plushie.configure do |config|
  config.source_path = "../plushie-rust"
end
```

With a source path set, `cargo-plushie` emits `[patch.crates-io]`
redirecting every plushie crate to the local checkout, which is
essential when modifying the renderer alongside the SDK.

### Requirements

- Rust toolchain with `cargo` on `PATH`. The task shells out to
  `cargo --version` first and aborts with `"cargo not found. Install
  Rust via https://rustup.rs"` when absent.
- `cargo-plushie` at the matching `PLUSHIE_RUST_VERSION`, or
  `PLUSHIE_RUST_SOURCE_PATH` set to a local plushie-rust checkout.

## plushie:clean

Removes build artifacts so the next `plushie:build` starts clean.

```bash
rake plushie:clean
```

Deletes:

- `_build/plushie/` (installed binaries)
- `_build/plushie-renderer-spec/` (virtual manifest and cargo target
  directory)

Prints "Nothing to clean" when both directories are already gone.

## plushie:package

Builds a standalone payload archive and `plushie-package.toml`
for the shared Rust package launcher. Ruby-specific work stays in
the SDK: copying the app, copying a conservative Ruby runtime,
installing runtime gems, adding the renderer to the payload, hashing
the archive, and writing SDK/protocol metadata into the manifest.
The helper also asks `cargo-plushie` to materialize the default
launcher icons under `payload/assets` before archiving.

```bash
rake 'plushie:package[dev.example.notes,Notes,0.1.0]'
```

The output defaults to `dist/payload.tar.zst` and
`dist/plushie-package.toml`. Build the outer launcher with:

```bash
bin/plushie package portable --manifest dist/plushie-package.toml
```

Set `PLUSHIE_PACKAGE_PORTABLE=true` to run that final command from
the Rake task after the manifest is written. Set
`PLUSHIE_PACKAGE_PORTABLE_OUT` to pass `--out PATH`, and set
`PLUSHIE_PACKAGE_STRICT_TOOLS=true` to pass `--strict-tools`.

Use `--strict-tools` with the Rake task, the Ruby package CLI, or the
Rust package commands when native packaging tools must be present. The
same gate can be checked before launcher creation:

```bash
bin/plushie package check --manifest dist/plushie-package.toml --strict-tools
```

### Configuration inputs

| Input | Default | Effect |
|---|---|---|
| `PLUSHIE_PACKAGE_APP_ID` | required | Package app identifier |
| `PLUSHIE_PACKAGE_APP_NAME` | unset | Optional display name written to the manifest |
| `PLUSHIE_PACKAGE_APP_VERSION` | `0.1.0` | App version written to the manifest |
| `PLUSHIE_PACKAGE_PROJECT_DIR` | current directory | App directory containing `lib/`, `bin/connect`, and `Gemfile` |
| `PLUSHIE_PACKAGE_OUTPUT` | `dist` | Directory for payload and manifest output |
| `PLUSHIE_PACKAGE_PORTABLE` | `false` | Run `bin/plushie package portable` after writing the manifest |
| `PLUSHIE_PACKAGE_PORTABLE_OUT` | unset | Output path forwarded as `--out` for portable launcher creation |
| `PLUSHIE_PACKAGE_STRICT_TOOLS` | `false` | Forward `--strict-tools` to the portable launcher command |
| `PLUSHIE_PACKAGE_TARGET` | current Ruby host | Package target override such as `linux-x86_64` |
| `PLUSHIE_PACKAGE_RENDERER_PATH` | auto-resolve | Existing renderer binary to copy into the payload |
| `PLUSHIE_PACKAGE_RENDERER_KIND` | `stock` | Renderer kind recorded in `[renderer]` |
| `PLUSHIE_PACKAGE_ICON_PATH` | default Plushie icon | App icon copied into the payload and recorded in `[platform].icon` |
| `PLUSHIE_PACKAGE_ENTRYPOINT` | `bin/connect` | App entrypoint used as the host command |
| `PLUSHIE_PACKAGE_BUNDLE_WITHOUT` | `development test` | Bundler groups excluded from the packaged app |
| `PLUSHIE_RUBY_DIR` | unset | Local SDK checkout to vendor into the packaged app |
| `PLUSHIE_RUBY_PROVIDER` | `local` | Ruby runtime provider: `local`, `path`, or `mise` |
| `PLUSHIE_RUBY_ROOT` | unset | Ruby runtime root for the `path` provider |
| `PLUSHIE_RUBY_VERSION` | unset | Ruby version passed to `mise where ruby@VERSION` for the `mise` provider |

The Rake task accepts `app_id`, `app_name`, and `app_version` as
positional task arguments. Environment variables remain available for
the less common inputs and for CI jobs that already use them.

Renderer resolution checks `PLUSHIE_PACKAGE_RENDERER_PATH`,
`PLUSHIE_BINARY_PATH`, `PLUSHIE_RUST_SOURCE_PATH`, and the managed
SDK download path. When `PLUSHIE_PACKAGE_RENDERER_KIND` is `custom`,
set `PLUSHIE_PACKAGE_RENDERER_PATH` or `PLUSHIE_BINARY_PATH` to the
custom renderer binary. When `PLUSHIE_RUST_SOURCE_PATH` is set for a
stock renderer, the package helper runs the managed native-tool sync
from that checkout so `bin/plushie`, `bin/plushie-renderer`, and
`bin/plushie-launcher` are prepared together.
Default icon generation uses `cargo run -p cargo-plushie --bin plushie
--release -- default-icons` from a local plushie-rust checkout when
`PLUSHIE_RUST_SOURCE_PATH` is set. Otherwise it uses
`bin/plushie default-icons`.

### Ruby runtime

By default, the package helper copies the active Ruby installation
reported by `RbConfig::CONFIG["prefix"]`. Runtime roots are OS and
architecture specific, so release builds should run on matching target
runners until cross-target runtime downloads are proven.

Runtime provider options:

- `local` copies the Ruby runtime currently running the package helper.
- `path` copies the extracted runtime root named by `PLUSHIE_RUBY_ROOT`.
- `mise` runs `mise where ruby@VERSION` when `PLUSHIE_RUBY_VERSION` is
  set, or `mise where ruby` otherwise, then copies that extracted root.

## plushie:run

Starts a Plushie application against a local renderer binary.

```bash
rake 'plushie:run[Counter]'
rake 'plushie:run[Counter,dev]'
rake 'plushie:run[Counter,json]'
rake 'plushie:run[Counter,dev,json]'
```

The task instantiates the app class, resolves the renderer binary
(see [binary resolution](#binary-resolution)), starts the runtime,
and blocks until the app exits.

### Positional arguments

| Position | Value | Description |
|---|---|---|
| `app_class` | string | Constant name of your app class. Resolved with `Object.const_get` |
| `opt1` / `opt2` | `dev` | Enable dev-mode live reload |
| `opt1` / `opt2` | `json` | Switch the wire protocol from MessagePack to newline-delimited JSON |

`app_class` is required; the task aborts with a usage message when
omitted.

### Dev mode

With `dev`, the runtime watches your source files for changes and
re-renders the UI on save. The app's model is preserved across
reloads; only the view tree (and any state the renderer owns) is
replaced. See `lib/plushie/dev_server.rb` for the watcher
implementation.

### JSON wire protocol

With `json`, the wire format switches from MessagePack to
newline-delimited JSON. Each message is a complete JSON object on
its own line, easy to inspect with
[`jq`](https://jqlang.github.io/jq/) or redirect to a file:

```bash
rake 'plushie:run[Counter,json]' 2>protocol.log
```

For renderer-side tracing, set `RUST_LOG`:

```bash
RUST_LOG=plushie=debug rake 'plushie:run[Counter,json]'
```

See the [Wire Protocol reference](wire-protocol.md) for the message
format.

## plushie:connect

Runs a Plushie application from a standalone entry point. When
`PLUSHIE_SOCKET` is present, it connects to that renderer. Otherwise it
starts the renderer through normal binary resolution, including
`PLUSHIE_BINARY_PATH`.

```bash
rake 'plushie:connect[Counter]'
```

### Positional argument

| Position | Value | Description |
|---|---|---|
| `app_class` | string | Constant name of the app class |

`app_class` is required; the task aborts with a usage message when
omitted.

The typical pattern is to run the renderer with structured exec args
that launches this task:

```bash
plushie \
  --listen \
  --exec-bin bundle \
  --exec-arg exec \
  --exec-arg rake \
  --exec-arg 'plushie:connect[Counter]'
```

All log output is routed off of stdout so the protocol channel
stays clean.

## plushie:inspect

Prints a Plushie app's initial UI tree as pretty-printed JSON,
without starting a renderer.

```bash
rake 'plushie:inspect[Counter]'
```

The task calls `init({})`, renders the view, normalizes the tree
(applying scoped IDs and widget expansion), converts the root node
to its wire shape, and prints it via `JSON.pretty_generate`. When
`init` returns `[model, command]`, the command is ignored and the
model is used to render.

Useful for:

- Debugging layout structure and widget nesting
- Verifying prop values without opening a window
- Quick inspection in CI or scripts
- Checking that `view` does not crash with a fresh model

No renderer binary is needed; everything runs in Ruby.

## plushie:script

Runs [`.plushie` automation scripts](testing.md) headlessly against
the mock backend.

```bash
rake plushie:script                                   # all scripts under test/scripts/
rake 'plushie:script[test/scripts/save_flow.plushie]' # a specific script
```

### Positional argument

| Position | Value | Description |
|---|---|---|
| `path` | string | Path to a single `.plushie` script. Omit to discover every `.plushie` file under `test/scripts/` |

Each script starts a fresh app session against the mock backend,
executes its instructions, and reports PASS or FAIL. Empty scripts
are reported as SKIP. Scripts whose files do not exist are reported
as FAIL.

The task prints a summary line of the form `N passed, M failed` and
exits with status 1 if any script failed. When no scripts are found,
it prints `No .plushie scripts found` and exits 0.

## plushie:replay

Replays a single `.plushie` script with the windowed backend. Real
windows appear on screen, GPU rendering is active, and `wait`
directives in the script are respected, so the script plays in real
time.

```bash
rake 'plushie:replay[test/scripts/demo.plushie]'
```

### Positional argument

| Position | Value | Description |
|---|---|---|
| `path` | string | Path to the `.plushie` script to replay |

`path` is required; the task aborts with a usage message when
omitted and exits with status 1 if the file does not exist.

Useful for:

- Visually verifying that an automation script does what you expect
- Creating demo recordings or walkthroughs
- Debugging interaction sequences that behave differently under real
  rendering (timing, animation, focus)

Replay forces the windowed backend regardless of
`PLUSHIE_TEST_BACKEND`; on a headless host, run it behind a display
server (for example a headless `weston` socket). See the
[Testing reference](testing.md).

## plushie:preflight

Runs the full CI check suite locally, stopping at the first failure.

```bash
rake plushie:preflight
```

Steps, in order:

1. `bundle exec rake standard` - [Standard Ruby](https://github.com/standardrb/standard) linter
2. `bundle exec rake test` - Minitest suite against the mock backend
3. `PLUSHIE_TEST_BACKEND=headless bundle exec rake test` - the same
   suite against the headless backend, skipped with a warning if the
   renderer binary is not resolvable
4. `bundle exec steep check` - Steep type checker against the RBS
   signatures
5. `bundle exec yard doc` - YARD documentation generation

Each step streams its output directly to the terminal. If every step
passes, the task prints `All checks passed.` at the end.

If preflight passes locally, CI will pass. Run it before pushing.

## Binary resolution

Several tasks need the renderer binary. `Plushie::Binary.path!`
resolves it in priority order:

1. `PLUSHIE_BINARY_PATH` environment variable. Raises if set but the
   file is missing.
2. `Plushie.configuration.binary_path`. Raises if set but the file
   is missing.
3. Custom widget build under `_build/plushie/custom/target/` after
   `rake plushie:build`.
4. Downloaded binary in `bin/` after
   `rake plushie:download`.

Steps 1 and 2 are explicit; steps 3 and 4 stay within the current
project. See `Plushie::Binary` for the full resolution logic.

## Environment variables

| Variable | Effect |
|---|---|
| `PLUSHIE_BINARY_PATH` | Explicit path to the renderer binary. Raises if set but missing |
| `PLUSHIE_RUST_SOURCE_PATH` | Path to a local plushie-rust checkout. Switches builds to source mode and pins `cargo-plushie` to the checkout |
| `PLUSHIE_BIN_FILE` | Override destination path for the native binary in `plushie:download` and `plushie:build` |
| `PLUSHIE_WASM_DIR` | Override destination directory for the WASM bundle in `plushie:download` |
| `PLUSHIE_WIDGETS` | Comma-separated list of native widget class names for `plushie:build`. Alias: `PLUSHIE_EXTENSIONS` |
| `PLUSHIE_BUILD_NAME` | Override the Cargo binary target name for custom builds |
| `PLUSHIE_TEST_BACKEND` | Selects the test backend: `mock` (default), `headless`, or `windowed` |
| `RUST_LOG` | Passed through to the renderer for tracing-based logging |

## See also

- [Configuration reference](configuration.md) - `Plushie.configure`
  fields, environment variables, and transport modes
- [Versioning reference](versioning.md) - the relationship between
  the gem version, `PLUSHIE_RUST_VERSION`, and the renderer binary
- [Testing reference](testing.md) - test backends, `.plushie`
  scripts, and the full test helper API
