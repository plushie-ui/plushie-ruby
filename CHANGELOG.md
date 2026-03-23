# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] - 2026-03-23

### Added
- Elm architecture (init/update/view/subscribe) via `include Plushie::App`
- Immutable models via `Plushie::Model.define` (Data.define + #with)
- Block-based UI DSL with 39 widget types
- Canvas shape DSL with typed structs (Rect, Circle, Line, Text, Path, Group)
- Complete wire protocol encode/decode (MessagePack + JSONL)
- Tree diffing with incremental patch generation
- 72+ command constructors (async, focus, scroll, window ops, effects, etc.)
- Platform effects (file dialogs, clipboard, notifications)
- Subscription system (timers, keyboard, mouse, window events)
- Three transport modes: spawn, stdio, iostream
- Renderer lifecycle management with exponential backoff restart
- 18 property type modules with wire encoding
- State helpers: Animation, Route, Selection, Undo, DataQuery, State, KeyModifiers
- Widget extension system (pure Ruby composites + native Rust-backed)
- Native Rust extension build pipeline via `rake plushie:build` --
  generates Cargo workspace, validates crate paths and constructors,
  detects type name and crate collisions, builds custom renderer binary
- `Plushie.configure` block for SDK-wide configuration: `binary_path`,
  `source_path`, `build_name`, `extensions`, `extension_config`,
  `test_backend`
- `extension_config` runtime configuration passed to Rust extensions
  via the Settings wire message and `InitCtx`
- WASM renderer download via `rake plushie:download[wasm]`
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
- RBS type signatures for core public API
- Rake tasks: download, build, run, connect, inspect, script, replay,
  preflight
- Binary download with SHA-256 checksum verification
- 8 examples: counter, clock, todo, async_fetch, notes, shortcuts, color_picker, catalog
