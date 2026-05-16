# Packaging

Every chapter so far has assumed the app runs on the machine that
built it. You ran `bundle install`, fetched a renderer, and typed
`ruby pad.rb`. Shipping the same app to another person is a
different problem. A Plushie Ruby app has three moving parts that
have to arrive on the target machine together: your Ruby source,
the `plushie` gem, and a `plushie-renderer` binary that matches
the gem's pinned `PLUSHIE_RUST_VERSION`. If you added any native
widgets, a fourth part joins the list: the Rust source for those
widgets plus the custom renderer binary built from them.

This chapter covers the shipping story: run-from-source for
teammates, gem publishing to RubyGems.org, bundling a prebuilt
binary, and distributing a native widget gem that consumers
compile locally.

## Why packaging needs attention

A Plushie app is not a single Ruby process. At runtime it is two
processes talking over a pipe:

- The Ruby side holds the model, the view function, commands,
  subscriptions, and every event handler.
- The renderer side (`plushie-renderer`) owns the window, the GPU,
  iced, and every widget implementation.

The Ruby side travels as a gem. The renderer side is a native
binary that has to match the gem's `Plushie::PLUSHIE_RUST_VERSION`
exactly. Shipping one without the other gets a
`ProtocolVersionMismatchError` on startup.

Three additional constraints shape the packaging options:

- Renderer binaries are platform-specific. `linux-x86_64`,
  `darwin-aarch64`, and `windows-x86_64` are separate builds with
  separate SHA-256 sidecars.
- Renderer binaries are large (tens of megabytes). Bundling one
  per platform inside a gem inflates the gem.
- Native widgets require a custom renderer built from Rust source
  on the consumer's machine, which means they need a Rust
  toolchain anyway.

The options below trade these constraints against each other.

## Option A: run from source

The simplest path, and the right default for internal tools and
team scripts. Consumers clone the repository, install the gem,
and fetch the renderer at setup time.

`Gemfile`:

```ruby
source "https://rubygems.org"

gem "plushie", "~> 0.5"
gem "rake"
```

`Rakefile`:

```ruby
require "plushie/rake"
require_relative "lib/my_app"
```

`bin/my_app`:

```ruby
#!/usr/bin/env ruby
require_relative "../lib/my_app"
Plushie.run(MyApp)
```

The README walks the install:

```bash
git clone https://github.com/you/my_app.git
cd my_app
bundle install
bundle exec rake plushie:download
bundle exec ruby bin/my_app
```

`rake plushie:download` fetches a precompiled renderer from GitHub
releases, verifies the SHA-256 sidecar, and places it under
`bin/`. The version is pinned by the gem's
`Plushie::PLUSHIE_RUST_VERSION` constant, so the binary and the
gem always agree. No publishing, no release pipeline, no gem
build step.

## Option B: publish a gem

