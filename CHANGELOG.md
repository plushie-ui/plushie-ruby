# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

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
