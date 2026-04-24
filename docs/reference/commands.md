# Commands and Effects

Commands are pure data returned from `update` and `init`. The runtime
interprets them after the update cycle completes. They are how your
app triggers side effects: background work, focus changes, window
operations, platform effects, and more.

All built-in commands live in `Plushie::Command`; platform effects
live in `Plushie::Effect`.

## Returning commands

`update` and `init` support three return shapes:

```ruby
# Bare model (no commands)
def update(model, _event)
  model
end

# Model + single command
def update(model, event)
  case event
  in Event::Widget[type: :click, id: "save"]
    [model, Plushie::Command.focus("editor")]
  end
end

# Model + command list
def update(model, event)
  case event
  in Event::Widget[type: :click, id: "export"]
    [model, [
      Plushie::Effect.file_save(:export, title: "Export"),
      Plushie::Effect.notification(:notify, "Exporting", "Saving to file...")
    ]]
  end
end
```

Invalid return shapes raise `ArgumentError` immediately. See the
[App Lifecycle reference](app-lifecycle.md) for the full validation
rules.

## Command categories

All methods live in `Plushie::Command` unless noted otherwise.
Command submodule methods are also delegated onto `Plushie::Command`
directly, so `Command.scroll_to(...)` and
`Command::Scroll.scroll_to(...)` are equivalent.

### Control flow

| Method | Purpose |
|---|---|
| `none` | No-op command (useful in conditional pipelines) |
| `dispatch(value, mapper_fn)` | Lift an already-resolved value into the pipeline. The runtime calls `mapper_fn.call(value)` and queues the result for the next update cycle. |
| `batch(commands)` | Execute an array of commands sequentially |
| `exit` | Shut down the app |

`batch` threads commands through the runtime state in order. Use it
to combine multiple side effects from a single `update` branch.

### Async

| Method | Purpose |
|---|---|
| `task(callable, tag)` | Run a `Proc` in a background thread. Result delivered as `Event::Async[tag:, result:]`. |
| `stream(callable, tag)` | Run a `Proc` with an `emit` argument. Each `emit.call(value)` delivers `Event::Stream[tag:, value:]`. The final return delivers `Event::Async[tag:, result:]`. |
| `cancel(tag)` | Kill an in-flight task or stream by tag. |
| `send_after(delay_ms, event)` | One-shot delayed event delivered through `update`. If a timer for the same event is pending, the old one is cancelled. |

`send_after` is a one-shot timer. For recurring timers, use
`Plushie::Subscription.every` instead.

### Focus

| Method | Purpose |
|---|---|
| `focus(widget_id)` | Focus a widget by ID (supports `"window#path"` form) |
| `focus_next` | Move focus to the next focusable widget |
| `focus_previous` | Move focus to the previous focusable widget |
| `focus_next_within(scope)` | Move focus to the next focusable widget within a subtree |
| `focus_previous_within(scope)` | Move focus to the previous focusable widget within a subtree |

`focus_next_within` and `focus_previous_within` confine the focus
cycle to a subtree rooted at the given widget ID. Useful for menus,
pane grids, and keyboard containers that want a bounded Tab cycle.

### Text

`Plushie::Command::Text`, delegated onto `Plushie::Command`.

| Method | Purpose |
|---|---|
| `select_all(widget_id)` | Select all text in a text input or editor |
| `move_cursor_to_front(widget_id)` | Move cursor to start |
| `move_cursor_to_end(widget_id)` | Move cursor to end |
| `move_cursor_to(widget_id, position)` | Move cursor to a specific position |
| `select_range(widget_id, start, end_pos)` | Select a text range |

### Scroll

`Plushie::Command::Scroll`, delegated onto `Plushie::Command`.

| Method | Purpose |
|---|---|
| `scroll_to(widget_id, x, y)` | Scroll to absolute position |
| `snap_to(widget_id, x, y)` | Snap to a position |
| `snap_to_end(widget_id)` | Snap to the end |
| `scroll_by(widget_id, x, y)` | Scroll by a relative offset |

### Window operations

`Plushie::Command::Window`, delegated onto `Plushie::Command`.