Once the app stabilises enough to share outside the team, publish
it to [RubyGems](https://rubygems.org). Consumers `gem install`
your app, then run the same download task to fetch the renderer.

### Gemspec

Name the gem, depend on `plushie`, and list the files that ship:

```ruby
# my_app.gemspec
require_relative "lib/my_app/version"

Gem::Specification.new do |spec|
  spec.name    = "my_app"
  spec.version = MyApp::VERSION
  spec.authors = ["You"]
  spec.summary = "A Plushie desktop app"
  spec.license = "MIT"
  spec.homepage = "https://github.com/you/my_app"

  spec.required_ruby_version = ">= 3.2.0"
  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE.txt"]
  spec.bindir      = "exe"
  spec.executables = ["my_app"]

  spec.add_dependency "plushie", "~> 0.5"
end
```

A few choices worth naming:

- **Depend on `plushie` with a pessimistic constraint.** The gem's
  API is pre-1.0, so breaking changes can land in any `0.X.0`
  bump. Pinning to `~> 0.5` keeps you on the `0.5.x` line and
  lets Bundler pick up patch releases.
- **Don't list `plushie-renderer` as a dependency.** The renderer
  is a binary, not a gem. Its version is pinned transitively by
  the `plushie` gem's `PLUSHIE_RUST_VERSION` constant.
- **Set `rubygems_mfa_required`.** Matches the `plushie` gem's own
  metadata and prevents account-takeover pushes.

### Executable and version

Put the launcher under `exe/my_app` (calling `Plushie.run(MyApp)`)
and add `spec.executables = ["my_app"]` with
`spec.bindir = "exe"` to the gemspec. Define
`MyApp::VERSION = "0.1.0"` in `lib/my_app/version.rb` and require
it from the gemspec at the top. Bump it in lockstep with shipped
changes.

### Post-install fetch

A gem install cannot run arbitrary code on recent RubyGems without
a C extension hook, and the renderer is not a C extension. Tell
the user to fetch the renderer explicitly after installing:

```bash
gem install my_app
my_app --setup   # your wrapper that runs Plushie::Binary.download!
my_app
```

Or lean on Bundler's `rake` task if the consumer has the source
tree:

```bash
bundle exec rake plushie:download
```

Document whichever path you pick in your README. Hiding the
download behind a `post_install_message` is the minimum; a
dedicated setup subcommand is friendlier.

## Option C: bundle a prebuilt binary

When the target audience does not have a working internet
connection, or the renderer must be available without extra
setup, ship the binary inside the gem itself. The cost is a
platform-specific gem, one per OS and architecture.

### Platform-specific gems

Build one gem per supported platform with the matching renderer
binary in each:

```ruby
# my_app.gemspec
Gem::Specification.new do |spec|
  spec.name     = "my_app"
  spec.version  = MyApp::VERSION
  spec.platform = ENV["MY_APP_GEM_PLATFORM"] || Gem::Platform::RUBY

  spec.files = Dir[
    "lib/**/*.rb",
    "vendor/plushie-renderer-*",
    "README.md",
    "LICENSE.txt"
  ]

  spec.required_ruby_version = ">= 3.2.0"
  spec.add_dependency "plushie", "~> 0.5"
end
```

The build script loops over supported platforms, sets
`MY_APP_GEM_PLATFORM`, and runs `gem build`:

```bash
for plat in x86_64-linux arm64-darwin x86_64-darwin x64-mingw-ucrt; do
  MY_APP_GEM_PLATFORM=$plat \
    vendor_renderer_for "$plat" \
    gem build my_app.gemspec
done
```

Where `vendor_renderer_for` downloads the matching binary from
the `plushie-renderer` release, verifies its checksum, and drops
it under `vendor/`.

### Pointing the SDK at the bundled binary

The bundled binary has to be on the resolution path. Set
`Plushie.configuration.binary_path` at boot, resolving the path
relative to the gem's install location:

```ruby
# lib/my_app.rb
require "plushie"

module MyApp
  def self.renderer_path
    File.expand_path("../vendor/#{Plushie::Binary.binary_name}", __dir__)
  end
end

Plushie.configure do |config|
  config.binary_path = MyApp.renderer_path
end
```

`Plushie::Binary.binary_name` returns the stable project-local
filename (`plushie-renderer`, with `.exe` on Windows). The resolver
treats `binary_path` as explicit: if the file is missing, it raises
immediately rather than falling through to `bin/`. See the
[Configuration reference](../reference/configuration.md) for the
full resolution order.

A renderer binary is tens of megabytes, so a bundled-binary gem
runs several times larger than the base gem. Document the
download size in the README, and consider whether Option B gives
a better first-install experience.

## Option D: standalone launcher package

For a single-file app launcher, let the Ruby SDK prepare the
host payload and manifest, then hand that manifest to the shared
Rust package launcher. The language-specific work stays in Ruby:
copying a conservative Ruby runtime, installing runtime gems,
copying the app files, including a payload-local renderer,
materializing default launcher icons, writing `plushie-package.toml`,
and archiving the payload.

The default shape expects:

- `lib/` for application code
- `bin/connect` as the standalone host entrypoint
- `Gemfile` for runtime dependencies
- a renderer available through `PLUSHIE_BINARY_PATH`,
  `PLUSHIE_RUST_SOURCE_PATH`, or `rake plushie:download`

The SDK generates OS-specific launcher wrappers from your `bin/connect`
script. On POSIX targets it writes `bin/connect` as a shebang script that
invokes the bundled `ruby/bin/ruby`. On `windows-*` targets it writes
`bin/connect.cmd` (a Windows batch file) instead. Your `bin/connect` script
is copied to `bin/connect.rb` in the payload in both cases; the manifest
records whichever wrapper the launcher should call.

Add `require "plushie/rake"` to the app's `Rakefile`, then run:

```bash
bundle exec rake 'plushie:package[dev.example.notes,Notes,0.1.0]'
```

The task writes `dist/payload.tar.zst` and
`dist/plushie-package.toml`. Build the outer launcher with:

```bash
bin/plushie package portable --manifest dist/plushie-package.toml
```

For custom renderers, set `PLUSHIE_PACKAGE_RENDERER_KIND=custom` and
point `PLUSHIE_PACKAGE_RENDERER_PATH` or `PLUSHIE_BINARY_PATH` at the
renderer binary to copy into the payload.

You can run the same gate before building the launcher:

```bash
bin/plushie package check --manifest dist/plushie-package.toml --strict-tools
```

The manifest records `host_sdk = "ruby"`, the Ruby SDK version,
`PLUSHIE_RUST_VERSION`, the protocol version, the package target,
payload hash and size, renderer provenance (`kind` and `source`),
and `[platform]` metadata when configured. By default the Ruby
helper invokes `bin/plushie default-icons --out dist/payload/assets`
before archiving and records `assets/default-app-icon-512.png`. Set
`PLUSHIE_PACKAGE_ICON_PATH` to copy an app icon into `assets/` and
record that payload-relative path instead. The `[platform]` section is
omitted entirely when no platform fields are set.

Optional platform metadata is declared in `plushie-package.config.toml`.
Run `--write-package-config` to generate a template with commented-out
examples. Supported fields:

```toml
[platform]
publisher = "Example Corp"
copyright = "Copyright 2025 Example Corp"
category = "Productivity"
description = "A short description of the application."
bundle_id = "com.example.myapp"

[platform.macos]
bundle_version = "1"   # CFBundleVersion (usually an incrementing integer string)

[platform.windows]
install_scope = "perUser"  # "perUser" or "perMachine"
```

All fields are optional. `[platform]`, `[platform.macos]`, and
`[platform.windows]` are each omitted from the emitted manifest when
they carry no populated fields.

For scripts that need a direct helper instead of Rake, use
`Plushie::Package.build` from `require "plushie/package"`.
Environment variables such as `PLUSHIE_PACKAGE_OUTPUT` and
`PLUSHIE_PACKAGE_ICON_PATH` are still supported for less common
package inputs and CI configuration.

## Option E: native widget distribution

A gem that extends Plushie with a custom Rust widget can't ship a
prebuilt binary: the consumer's renderer has to include the
widget, which means compiling a custom renderer on the consumer's
machine. The gem ships the Rust source, and the consumer runs
`rake plushie:build`.

The shape:

```
my_sparkline/
  my_sparkline.gemspec
  lib/
    my_sparkline.rb
    my_sparkline/
      version.rb
      extension.rb
  native/
    sparkline/
      Cargo.toml
      src/
        lib.rs
```

Gemspec lists both trees:

```ruby
Gem::Specification.new do |spec|
  spec.name    = "my_sparkline"
  spec.version = MySparkline::VERSION
  spec.files   = Dir[
    "lib/**/*.rb",
    "native/sparkline/Cargo.toml",
    "native/sparkline/src/**/*.rs",
    "README.md"
  ]

  spec.required_ruby_version = ">= 3.2.0"
  spec.add_dependency "plushie", "~> 0.5"
end
```

The Ruby declaration resolves its `rust_crate` path against the
gem's install location, so downstream apps do not have to know
where the gem unpacks:

```ruby
module MySparkline
  class Extension
    include Plushie::Widget

    widget :sparkline, kind: :native_widget
    rust_crate File.expand_path("../../../native/sparkline", __FILE__)
    rust_constructor "sparkline::Extension::new()"

    prop :data, :any, default: []
  end
end
```

The downstream app wires the gem into its own build config:

```ruby
# Rakefile
require "plushie"
require "my_sparkline"

Plushie.configure do |config|
  config.widgets    = [MySparkline::Extension]
  config.build_name = "my-app-plushie"
end

require "plushie/rake"
```

Then the usual flow runs:

```bash
bundle install
bundle exec rake plushie:build
bundle exec rake 'plushie:run[MyApp]'
```

`rake plushie:build` requires a Rust toolchain and `cargo-plushie`
at the version pinned by `Plushie::PLUSHIE_RUST_VERSION`. See the
[Native Extensions reference](../reference/native-extension.md)
for the full widget-distribution story, and the
[Rake Tasks reference](../reference/rake-tasks.md) for how
`cargo-plushie` is resolved.

No `extensions` entry and no `gem install` compile hook: the gem
stays cheap to install, and the expensive Rust compile only
happens when the consumer opts in via `rake plushie:build`.

## Version pinning

Keep the gem's own version and the pinned renderer version moving
in lockstep in your head even when they do not in the code. The
rules:

- Bug fixes and new Ruby features in your app bump `MyApp::VERSION`
  but leave the `plushie` dependency alone. Pre-1.0, you are
  pinned to a minor line (`~> 0.5`), so `bundle update plushie`
  inside that line is safe.
- A `plushie` upgrade to a new minor line (`~> 0.6`) changes
  `PLUSHIE_RUST_VERSION` transitively. Run
  `rake plushie:download` or `rake plushie:build` to pick up the
  matching renderer, run the test suite, and bump `MyApp::VERSION`
  with a CHANGELOG entry noting the renderer upgrade.
- Pin `plushie` to an exact version (`= 0.6.0`) if your users
  share a binary out of band, so the protocol version they get
  never drifts from the one your gem expects.

The [Versioning reference](../reference/versioning.md) covers the
three-axis model (gem version, `PLUSHIE_RUST_VERSION`, wire
protocol) in full, including how `Plushie::ProtocolVersionMismatchError`
surfaces a drift.

## Release checklist

The sequence that keeps a release clean:

1. **CHANGELOG.** Move unreleased entries into a dated section
   under the new version. Call out any `plushie` upgrade and
   which `PLUSHIE_RUST_VERSION` it pulls in.
2. **Version bump.** Update `lib/my_app/version.rb` to match the
   CHANGELOG section.
3. **Preflight.** Run the full check suite, including the
   headless backend if your CI covers it:

   ```bash
   bundle exec rake
   PLUSHIE_TEST_BACKEND=headless bundle exec rake test
   ```

4. **Build the gem.** `gem build my_app.gemspec` produces
   `my_app-<version>.gem`.
5. **Clean-install test.** In a fresh directory, without your
   project's `Gemfile` in scope:

   ```bash
   gem install ./my_app-0.1.0.gem
   my_app
   ```

   This catches missing files in the gemspec, wrong executable
   paths, and binary resolution bugs that hide under Bundler's
   load path.
6. **Tag and push.** `git tag v0.1.0 && git push --tags`. The tag
   is the permanent reference for the release.
7. **Publish.** `gem push my_app-0.1.0.gem`. RubyGems sends an
   MFA prompt when `rubygems_mfa_required` is set; approve it.
8. **Update docs.** Link the new version in the README if it pins
   an example. If the gem ships a download URL or install guide,
   verify both still resolve.

The same checklist works for Option E (native widget gems). The
clean-install step is the key safeguard there too: it confirms
the Rust source files shipped in the gem and `rake plushie:build`
finds them from the install location.

## User-facing install story

What does someone running your app actually type? By option:

```bash
# Option A: run from source
git clone https://github.com/you/my_app.git
cd my_app
bundle install
bundle exec rake plushie:download
bundle exec ruby bin/my_app

# Option B: gem, separate renderer download
gem install my_app
my_app --setup   # wraps Plushie::Binary.download!
my_app

# Option C: bundled binary
gem install my_app --platform=x86_64-linux
my_app

# Option D: standalone launcher
bundle exec rake 'plushie:package[dev.example.notes,Notes,0.1.0]'
bin/plushie package portable --manifest dist/plushie-package.toml

# Option E: native widget gem (consumer has a Rust toolchain)
bundle add my_sparkline
bundle exec rake plushie:build
bundle exec rake 'plushie:run[MyApp]'
```

Pick the option that matches the audience. A developer tool is
fine on A; a commercial app on Windows is better served by C; a
managed standalone distribution can use D; a widget library has no
choice but E.

## Troubleshooting for packagers

### Binary architecture mismatches

`plushie binary not executable` after install usually means the
wrong platform binary shipped. `RbConfig::CONFIG["host_os"]` and
`host_cpu` report what Ruby was compiled for, which is not always
what the user's hardware actually is (Rosetta 2 on Apple Silicon,
x86_64 Ruby under an aarch64 macOS). Log both values in the
launcher when startup fails so bug reports arrive with the
relevant facts.

