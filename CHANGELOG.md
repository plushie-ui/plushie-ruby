# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.6.0] - 2026-05-09

Targets plushie-renderer 0.7.1.

### Breaking changes

- Environment variable `PLUSHIE_SOURCE_PATH` renamed to
  `PLUSHIE_RUST_SOURCE_PATH`. Update shell profiles and CI configs.
- Constant `Plushie::BINARY_VERSION` renamed to
  `Plushie::PLUSHIE_RUST_VERSION` to match the plushie-rust release
  identifier. Anything referencing the old name needs updating.
- `Command.async` renamed to `Command.task` for cross-SDK consistency
  (`async` is reserved in Python and Rust). `Command.done` renamed to
  `Command.dispatch` to reflect the "send through update" semantic.
  `Command.widget_commands` renamed to `Command.widget_batch` to match
  the Elixir SDK and disambiguate from the `Plushie::Command` type.
- Grid widget `columns` prop renamed to `num_columns`.
- `Command.Image.create_image` and `update_image` no longer accept
  `pixels:`, `width:`, `height:` keyword arguments for raw RGBA data.
  Use the new dedicated `create_image_rgba(handle, width, height, pixels)`
  and `update_image_rgba(handle, width, height, pixels)` constructors
  instead. The blob-data form of `create_image` and `update_image`
  (passing raw binary data directly) is unchanged.
- Table widget `:selected` and `:striped` props removed; they were
  dead code with no renderer-side effect.

### Added

- `Plushie::CargoPlushie.resolve` helper that locates a usable
  cargo-plushie via `PLUSHIE_RUST_SOURCE_PATH`, falling back to a
  version-matched binary on `PATH`, otherwise raising with
  `cargo install cargo-plushie --version <version> --locked`
  guidance.
- `docs/versioning.md` documenting the `PLUSHIE_RUST_VERSION` pin and
  SDK-vs-plushie-rust versioning rules.
- `Event::SessionError` and `Event::SessionClosed` typed variants.
  `SessionError` includes a `code` field carrying the numeric error code
  from the renderer.
- `Event::Diagnostic` typed variants: `crash`, `update_panicked`,
  `renderer_error`, `protocol_error`, and `unknown`. Previously all
  diagnostics arrived as the generic `Diagnostic` struct; each kind
  now has its own Data class with kind-specific fields.
- `Plushie::BufferOverflowError` and `Plushie::ProtocolVersionMismatchError`
  typed error classes raised on the matching renderer-side conditions.
- `Event::Effect` typed per-kind result variants. Effect callbacks now
  receive a typed struct rather than a raw Hash.
- `RichText::Span` typed Data class for inline text spans.
- `link_click` events decoded as a typed `:link_click` variant on
  `Event::Widget`.
- Touch release events carry a `lost` flag when the pointer left the
  window before the release.
- `Rule` widget `thickness` prop as a direction-agnostic alternative to
  the existing `width`/`height` split.
- SDK-side event coalescing: high-frequency events declared coalesable
  are deduplicated in the bounded queue before reaching `update`.
- `Command.dispatch` chain depth is now capped; dispatching beyond the
  limit raises rather than looping indefinitely.
- `Binary.resolve` falls back to a locally built renderer binary under
  `../plushie-rust/target/{release,debug}/plushie-renderer` when
  `PLUSHIE_RUST_SOURCE_PATH` is set and no explicit path is configured.
- `rake plushie:preflight` rebuilds the renderer binary from the local
  plushie-rust checkout when `PLUSHIE_RUST_SOURCE_PATH` is set.
- Negative padding, border width, and border radius values are now
  rejected at build time with an `ArgumentError`.

### Fixed

- Subscription `key_press` and `key_release` events now read the
  structured key payload (`key`, `modified_key`, `physical_key`,
  `location`, `text`, `repeat`) from the `value` field. The previous
  fallback to top-level message fields read modifiers from the wrong
  location when value was non-Hash and would silently misread future
  shape changes.
- `animation_frame` and `theme_changed` no longer carry dead fallback
  reads alongside the canonical `value` access; the fallbacks could
  never fire against the real renderer and masked the intended source
  field.
- `ime_preedit` and `ime_commit` now raise `ArgumentError` when the
  `value` payload is missing or non-Hash, surfacing wire-shape drift
  instead of producing an `Event::Ime` with nil text and cursor.
- Concurrency bugs in the runtime, bridge, and session pool: a race in
  the timer scheduler, a missing mutex on effect-kind state, and a
  session-pool drain condition that could deadlock under session churn.
- Cancelled async threads are now properly released; previously a
  cancelled task could hold its thread until the pool was torn down.
- Effect cancellation events are dispatched to `update` during SDK
  shutdown so apps can clean up transient state.
- `image_list` and `image_clear` now route through the typed `image_op`
  wire channel rather than a generic command envelope.
- `default_font` is always encoded as a `{ family: ... }` object; the
  previous path emitted a bare string that the renderer rejected.
- `window_opened` position fields are now read from top-level `x`/`y`
  keys as the protocol specifies; the previous path read from a nested
  `position` map that does not exist.