| Method | Purpose |
|---|---|
| `close_window(window_id)` | Close a window |
| `resize_window(window_id, width, height)` | Set window size |
| `move_window(window_id, x, y)` | Set window position |
| `maximize_window(window_id, maximized = true)` | Maximize or unmaximize |
| `minimize_window(window_id, minimized = true)` | Minimize or unminimize |
| `set_window_mode(window_id, mode)` | Set `:windowed` / `:fullscreen` mode |
| `toggle_maximize(window_id)` | Toggle maximized state |
| `toggle_decorations(window_id)` | Toggle window chrome |
| `focus_window(window_id)` | Bring window to front |
| `set_window_level(window_id, level)` | Set window z-level |
| `drag_window(window_id)` | Begin window drag |
| `drag_resize_window(window_id, direction)` | Begin window resize drag |
| `request_attention(window_id, urgency)` | Flash / bounce in the OS task switcher |
| `set_resizable(window_id, resizable)` | Change resizable flag at runtime |
| `set_min_size(window_id, width, height)` | Change minimum size at runtime |
| `set_max_size(window_id, width, height)` | Change maximum size at runtime |
| `enable_mouse_passthrough(window_id)` | Make the window click-through |
| `disable_mouse_passthrough(window_id)` | Restore normal hit-testing |
| `show_system_menu(window_id)` | Invoke the OS window system menu |
| `set_icon(window_id, rgba_data, width, height)` | Swap the window icon at runtime |
| `set_resize_increments(window_id, width, height)` | Snap-grid resize step |
| `allow_automatic_tabbing(enabled)` | macOS automatic tab management |
| `screenshot(window_id, tag)` | Capture window screenshot |

Screenshot results arrive as `Event::System[type: :screenshot_response, ...]`.

### Window queries

`Plushie::Command::WindowQuery`, delegated onto `Plushie::Command`.

| Method | Purpose |
|---|---|
| `window_size(window_id, tag)` | Query window dimensions |
| `window_position(window_id, tag)` | Query window position |
| `is_maximized(window_id, tag)` | Query maximized state |
| `is_minimized(window_id, tag)` | Query minimized state |
| `window_mode(window_id, tag)` | Query fullscreen/windowed mode |
| `scale_factor(window_id, tag)` | Query DPI scale factor |
| `raw_id(window_id, tag)` | Query platform window handle |
| `monitor_size(window_id, tag)` | Query monitor dimensions |

Results arrive as `Event::System[type:, tag:, value:]`. The `tag`
matches the symbol you provided.

### Image handles

`Plushie::Command::Image`, delegated onto `Plushie::Command`.

| Method | Purpose |
|---|---|
| `create_image(handle, data)` | Create an image from encoded PNG/JPEG bytes |
| `create_image_rgba(handle, width, height, pixels)` | Create from raw RGBA pixels |
| `update_image(handle, data)` | Replace the pixels for an existing handle |
| `update_image_rgba(handle, width, height, pixels)` | RGBA-mode update |
| `delete_image(handle)` | Free a handle |
| `list_images(tag)` | Query current handles (result via `Event::System`) |
| `clear_images` | Free every handle |