### Missing GPU libraries on Linux

A fresh Linux install without a desktop session is missing the
Vulkan user-space libraries the renderer needs. The renderer
fails to start with a wgpu error. Document the required package
in the README: `vulkan-icd-loader` on Arch, `mesa-vulkan-drivers`
on Debian and Ubuntu, `vulkan-loader` on Fedora. See the
[Getting Started guide](02-getting-started.md) for the full list.

### macOS Gatekeeper

A downloaded renderer binary on macOS carries the quarantine
attribute, and Gatekeeper blocks it on first launch. The download
task does not strip the attribute because only a user action can
authorise it. Advise consumers to run
`xattr -d com.apple.quarantine` on the binary, or run the same
command inside a `--setup` subcommand after copying the file
into place for Option C.

### Windows SmartScreen

Unsigned binaries on Windows trigger SmartScreen warnings. Signing
the renderer for distribution needs an authenticode certificate,
which is worth the investment for a public release but not for
internal tools. The Run-anyway workaround is fine for Option A
but will scare off consumers of a commercial gem.

### Checksum mismatch on download

`rake plushie:download` verifies every binary against a `.sha256`
sidecar and aborts on mismatch. Check that the consumer's gem
version matches what you published, that no HTTP proxy is
serving a cached error page, and that the release on
[github.com/plushie-ui/plushie-rust/releases](https://github.com/plushie-ui/plushie-rust/releases)
still exists and has a sidecar. Re-running the task is almost
always enough.

## Exercise: publish the pad as a gem

Outline for turning the pad app from the earlier chapters into a
distributable gem. Read the plan, then execute when you have
somewhere to publish to.

1. Create `pad.gemspec` with the same Ruby floor as `plushie`
   (`>= 3.2.0`) and a `~> 0.5` dependency on `plushie`.
2. Move `pad.rb` under `lib/pad.rb` and move the runner into
   `exe/pad`, calling `Plushie.run(Pad)`. Add
   `spec.executables = ["pad"]` and `spec.bindir = "exe"` to the
   gemspec.
3. Define `Pad::VERSION = "0.1.0"` in `lib/pad/version.rb`, and
   require it from the gemspec.
4. Write a short `README.md` covering install: `gem install pad`,
   `pad --setup` (for the renderer), `pad`. Document the Vulkan
   package requirement on Linux.
5. Add a `--setup` option to `exe/pad` that calls
   `Plushie::Binary.download!` and exits, and a `--version`
   option that prints `Pad::VERSION` plus
   `Plushie::PLUSHIE_RUST_VERSION`.
6. Start a `CHANGELOG.md` with a `## 0.1.0` section.
7. Run `gem build pad.gemspec`, then `gem install ./pad-0.1.0.gem`
   in a fresh directory, then `pad --setup && pad`. If the window
   opens, the gem is shippable.
8. Run `gem push pad-0.1.0.gem` when you have a RubyGems account
   ready. Tag `v0.1.0` in git.

Bonus rounds:

- Publish a platform-specific gem (Option C) alongside the
  generic one, bundling the Linux-x86_64 renderer.
- Wrap the pad in a native widget gem (Option E) that ships a
  custom spell-check widget. Publish the widget gem first, then
  publish a pad release that depends on it.

## See also

- [Versioning reference](../reference/versioning.md), the
  relationship between `Plushie::VERSION`,
  `Plushie::PLUSHIE_RUST_VERSION`, and the wire protocol version
- [Native Extensions reference](../reference/native-extension.md),
  the full shape of a native widget gem and the Rust side of the
  distribution story
- [Rake Tasks reference](../reference/rake-tasks.md),
  `plushie:download`, `plushie:build`, and the environment
  variables that override their defaults
- [Configuration reference](../reference/configuration.md), the
  binary resolution order and the `Plushie.configure` keys that
  point the SDK at a bundled renderer

## Next steps

The guides end here. The reference set under
[`../reference/`](../reference/) covers every widget, command,
event, subscription, and configuration key in detail; each
guide chapter linked its matching reference pages in its "See
also" section. Dip in when a specific prop, flag, or edge case
comes up.
