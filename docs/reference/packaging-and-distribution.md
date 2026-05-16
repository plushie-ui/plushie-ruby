# Packaging and Distribution

`rake plushie:package` turns a Plushie app into a self-contained
artifact that ships with its own Ruby runtime, the app's bundled
gems, and a Plushie renderer. The output is either a portable
single-file executable or an OS-native installer (AppImage, `.dmg`,
`.msi`). The recipient does not need Ruby, Bundler, or anything else
installed.

When the artifact runs, the launcher extracts the payload, invokes
the bundled `ruby/bin/ruby` against `bin/start_host.rb`, and the app
starts its renderer from inside the payload. The flow is the same as
`rake plushie:run`, just running from an extracted directory instead
of your project.

| Section | Topic |
|---|---|
| [The packaging pipeline](#the-packaging-pipeline) | How the SDK, cargo-plushie, and the launcher hand off |
| [rake plushie:package](#rake-plushiepackage) | Task arguments, environment inputs, and what the task owns |
| [The payload](#the-payload) | What goes in `dist/payload/` |
| [Source layout](#source-layout) | What to commit and what to gitignore |
| [Renderer selection](#renderer-selection) | Stock versus custom |
| [Bundled assets](#bundled-assets) | Icons, fonts, and other payload files |
| [The bundled Ruby runtime](#the-bundled-ruby-runtime) | Runtime providers and Bundler deployment |
| [The managed tool set](#the-managed-tool-set) | `bin/plushie`, renderer, launcher |
| [The partial manifest](#the-partial-manifest) | TOML the SDK writes |
| [Package config](#package-config) | `plushie-package.config.toml` schema |
| [Forwarded environment](#forwarded-environment) | Host process environment policy |
| [Building artifacts](#building-artifacts) | Portable executable and OS installers |
| [Distribution](#distribution) | Release asset layout |
| [Continuous integration](#continuous-integration) | GitHub Actions workflow |
| [Signing](#signing) | Developer-driven signing hooks |
| [Updates](#updates) | `[updates]` schema |
| [Host-first versus renderer-parent](#host-first-versus-renderer-parent) | Default launch model and the alternative |

## The packaging pipeline

A packaged app moves through three stages:

1. **SDK build.** `rake plushie:package` copies the app, a Ruby
   runtime, and a renderer into `dist/payload/`, runs
   `bundle install --deployment` style steps to vendor the app's
   gems, writes a `bin/start_host` wrapper, and emits a partial
   `dist/plushie-package.toml` carrying SDK identity, version pins,
   target triple, and the renderer descriptor.
2. **Manifest assembly.** `rake plushie:package` then shells out to
   `bin/plushie package assemble`. cargo-plushie validates the
   payload, reads `plushie-package.config.toml` for `[start]`
   defaults and `[platform]` metadata, materializes the icon,
   archives the payload, computes its SHA-256 and size, and fills in
   the rest of `plushie-package.toml`.
3. **Artifact build.** `bin/plushie package portable` produces a
   self-extracting single-file executable. `bin/plushie package bundle`
   produces OS-native installers via
   [cargo-packager](https://github.com/crabnebula-dev/cargo-packager).
   Both consume the same completed manifest.

Stage 1 is Ruby-specific. Stages 2 and 3 are language-agnostic and
shared across every Plushie SDK; the same `bin/plushie` tool that
assembles a Ruby payload assembles an Elixir or Python payload.

## rake plushie:package

Stage 1 of the pipeline. The task copies the project, copies a Ruby
runtime, installs runtime gems with Bundler, places the renderer,
writes the partial manifest, and shells to
`bin/plushie package assemble` to complete it.

```bash
bundle exec rake 'plushie:package[dev.example.notes,Notes,0.1.0]'
```

Rake's positional argument syntax is square brackets. Quote the full
invocation so the shell does not glob-expand the brackets.

### Positional arguments

| Position | Description |
|---|---|
| `app_id` | Package app identifier. Required. |
| `app_name` | Display app name. Used by cargo-plushie for OS-native bundles. |
| `app_version` | App version written to the manifest. Defaults to `0.1.0`. |

`app_id` is a reverse-DNS identifier in the
`namespace.[subnamespace.]app` form (`dev.example.notes`,
`com.acme.invoice`). cargo-plushie validates the format during
assembly.

### Environment inputs

Less common inputs are read from environment variables so CI jobs
can drive them without rewriting the task call:

| Variable | Default | Effect |
|---|---|---|
| `PLUSHIE_PACKAGE_APP_ID` | required if positional missing | Package app identifier |
| `PLUSHIE_PACKAGE_APP_NAME` | unset | Display name written to the manifest |
| `PLUSHIE_PACKAGE_APP_VERSION` | `0.1.0` | App version written to the manifest |
| `PLUSHIE_PACKAGE_PROJECT_DIR` | current directory | App directory containing `lib/`, `bin/start_host`, and `Gemfile` |
| `PLUSHIE_PACKAGE_OUTPUT` | `dist` | Directory for payload and manifest output |
| `PLUSHIE_PACKAGE_TARGET` | current Ruby host | Package target override such as `linux-x86_64` |
| `PLUSHIE_PACKAGE_RENDERER_PATH` | auto-resolve | Existing renderer binary to copy into the payload |
| `PLUSHIE_PACKAGE_RENDERER_KIND` | `stock` | Renderer kind recorded in `[renderer]` |
| `PLUSHIE_PACKAGE_CONFIG` | unset | Path to `plushie-package.config.toml`. Forwarded to the assembler, which reads platform metadata from it |
| `PLUSHIE_PACKAGE_ENTRYPOINT` | `bin/start_host` | App entrypoint script |
| `PLUSHIE_PACKAGE_BUNDLE_WITHOUT` | `development test` | Bundler groups excluded from the packaged app |
| `PLUSHIE_RUBY_DIR` | unset | Local SDK checkout to vendor into the packaged app |
| `PLUSHIE_RUBY_PROVIDER` | `local` | Ruby runtime provider: `local`, `path`, or `mise` |
| `PLUSHIE_RUBY_ROOT` | unset | Ruby runtime root for the `path` provider |
| `PLUSHIE_RUBY_VERSION` | unset | Ruby version passed to `mise where ruby@VERSION` for the `mise` provider |

The output directory is rebuilt from scratch on every run. Anything
under `dist/` from a previous run is removed before the new payload
is assembled.

### Writing the package config template

`Plushie::Package` exposes a `--write-package-config` flag through
its CLI entry point, useful for scripted setup:

```bash
ruby -rplushie/package -e 'Plushie::Package.run_cli(ARGV)' -- \
  --write-package-config
```

This writes `plushie-package.config.toml` next to the current
directory and exits without packaging anything.

## The payload

`dist/payload/` is the directory that gets archived into the artifact:

```
dist/
  plushie-package.toml           # manifest (partial then completed)
  payload/
    bin/
      start_host                 # POSIX entry script (shebang wrapper)
      start_host.cmd             # Windows entry script (windows-* targets)
      start_host.rb              # the app's entrypoint, copied verbatim
      plushie-renderer           # payload-local renderer copy
    lib/                         # app source tree, copied from project lib/
    Gemfile                      # copy of the project Gemfile (or local-SDK Gemfile)
    Gemfile.lock                 # Bundler lockfile from the package install
    vendor/
      bundle/                    # vendored gems from bundle install
      plushie-ruby/              # optional: local SDK checkout when PLUSHIE_RUBY_DIR is set
    .bundle/
      config                     # local Bundler config (path, without groups)
    ruby/                        # bundled Ruby runtime (bin/, lib/, share/, ...)
    assets/                      # icon and other files from package_assets/
                                 #   (see Bundled assets below)
```

On POSIX targets, `bin/start_host` is a small shell wrapper that
`exec`s `ruby/bin/ruby` against `bin/start_host.rb`. On `windows-*`
targets, `bin/start_host.cmd` does the same with `ruby/bin/ruby.exe`.
The shared package launcher runs whichever wrapper the manifest
records with `PLUSHIE_BINARY_PATH` set to the payload-local renderer,
and `bin/start_host.rb` starts that renderer through the normal binary
resolution path. The packaged app never reaches out to the system
`PATH` or a download cache; everything it needs is inside the
extracted payload.

The app's `bin/start_host` script in your project source ends up at
`bin/start_host.rb` inside the payload. It should `require "plushie"`
and call `Plushie.connect(YourApp)` (or `Plushie.run`); the wrapper
takes care of locating the right Ruby and forwarding arguments.

## Source layout

Packaging adds project-owned files that belong in version control and
generated files that do not. Knowing which is which avoids accidentally
committing platform-specific binaries or losing project-owned config.

| Path | What it is | Commit or gitignore |
|---|---|---|
| `plushie-package.config.toml` | Package config: start command, platform metadata, asset directory override. Like the gemspec for packaging. | Commit. |
| `package_assets/` | Project-owned icon, fonts, and other files copied verbatim into the payload. | Commit. |
| `bin/start_host` | App entrypoint script. Required by the packager. | Commit. |
| `Gemfile`, `Gemfile.lock` | Bundler manifest and resolved lockfile. The packager re-installs against these inside the payload. | Commit. |
| `bin/plushie`, `bin/plushie-renderer`, `bin/plushie-launcher` | Plushie tool set installed by `rake plushie:download`. Platform-specific binaries. | Gitignore. |
| `dist/` | Package output: payload directory and manifest. Rebuilt by every `rake plushie:package` run. | Gitignore. |
| `target/plushie/` | Portable and bundle artifacts produced by `bin/plushie package portable` / `bundle`. | Gitignore. |
| `_build/` | Build artifacts for `rake plushie:build` (custom renderer). | Gitignore. |

A minimum `.gitignore` for a packaging-enabled project looks like:

```
/_build/
/bin/plushie
/bin/plushie-renderer
/bin/plushie-launcher
/bin/*.exe
/dist/
/target/
/vendor/bundle/
```

`rake plushie:download`, `rake plushie:package`, and
`bin/plushie package portable` each check whether their output path is
gitignored when run inside a git repository. If it is not, they print a
one-paragraph warning naming the directory and the line to add. The
command still succeeds; the warning is just a nudge.

## Renderer selection

The task picks a renderer based on whether your project declares
[native widgets](custom-widgets.md) (Rust-backed widgets that ship
their own crate):

- **No native widgets.** A stock renderer is bundled. By default, it
  comes from the managed tool set installed by `rake plushie:download`.
- **Native widgets present.** Set `PLUSHIE_PACKAGE_RENDERER_KIND=custom`
  and point `PLUSHIE_PACKAGE_RENDERER_PATH` (or `PLUSHIE_BINARY_PATH`)
  at a custom renderer built by `rake plushie:build`.

Requesting `stock` packaging for an app with native widgets fails
fast, because a stock renderer cannot include those widget crates.

`PLUSHIE_PACKAGE_RENDERER_PATH` packages a specific binary regardless
of how it was produced. The payload-local path is always
`bin/plushie-renderer` (with `.exe` on `windows-*` targets); the
`[renderer].kind` field in the manifest records whether the binary is
`stock` or `custom`.

## Bundled assets

A packaged app needs two kinds of files beyond the gem itself: the
icon and other OS-bundle metadata that cargo-plushie reads from the
manifest, and runtime assets that your app loads at startup (fonts,
images, data files). Each has a different home.

### App-loaded assets (gem-relative paths)

Anything your app reads at runtime should resolve through gem-relative
or project-relative paths. The same code works packaged or unpackaged
because the payload preserves the project's `lib/` layout:

```ruby
module Notes
  ROOT = File.expand_path("..", __dir__)

  def self.font_path
    File.join(ROOT, "assets", "fonts", "inter.ttf")
  end

  def self.icon_path
    File.join(ROOT, "assets", "window-icon.png")
  end
end
```

For a published gem, swap `File.expand_path("..", __dir__)` for
`Gem.loaded_specs.fetch("notes").full_gem_path` so the path resolves
to the gem's install location. Reference these paths from
`settings.fonts`, `Plushie::Command::Image`, or any widget that takes
a file path. If it works in `rake plushie:run`, it works packaged.

### Package-level assets (package_assets/)

Files that need to live inside the payload at a known location, such
as the OS bundle icon referenced from `[platform].icon`, go in a
`package_assets/` directory next to `plushie-package.config.toml`.
cargo-plushie copies the contents verbatim into the payload root
during `bin/plushie package assemble`:

```
notes/
├── Gemfile
├── plushie-package.config.toml
└── package_assets/
    ├── icon.png                # ends up at payload/icon.png
    └── fonts/
        └── extra.ttf           # ends up at payload/fonts/extra.ttf
```

The convention is zero-config: if `package_assets/` exists, it is
used. To use a different directory name, set `[assets].dir` in the
package config:

```toml
[assets]
dir = "branding"
```

Asset files overwrite SDK-generated payload files when the names
collide, so a `package_assets/bin/start_host` would replace the
generated entry script. Use this for overrides, not by accident; the
default layout has no overlap.

### Icon

cargo-plushie looks for an icon at the path named in `[platform].icon`
inside the payload. If no path is set and a file already exists at
`assets/default-app-icon-512.png`, that path is recorded. If nothing
exists at either location, cargo-plushie writes the built-in default
icon to `assets/default-app-icon-512.png` and records that path.

**Format:** PNG with RGBA alpha channel for transparency.

**Dimensions:** square aspect ratio, 512x512 minimum. cargo-packager
scales this single source down for `.ico` (16/32/48/64/128/256) and
up or down for `.icns` (16/32/64/128/256/512/1024). Provide 1024x1024
or larger if the same icon will be used for retina displays or
high-DPI Windows installers.

To use a custom icon, put a PNG in `package_assets/` and reference it
from `[platform].icon`:

```toml
[platform]
icon = "icon.png"               # payload-relative; resolves to payload/icon.png
                                # after package_assets/icon.png is copied
```

The schema accepts a single icon path. Multi-size sources and
per-platform `.icns`/`.ico` overrides are not yet supported.

## The bundled Ruby runtime

The packager copies a full Ruby runtime root (the directory tree
under `RbConfig::CONFIG["prefix"]`: `bin/ruby`, `lib/ruby/`,
`share/`, and so on) into `payload/ruby/`. Three providers decide
which runtime is copied:

| Provider | How it picks the runtime |
|---|---|
| `local` (default) | Copies the Ruby installation currently running the package helper, via `RbConfig::CONFIG["prefix"]`. |
| `path` | Copies the extracted runtime root named by `PLUSHIE_RUBY_ROOT`. Use this when CI installs a runtime and you want to point at the resolved path. |
| `mise` | Runs `mise where ruby@VERSION` when `PLUSHIE_RUBY_VERSION` is set, or `mise where ruby` otherwise, then copies that root. |

Runtime roots are OS and architecture specific, so release builds
should run on a runner that matches the target until cross-target
runtime downloads are proven. Cross-target runtime bundling (building
a Linux runtime on macOS, for example) is not currently a supported
flow.

### Gem installation

After the runtime is copied, the packager configures Bundler against
the payload directory and runs `bundle install` with the payload's
own Ruby. The configuration sets:

- `path` to `vendor/bundle`, so gems install inside the payload.
- `without` to `PLUSHIE_PACKAGE_BUNDLE_WITHOUT` (defaults to
  `development test`), so dev-only and test-only groups are skipped.

The `bundle install` call runs through `Bundler.with_unbundled_env`
to keep the parent process's Bundler environment from leaking into
the payload install. The packaged app's Bundler config lives entirely
under `payload/.bundle/config` and resolves against `payload/Gemfile`.

### Vendoring a local SDK checkout

When `PLUSHIE_RUBY_DIR` points at a local plushie-ruby checkout, the
packager copies the checkout to `payload/vendor/plushie-ruby/` and
writes a one-line Gemfile that resolves `plushie` from that path:

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gem "plushie", path: "vendor/plushie-ruby"
```

The project's normal `Gemfile` is replaced for the install step. Use
this when packaging an app against an unreleased SDK build, for
example while bisecting a renderer regression.

## The managed tool set

`rake plushie:download` installs three executables under `bin/`:

| File | Role |
|---|---|
| `plushie` | Orchestration tool. Owns `tools sync`, `package assemble`, `package portable`, `package bundle`. |
| `plushie-renderer` | The renderer binary used at runtime. Resolved by `Plushie::Binary.path!`. |
| `plushie-launcher` | The shared launcher used by `package portable` to build the self-extracting artifact. |

The version of each file matches the `PLUSHIE_RUST_VERSION` pin in
the SDK. `rake plushie:download` fetches `plushie` first, then
invokes `bin/plushie tools sync --required-version VERSION` to fetch
the matching renderer and launcher.

`rake plushie:package` requires all three files. The renderer is
copied into the payload, `plushie` runs the assemble step, and
`plushie-launcher` is the substrate that `package portable` wraps
the payload with. The task raises early if any are missing and
prints a `rake plushie:download` hint.

The Windows variants of these files carry an `.exe` suffix. The
tool name (`plushie` versus `plushie.exe`) is platform-specific;
the role is the same.

## The partial manifest

`rake plushie:package` writes a TOML document with everything the SDK
knows: identity, versions, target, and the renderer descriptor. A
minimal partial manifest looks like:

```toml
schema_version = 1
app_id = "dev.example.notes"
app_version = "0.1.0"
target = "linux-x86_64"
host_sdk = "ruby"
host_sdk_version = "0.7.2"
plushie_rust_version = "0.7.0"
protocol_version = 1

[start]
command = ["bin/start_host"]

[renderer]
path = "bin/plushie-renderer"
kind = "stock"
```

`bin/plushie package assemble` reads this file plus the payload
directory and writes the completed manifest in place. The completed
manifest adds:

- A `[payload]` section with the archive hash, size, and compression
  format.
- `[start].working_dir` and `[start].forward_env` defaults from the
  package config.
- A `[platform]` block if one is set in the package config. The
  materialized icon path is recorded as `[platform].icon`; there is
  no separate `[icon]` table.

The split exists so that cargo-plushie owns the cross-SDK schema
once. Every Plushie SDK writes a partial manifest in this shape and
hands the rest to the same `package assemble` step.

## Package config

Optional defaults for the assemble step live in
`plushie-package.config.toml` at the project root. Generate a
template with the CLI entry point:

```bash
ruby -rplushie/package -e 'Plushie::Package.run_cli(ARGV)' -- \
  --write-package-config
```

The template includes the common fields, with the platform sections
commented out:

```toml
config_version = 1

[start]
command = ["bin/start_host"]

# [assets]
# # Project-relative directory copied verbatim into the payload root
# # during package assembly. When this section is absent, a directory
# # named `package_assets/` next to this config file is used by
# # convention if it exists.
# dir = "package_assets"

# [platform]
# publisher = "Your Name"
# copyright = "Copyright 2026 Your Name"
# category = "productivity"
# description = "Short app description"
# bundle_id = "com.example.app"

# [platform.macos]
# bundle_version = "1"

# [platform.windows]
# install_scope = "perUser"
```

`[start].command` is a structured argv; the first element is the
host entry script. When building for a `windows-*` target, the SDK
swaps `bin/start_host` for `bin/start_host.cmd` while writing the
partial manifest, so the assembler never sees the POSIX form. The
substitution happens during stage 1 (SDK build), not during the
assemble step.

`[start].forward_env` (added by the assembler when not set in the
config) is the list of environment variable **names** copied from
the parent process into the host process at launch time. Names only;
values are never logged or recorded. The defaults cover the variables
a typical Linux GUI app needs. Add entries when your app reads
additional environment, for example `RUST_LOG` during development.

The `[platform]` block populates OS-native bundle metadata. All
fields are optional. `bundle_id` defaults to `app_id`. The
`[platform.macos]` and `[platform.windows]` subtables carry
OS-specific fields and are also optional.

Set `PLUSHIE_PACKAGE_CONFIG` to point at a config file outside the
project root.

## Forwarded environment

The package launcher does not blanket-inherit the user's environment.
It builds the host process environment from two closed sources:

- The Plushie reserved namespace (`PLUSHIE_BINARY_PATH`,
  `PLUSHIE_PACKAGE_DIR`, `PLUSHIE_PACKAGE_READY_FILE`, plus a small
  set of internal coordination variables that the launcher sets
  itself).
- The names listed in `[start].forward_env`.

Variables outside both sets are dropped. This matches the
`Plushie::RendererEnv` allowlist that the SDK uses to bound the
renderer subprocess environment, and gives packaged apps a
predictable, narrow runtime environment regardless of where the
launcher is invoked from.

## Building artifacts

Once the manifest is complete, the same payload feeds two artifact
shapes.

### Portable single-file launcher

```bash
bin/plushie package portable --manifest dist/plushie-package.toml
```

Produces a self-extracting executable wrapping `plushie-launcher` and
the archived payload. Output lands under `target/plushie/package/`
by default; pass `--out PATH` to override. The artifact is content-
addressed by the payload hash, so two builds of the same inputs
produce a byte-identical executable.

The launcher extracts the payload to a per-user cache directory
keyed by the payload hash. Repeated runs of the same artifact reuse
the extraction.

### OS-native installers

```bash
bin/plushie package bundle --manifest dist/plushie-package.toml --format appimage
bin/plushie package bundle --manifest dist/plushie-package.toml --format dmg --format app
bin/plushie package bundle --manifest dist/plushie-package.toml --format nsis
```

`--format` is singular and repeatable: pass it once per cargo-packager
format. Delegates to [cargo-packager](https://github.com/crabnebula-dev/cargo-packager)
for `appimage` (Linux), `app` and `dmg` (macOS), and `nsis` and `wix`
(Windows). These are cargo-packager format identifiers, not file
extensions. Format availability depends on the runner: Apple formats
need a macOS runner, Windows formats need a Windows runner.

Both commands default to a strict-tools check: they verify that the
launcher, renderer, and `plushie` itself match the SDK-pinned
version. Pass `--lax-tools` to bypass the check; this is intended
for local experimentation and not for release builds.

## Distribution

Artifacts are version-named and signed with SHA-256 sidecars in the
same layout the SDK uses to fetch its own managed tools:

```
BASE/vVERSION/ARTIFACT
BASE/vVERSION/ARTIFACT.sha256
```

GitHub releases match this layout naturally. Other hosting works
the same way: any HTTPS endpoint that serves
`vVERSION/ARTIFACT` and `vVERSION/ARTIFACT.sha256` is usable.

For local release verification, point `PLUSHIE_RELEASE_BASE_URL` at
a `file://` directory or a loopback HTTP server before assets are
uploaded. The download flow accepts both schemes alongside the
default HTTPS.

## Continuous integration

The following GitHub Actions workflow builds a portable artifact per
target on a `v*` tag push and uploads everything to a GitHub release
with SHA-256 sidecars. Drop it in at `.github/workflows/release.yml`
and edit the marked lines for your app:

```yaml
name: Release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write          # for uploading release assets

jobs:
  package:
    name: Package (${{ matrix.target }})
    runs-on: ${{ matrix.runner }}
    strategy:
      fail-fast: false
      matrix:
        include:
          - target: linux-x86_64
            runner: ubuntu-latest
          - target: darwin-x86_64
            runner: macos-13
          - target: darwin-aarch64
            runner: macos-14
          - target: windows-x86_64
            runner: windows-latest
    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true

      - name: Install Plushie tools
        run: bundle exec rake plushie:download

      - name: Build the package payload
        # EDIT: replace dev.example.notes and Notes below
        run: |
          bundle exec rake 'plushie:package[dev.example.notes,Notes,${{ github.ref_name }}]'

      - name: Build the portable artifact
        run: bin/plushie package portable --manifest dist/plushie-package.toml

      - name: Compute SHA-256 sidecar
        shell: bash
        run: |
          cd target/plushie/package
          for f in *; do
            if [ -f "$f" ] && [[ "$f" != *.sha256 ]]; then
              shasum -a 256 "$f" | awk '{print $1}' > "$f.sha256"
            fi
          done

      - name: Upload to release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            target/plushie/package/*
          generate_release_notes: true
```

The workflow runs four parallel jobs, one per supported target. Each
checks out the code, installs Ruby with `bundler-cache: true` (which
restores the gem cache automatically), installs the Plushie tool set,
builds the payload, produces the portable artifact, computes a
SHA-256 sidecar, and uploads both files to the release that the tag
push creates.

Lines to tweak for your project:

- The matrix runner labels (`macos-13` for Intel macOS, `macos-14`
  for Apple Silicon). GitHub-hosted runner labels change over time;
  pin or update as needed. Add `ubuntu-24.04-arm` (or use a
  self-hosted runner) for Linux aarch64.
- The Ruby version in `ruby/setup-ruby`. Match what your project
  supports; the SDK requires `>= 3.2`.
- The `rake plushie:package` arguments: `app_id` and the display
  name. `${{ github.ref_name }}` resolves to the tag (`v0.1.0`),
  which the assembler accepts as the app version.
- Release notes: set `generate_release_notes` to `false` and add
  `body` (or `body_path`) if you write release notes by hand.

To also build OS-native installers, add a second matrix entry that
calls `bin/plushie package bundle --format <name>` (repeat per format) instead of
`package portable`, and adjust the upload glob accordingly. Apple
formats need a macOS runner with valid signing identities; Windows
formats need a Windows runner with the appropriate SDKs.

For private hosting, replace the upload step with whatever pushes
the artifact and sidecar to your release endpoint. Any service that
exposes the assets at `BASE/vVERSION/ARTIFACT` plus
`BASE/vVERSION/ARTIFACT.sha256` works with the download flow.

## Signing

`plushie-package.toml` carries a `[[signing.hooks]]` block: a list of
commands that run after the artifact is built. Pass
`--run-signing-hooks` to `package portable` or `package bundle` to
invoke them. Hooks are opt-in so release builds run them and local
experimentation does not.

Each hook is a structured argv. Use them for macOS notarization,
Windows code signing, Linux checksum attestation, or whatever else the
target platform needs. Plushie does not hold signing keys; the hook
commands do.

## Updates

`plushie-package.toml` reserves an `[updates]` block for update
channel metadata. The schema is in place. The runtime side that
consumes it, planned around
[cargo-packager-updater](https://github.com/crabnebula-dev/cargo-packager),
is not yet shipped.

## Host-first versus renderer-parent

Packaging is host-first. The launcher starts the Ruby app and the
app starts its own renderer.

A separate renderer-parent flow exists for development and embedding
hosts. The renderer starts first, binds a Unix socket, and spawns
the Ruby command with `PLUSHIE_SOCKET` pointing at it:

```bash
plushie-renderer --listen \
  --exec-bin bundle \
  --exec-arg exec \
  --exec-arg rake \
  --exec-arg 'plushie:connect[Notes]'
```

`--listen`, `--exec-bin`, and `--exec-arg` are flags on the
`plushie-renderer` binary, not the `plushie` orchestration tool.

`rake plushie:connect` reads the socket and connects.
`Plushie.connect` is the runtime entry point for both flows; it
detects `PLUSHIE_SOCKET` and either connects to the existing renderer
or spawns its own.

The same entry point is what `bin/start_host.rb` calls in a packaged
app, so driving a packaged app from an external renderer is possible
but requires adding `PLUSHIE_SOCKET` to `[start].forward_env` so the
launcher passes the variable through. This is not a default-on
configuration.

## See also

- [Rake Tasks reference](rake-tasks.md) - all Rake tasks including
  `plushie:package`, `plushie:download`, `plushie:build`, and
  `plushie:connect`
- [Configuration reference](configuration.md) - environment variables,
  `Plushie.configure` fields, and transport modes
- [Wire Protocol reference](wire-protocol.md) - message format, token
  handling, and renderer-parent startup
- [Versioning reference](versioning.md) - the relationship between
  the gem version, `PLUSHIE_RUST_VERSION`, and the renderer binary
- `Plushie.connect` - the runtime entry point used by
  `bin/start_host.rb`
- `Plushie::Binary` - binary resolution, including how packaged apps
  find their payload-local renderer
- [Bundler deployment documentation](https://bundler.io/guides/deploying.html) -
  the `path`/`without` configuration the packager uses to vendor gems