See [Built-in Widgets > image](built-in-widgets.md#display) for the
path-based vs handle-based trade-offs.

### Pane grid

| Method | Purpose |
|---|---|
| `pane_split(grid_id, pane_id, axis, new_pane_id)` | Split a pane (`:horizontal` or `:vertical`) |
| `pane_close(grid_id, pane_id)` | Close a pane |
| `pane_swap(grid_id, pane_a, pane_b)` | Swap two panes |
| `pane_maximize(grid_id, pane_id)` | Maximize a pane |
| `pane_restore(grid_id)` | Restore all panes from maximized state |

### System queries

| Method | Purpose |
|---|---|
| `system_theme(tag)` | Query OS light/dark preference |
| `system_info(tag)` | Query system information |
| `tree_hash(tag)` | Query structural hash of the UI tree |
| `find_focused(tag)` | Query which widget has focus |

Results arrive as `Event::System[type:, tag:, value:]`.

### Accessibility

| Method | Purpose |
|---|---|
| `announce(text, politeness = :polite)` | Screen reader announcement |

`politeness` is `:polite` (queued behind any speech in progress) or
`:assertive` (interrupts). Use `:polite` for most toast-style
feedback; reserve `:assertive` for urgent context the user must
hear immediately.

### Font loading

| Method | Purpose |
|---|---|
| `load_font(family, data)` | Load a font at runtime from TTF/OTF bytes |

### Widget commands

| Method | Purpose |
|---|---|
| `widget_command(id, family, value = nil)` | Send a command to any widget by ID, family name, and optional payload |
| `widget_batch(commands)` | Send a batch of widget commands applied atomically |

`widget_command` is the mechanism for native widgets to receive
arbitrary operations. Each native widget declares its command
families in its Rust side; the family name is how the SDK reaches
them.

### Testing / headless

| Method | Purpose |
|---|---|
| `advance_frame(timestamp)` | Advance the animation clock deterministically |

See the [Testing reference](testing.md).

## Platform effects

All effect methods live in `Plushie::Effect`. Each takes a symbol
**tag** as its first argument and returns a `Command::Cmd`. Results
arrive as `Event::Effect[tag:, result:]` in `update`. The `result`
is a typed `Event::Effect::Result` class (see the
[Events reference](events.md#event-effect)).

### File dialogs

| Method | Purpose |
|---|---|
| `file_open(tag, **opts)` | Single file picker |
| `file_open_multiple(tag, **opts)` | Multi-file picker |
| `file_save(tag, **opts)` | Save dialog |
| `directory_select(tag, **opts)` | Single directory picker |
| `directory_select_multiple(tag, **opts)` | Multi-directory picker |

Common options: `title`, `filters` (array of `[label, pattern]`
pairs), `default_path`.

```ruby
case event
in Event::Widget[type: :click, id: "open"]
  [model, Plushie::Effect.file_open(:import, title: "Import", filters: [["Ruby", "*.rb"]])]

in Event::Effect[tag: :import, result: Event::Effect::Result::FileOpened[path:]]
  load_file(model, path)

in Event::Effect[tag: :import, result: Event::Effect::Result::Cancelled[]]
  model
end
```

### Clipboard

| Method | Purpose |
|---|---|
| `clipboard_read(tag)` | Read plain text |
| `clipboard_write(tag, text)` | Write plain text |
| `clipboard_read_html(tag)` | Read HTML content |
| `clipboard_write_html(tag, html, alt_text: nil)` | Write HTML content (with optional plain-text alternative) |
| `clipboard_clear(tag)` | Clear clipboard |
| `clipboard_read_primary(tag)` | Read primary selection (Linux) |
| `clipboard_write_primary(tag, text)` | Write primary selection (Linux) |

### Notifications

```ruby
Plushie::Effect.notification(:saved, "Exported", "File saved to #{path}")
```

Options: `icon`, `timeout` (auto-dismiss ms), `urgency` (`:low`,
`:normal`, `:critical`), `sound`.

## Async mechanics

- **One task per tag.** Calling `task` or `stream` with a tag that is
  already in-flight kills the previous task. Use unique tags for
  concurrent work.
- **Nonce-based stale rejection.** Each task gets a nonce at
  creation. Results from killed tasks carry a stale nonce and are
  silently discarded.
- **Crashes become errors.** If the task raises, the runtime reports
  the exception class and message on the `Event::Async` result.
- **Renderer restarts.** In-flight async tasks run in Ruby, not the
  renderer, so they survive a renderer restart. Results may be stale
  if the work depended on renderer state.

### Streaming

```ruby
cmd = Plushie::Command.stream(->(emit) {
  fetch_chunks.each_with_index do |chunk, i|
    emit.call(progress: i, value: chunk)
  end
  :done
}, :import)
```

Each `emit.call(...)` delivers `Event::Stream[tag: :import, value: ...]`.
The function's final return value is delivered as
`Event::Async[tag: :import, result: :done]`. Wrap in a tagged tuple
yourself if you want a consistent ok/error shape.

## Effect lifecycle

- **Tag-based matching.** Every effect takes a symbol tag. The tag
  returns in `Event::Effect[tag:]` for direct pattern matching.
- **One effect per tag.** Starting a new effect with a tag that has
  a pending request discards the previous one.
- **Default timeouts:** file dialogs 120s, clipboard and
  notifications 5s. Override with the `timeout:` option.
- **Timeout delivery.** `Event::Effect::Result::Timeout[]`.
- **User cancellation.** Dismissing a dialog delivers
  `Event::Effect::Result::Cancelled[]` (a normal outcome, not an
  error).
- **Unsupported platforms.** Missing platform support delivers
  `Event::Effect::Result::Unsupported[]`.
- **Effect stubs.** Tests register canned results per effect kind
  via the renderer's effect stub API. See the
  [Testing reference](testing.md).

## DIY patterns

The runtime is a plain object. For integrations that don't fit the
command model, spin up a thread yourself and feed results back
through `Command.dispatch`:

```ruby
def update(model, event)
  case event
  in Event::Widget[type: :click, id: "fetch"]
    cmd = Plushie::Command.task(-> { MyApp::HTTP.get("/api/data") }, :fetched)
    [model, cmd]

  in Event::Async[tag: :fetched, result: data]
    model.with(data: data)
  end
end
```

This is the preferred way to integrate with existing Ruby
infrastructure (HTTP clients, ActiveRecord, PubSub). The trade-off
of dropping straight to raw threads without `task` is that you lose
tag-based cancellation and stale-result rejection.

## See also

- [Events reference](events.md) - the event classes commands
  produce, including `Event::Effect::Result` variants
- [App Lifecycle reference](app-lifecycle.md) - return value
  validation and the update cycle
- [Subscriptions reference](subscriptions.md) - recurring events
  and the `every` subscription for timer loops
- [Testing reference](testing.md) - effect stubs and frame
  advancement
- [Async and Effects guide](../guides/11-async-and-effects.md) -
  effects, async, streaming, and multi-window patterns
