# Versioning

The plushie gem has two independent version numbers:

- `Plushie::VERSION`: the gem version (RubyGems semver).
- `Plushie::PLUSHIE_RUST_VERSION`: the plushie-rust release this gem
  pins to.

## The plushie-rust pin

plushie-rust ships every crate at one workspace version. That number
(`PLUSHIE_RUST_VERSION`) governs three artifacts the Ruby SDK
touches:

- the prebuilt `plushie-renderer` binary downloaded by
  `rake plushie:download`,
- the `cargo-plushie` build tool invoked by `rake plushie:build`,
- the `plushie-renderer` / `plushie-widget-sdk` versions emitted
  into the generated renderer Cargo.toml.

All three must come from the same plushie-rust release, because the
wire protocol, the Rust API, and the Cargo deps evolve together. A
gem release that declared `PLUSHIE_RUST_VERSION = "0.6.1"` is
promising every plushie-rust artifact it uses comes from `0.6.1`.

See the upstream reference at
[plushie-rust/docs/versioning.md](https://github.com/plushie-ui/plushie-rust/blob/main/docs/versioning.md)
for the canonical statement.

## Two axes, two bumps

The gem version and the plushie-rust pin move independently:

- Ruby-only changes (dialyzer-style cleanups, new SDK APIs built on
  the existing protocol, docs) bump the gem version only.
  `PLUSHIE_RUST_VERSION` stays the same.
- plushie-rust upgrades (new renderer widgets, protocol additions,
  renderer fixes) bump `PLUSHIE_RUST_VERSION` inside the gem and
  usually bump the gem version as well.

## Exact-match rule

The pin is an exact version string, not a semver range. There is no
`"~> 0.6"` fuzzy pin. We bump the exact number on every renderer
upgrade.

Rationale: the renderer binary, the generated Cargo deps, and the
protocol messages travel together. A single mismatched version puts
the SDK out of sync with itself. Forcing exact-match removes that
whole class of "mostly works, except for the one message that
changed" bugs.

## cargo-plushie install pins to PLUSHIE_RUST_VERSION

Users who don't set `PLUSHIE_RUST_SOURCE_PATH` install cargo-plushie
from crates.io:

```
cargo install cargo-plushie --version <PLUSHIE_RUST_VERSION> --locked
```

`Plushie::CargoPlushie.resolve` compares the installed tool's
`--version` against `Plushie::PLUSHIE_RUST_VERSION` and fails with
the exact install command if they don't match. That keeps the
renderer workspace generator, the dep versions it emits, and the
renderer binary it ultimately produces on the same release.

## PLUSHIE_RUST_SOURCE_PATH (development)

Contributors working across plushie-rust and plushie-ruby in lockstep
set the env var at a local plushie-rust checkout:

```
export PLUSHIE_RUST_SOURCE_PATH=/path/to/plushie-rust
```

When set, `rake plushie:build` ignores the `PATH` lookup and runs
cargo-plushie via `cargo run -p cargo-plushie` out of the checkout.
No reinstall needed after a `git pull`; whatever's in the tree is
what runs.

## Wire protocol version

The wire protocol has its own version negotiated in the handshake,
independent of `PLUSHIE_RUST_VERSION`. Patch releases (e.g. `0.6.1`
to `0.6.2`) must not break protocol compatibility; minor and major
bumps may. The handshake surfaces a protocol mismatch early with a
clear error rather than letting the app produce corrupt behaviour.