- Effect tag supersession correctly clears the effect-kinds index when
  a new registration replaces an existing one under the same tag.
- Unknown event families tolerate a missing `window_id` field instead
  of raising a `KeyError`.
- Wayland-specific environment variables are now forwarded to the
  renderer subprocess.
- `Plushie.configure { |c| c.log_level = ... }` is now honoured; the
  previous path set the logger level only on the initial connection,
  which was overwritten on restart.
- Renderer build lookup no longer raises on a missing `_build` directory;
  it falls through to the next resolution step.
- Runtime event queue is bounded; a stalled app no longer causes
  unbounded memory growth under high-frequency event sources.
- Widget state callbacks are no longer inherited across unrelated widget
  subclasses defined with `Widget.define`.
- Effects are cancelled and their callbacks suppressed when the SDK
  shuts down.
- Timeout error messages include the action and selector for easier
  diagnosis in test output.
- Widget set override names are validated to prevent accidental
  shadowing of built-in DSL methods.
- Renderer exit details are sanitised before appearing in error messages
  and logs.

### Changed

- Native widget builds now delegate workspace generation and
  `cargo build` to [cargo-plushie](https://crates.io/crates/cargo-plushie).
  The Ruby SDK writes a minimal virtual app manifest under
  `_build/plushie-renderer-spec/` and shells out to
  `cargo plushie build`. Widget discovery, [patch.crates-io] forwarding,
  collision checks, and constructor validation now live in
  cargo-plushie and are shared across host SDKs.
- Native widget crates must now declare
  `[package.metadata.plushie.widget] { type_name, constructor }` in
  their Cargo.toml. cargo-plushie uses that table for discovery.
- Renderer subprocess environment is now filtered to variables with a
  `PLUSHIE_` prefix plus a small display-server allowlist. Previously
  the full shell environment was forwarded.
- Per-timer threads replaced with a single `TimerScheduler` thread
  using deadline-based `IO.select`. Timer count no longer scales the
  thread count.
- Renderer restart backoff parameters, nil-view handling, and frozen
  overlay semantics aligned with the Elixir and other SDKs.

### Removed

- The checked-in `native/plushie/Cargo.lock` stash. cargo-plushie
  manages the scratch workspace's lock file.

## [0.5.0] - 2026-03-23

Initial release. Targets plushie-renderer 0.5.0.

### Added

- Elm architecture (init/update/view/subscribe) via `include Plushie::App`
- Immutable models via `Plushie::Model.define` (Data.define + #with)
- Block-based UI DSL with 39 widget types
- Canvas shape DSL with typed structs (Rect, Circle, Line, Text, Path, Group)
- Canvas Group with transforms array, clip field, and top-level
  interactive properties (on_click, on_hover, focus_style, focusable, a11y)
- Canvas widget `role` and `arrow_mode` props for accessible containers
- Complete wire protocol encode/decode (MessagePack + JSONL)
- Tree diffing with incremental patch generation
- 72+ command constructors (async, focus, scroll, window ops, effects,
  focus_element for canvas, etc.)
- Platform effects (file dialogs, clipboard, notifications)
- Subscription system (timers, keyboard, mouse, window events)
- Three transport modes: spawn, stdio, iostream
- Renderer lifecycle management with exponential backoff restart
- Error recovery: StandardError rescue in update/view with model
  preservation and log throttling
- 18 property type modules with wire encoding
- State helpers: Animation, Route, Selection, Undo, DataQuery, State,
  KeyModifiers
- Widget extension system (pure Ruby composites + native Rust-backed)
- Native Rust extension build pipeline via `rake plushie:build` --
  generates Cargo workspace, validates crate paths and constructors,
  detects type name and crate collisions, builds custom renderer binary
- `Plushie.configure` block for SDK-wide configuration: `binary_path`,
  `source_path`, `build_name`, `widgets`, `widget_config`,
  `test_backend`
- `widget_config` runtime configuration passed to native widgets
  via the Settings wire message and `InitCtx`
- WASM renderer download via `rake plushie:download[wasm]`
- `PLUSHIE_BIN_FILE` and `PLUSHIE_WASM_DIR` env vars for overriding
  download and build output paths
- `rake plushie:connect` task for stdio transport (plushie --exec)
- Token authentication for --exec and remote rendering
- `RendererEnv` to filter sensitive environment variables from renderer
  subprocess
- Dev server with hot code reloading
- Test framework with three backends (mock, headless, windowed)
- Session pooling for parallel test execution
- Snapshot and screenshot assertion helpers
- .plushie script format parser and runner
- Minitest and RSpec integration
- 100% YARD documentation coverage with zero warnings
- RBS type signatures for all modules
- GitHub Actions CI workflow (Ruby 3.2 + 3.3 + 4.0 matrix)
- CONTRIBUTING.md with commit conventions and development guide
- Rake tasks: download, build, run, connect, inspect, script, replay,
  preflight
- Binary download with SHA-256 checksum verification
- 9 examples: counter, clock, todo, async_fetch, notes, shortcuts,
  color_picker, catalog, rate_plushie
- Extracted reusable canvas widgets: StarRating, ThemeToggle,
  ColorPickerWidget (in examples/widgets/)
