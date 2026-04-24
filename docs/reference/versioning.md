# Versioning

Plushie has three version numbers that evolve independently: the
Ruby gem, the plushie-rust release it targets, and the wire
protocol spoken between the SDK and the renderer. All three are
constants in the SDK source and each has its own upgrade path.

## Gem version

The gem's own semver lives in `Plushie::VERSION` (defined in
`lib/plushie/version.rb`) and is published to
[RubyGems](https://rubygems.org/gems/plushie). Bumps cover
Ruby-side changes: bug fixes, new widget methods, DSL refinements,
type signatures, test helpers, documentation, and so on.

Pre-1.0, breaking changes may land in any minor bump (`0.X.0`).
Patch releases (`0.X.Y`) stay backwards-compatible within the SDK.
The [CHANGELOG](../../CHANGELOG.md) lists every release's changes
with breaking items called out under a dedicated heading.

There are no deprecation shims during the pre-1.0 window. When a
name or API shape changes, the old form is removed in the same
release that adds the new one. The CHANGELOG entry describes the
rename and its migration.

## `PLUSHIE_RUST_VERSION`

The `Plushie::PLUSHIE_RUST_VERSION` constant pins the exact
[plushie-rust](https://github.com/plushie-ui/plushie-rust) release
this SDK targets. Every plushie-rust artefact the SDK touches comes
from that release:

- The `plushie-renderer` binary downloaded by `rake plushie:download`.
- The WASM renderer downloaded by `rake plushie:download[wasm]`.
- The `cargo-plushie` tool invoked by `rake plushie:build`. The
  build fails if the tool on `PATH` does not match this version
  exactly, and prints a
  `cargo install cargo-plushie --version X.Y.Z --locked` command.
- The crate versions emitted into the generated native-widget
  workspace under `_build/plushie/custom/`.

Bumping this constant is how the SDK opts in to a newer renderer.
The two version axes move independently:

- Ruby-only fixes bump `Plushie::VERSION` only;
  `PLUSHIE_RUST_VERSION` stays put.
- plushie-rust upgrades bump `PLUSHIE_RUST_VERSION` (and usually
  `Plushie::VERSION` too, to cut a release that ships the upgrade).

`PLUSHIE_RUST_VERSION` must match a plushie-rust release exactly:
no semver ranges, no fuzzy pins. Exact match is the only way to
guarantee the renderer binary, the generated dependencies, and the
wire protocol travel together.

## Wire protocol version

`Plushie::Protocol::PROTOCOL_VERSION` is a constant integer
embedded in the `settings` message the runtime sends to the
renderer on startup. The renderer compares it against its own
constant. On mismatch the SDK raises
`Plushie::ProtocolVersionMismatchError` with `expected:` and
`got:` fields; a mismatched protocol is not safe to continue on.

Mismatches are a symptom, not the root cause. They indicate the
SDK and the renderer binary came from different plushie-rust
releases. Realigning `PLUSHIE_RUST_VERSION` with the installed
renderer, or re-running `rake plushie:download`, restores
compatibility.

## Fetching the matching renderer

`rake plushie:download` resolves the download URL from
`PLUSHIE_RUST_VERSION` and the current platform:

```
https://github.com/plushie-ui/plushie-renderer/releases/download/vX.Y.Z/plushie-renderer-<os>-<arch>
```

The download is verified against a `.sha256` sidecar file before
being written to `_build/plushie/bin/`. A checksum mismatch aborts
the download and leaves the existing binary untouched.

`rake plushie:download[wasm]` does the same for the
`plushie-renderer-wasm.tar.gz` archive, extracted to
`_build/plushie-renderer/wasm/`.

Override the destination with `PLUSHIE_BIN_FILE` or
`PLUSHIE_WASM_DIR` (or the matching `Plushie.configure` keys) when
packaging for non-default layouts.

## Building from source

`rake plushie:build` generates a minimal virtual app crate under
`_build/plushie/custom/` (listing the project's native widget
crates as path deps) and shells out to `cargo-plushie`. That tool
owns workspace generation, widget discovery, and the cargo
invocation; the SDK is a thin façade.

`cargo-plushie` is resolved in this order:

1. `PLUSHIE_RUST_SOURCE_PATH` set: invoked via
   `cargo run -p cargo-plushie ...` against the checkout.
2. `cargo-plushie` on `PATH` at the version matching
   `PLUSHIE_RUST_VERSION`.
3. Fails with `cargo install cargo-plushie --version X.Y.Z --locked`
   guidance.

For local development against a sibling plushie-rust checkout:

```bash
export PLUSHIE_RUST_SOURCE_PATH=../plushie-rust
rake plushie:build
```

The same env var is also consulted by `Plushie::Binary.resolve` to
find a locally built renderer binary under
`../plushie-rust/target/{release,debug}/plushie-renderer`.

## Ruby version floor

The gemspec declares `required_ruby_version = ">= 3.2.0"`. The
CI matrix covers 3.2, 3.3, and 4.0. Raising the floor is a
breaking change and will be called out in the CHANGELOG.

## Gem dependencies

Runtime dependencies stay on conservative ranges:

| Gem | Version |
|---|---|
| `msgpack` | `~> 1.7` |
| `logger` | any |
| `base64` | any |

`logger` and `base64` are unconstrained because they track Ruby
itself (both were bundled-then-split gems) and any compatible
version works. `msgpack` is pinned to a pessimistic range because
the wire format is sensitive to the encoder's behaviour.

Development dependencies live in the `Gemfile` rather than the
gemspec, so downstream apps pick up only the runtime set.

## Upgrade guidance

To take a newer plushie-rust release:

1. Edit the `PLUSHIE_RUST_VERSION` constant in
   `lib/plushie/version.rb`.
2. Run `rake plushie:download` to fetch the matching
   `plushie-renderer` binary, or `rake plushie:build` to rebuild
   from source. The build tool expects `cargo-plushie` on `PATH`
   at the same version; install it with the
   `cargo install cargo-plushie --version X.Y.Z --locked` command
   the build prints on mismatch.
3. Run the test suite against the new binary
   (`bundle exec rake test`).

The CHANGELOG for each gem release calls out whether it bumps
`PLUSHIE_RUST_VERSION` and what plushie-rust changes come with it.

See
[plushie-rust's versioning policy](https://github.com/plushie-ui/plushie-rust/blob/main/docs/versioning.md)
for the canonical rules covering the full Rust workspace, the wire
protocol version, and cross-SDK compatibility.

## See also

- [Configuration reference](configuration.md) - `Plushie.configure`
  keys including `binary_path`, `source_path`, `bin_file`, and
  `wasm_dir`
- [Rake tasks reference](rake-tasks.md) - full task listing with
  arguments and environment overrides
- [Events reference](events.md) - the error classes raised when
  the renderer rejects a mismatched protocol
