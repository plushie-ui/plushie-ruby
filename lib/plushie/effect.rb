# frozen_string_literal: true

module Plushie
  # Native platform effect requests.
  #
  # Effects are asynchronous I/O operations handled by the renderer:
  # file dialogs, clipboard access, notifications. Each method takes
  # a symbol tag as its first argument and returns a Command. The tag
  # flows through to the Effect event for clean pattern matching.
  #
  # Only one effect per tag can be in flight at a time. Starting a new
  # effect with a tag that already has a pending request discards the
  # previous one.
  #
  # @example
  #   def update(model, event)
  #     case event
  #     in Event::Widget[type: :click, id: "open"]
  #       [model, Effect.file_open(:import, title: "Pick a file")]
  #     in Event::Effect[tag: :import, result: [:ok, result]]
  #       model.with(file: result["path"])
  #     in Event::Effect[tag: :import, result: :cancelled]
  #       model
  #     end
  #   end
  module Effect
    # Default timeout for file dialog effects (milliseconds).
    TIMEOUT_FILE = 120_000
    # Default timeout for clipboard effects (milliseconds).
    TIMEOUT_CLIPBOARD = 5_000
    # Default timeout for notification effects (milliseconds).
    TIMEOUT_NOTIFICATION = 5_000

    module_function

    # Open-file dialog.
    # @param tag [Symbol] identifies this effect in the result event
    # @return [Command::Cmd]
    def file_open(tag, **opts) = request(tag, :file_open, **opts)

    # Multi-file open dialog.
    # @param tag [Symbol]
    # @return [Command::Cmd]
    def file_open_multiple(tag, **opts) = request(tag, :file_open_multiple, **opts)

    # Save-file dialog.
    # @param tag [Symbol]
    # @return [Command::Cmd]
    def file_save(tag, **opts) = request(tag, :file_save, **opts)

    # Directory picker.
    # @param tag [Symbol]
    # @return [Command::Cmd]
    def directory_select(tag, **opts) = request(tag, :directory_select, **opts)

    # Multi-directory picker.
    # @param tag [Symbol]
    # @return [Command::Cmd]
    def directory_select_multiple(tag, **opts) = request(tag, :directory_select_multiple, **opts)

    # Read clipboard text.
    # @param tag [Symbol]
    # @return [Command::Cmd]
    def clipboard_read(tag) = request(tag, :clipboard_read)

    # Write text to clipboard.
    # @param tag [Symbol]
    # @param text [String]
    # @return [Command::Cmd]
    def clipboard_write(tag, text) = request(tag, :clipboard_write, text: text)

    # Read HTML from clipboard.
    # @param tag [Symbol]
    # @return [Command::Cmd]
    def clipboard_read_html(tag) = request(tag, :clipboard_read_html)

    # Write HTML to clipboard.
    # @param tag [Symbol]
    # @param html [String]
    # @param alt_text [String, nil] plain text fallback
    # @return [Command::Cmd]
    def clipboard_write_html(tag, html, alt_text: nil)
      opts = {html: html}
      opts[:alt_text] = alt_text if alt_text
      request(tag, :clipboard_write_html, **opts)
    end

    # Clear the clipboard.
    # @param tag [Symbol]
    # @return [Command::Cmd]
    def clipboard_clear(tag) = request(tag, :clipboard_clear)

    # Read primary clipboard (middle-click paste on Linux).
    # @param tag [Symbol]
    # @return [Command::Cmd]
    def clipboard_read_primary(tag) = request(tag, :clipboard_read_primary)

    # Write to primary clipboard.
    # @param tag [Symbol]
    # @param text [String]
    # @return [Command::Cmd]
    def clipboard_write_primary(tag, text) = request(tag, :clipboard_write_primary, text: text)

    # Show an OS notification.
    #
    # On macOS, notifications may require the app to be bundled (.app)
    # or have notification entitlements to display.
    #
    # @param tag [Symbol]
    # @param title [String]
    # @param body [String]
    # @return [Command::Cmd]
    def notification(tag, title, body, **opts)
      payload = {title: title, body: body}
      payload[:icon] = opts[:icon] if opts[:icon]
      payload[:timeout] = opts[:timeout] if opts[:timeout]
      payload[:urgency] = opts[:urgency].to_s if opts[:urgency]
      payload[:sound] = opts[:sound] if opts[:sound]
      request(tag, :notification, **payload)
    end

    # Generic effect request.
    #
    # @param tag [Symbol] identifies this effect in the result event
    # @param kind [Symbol] effect kind
    # @param opts [Hash] effect-specific parameters
    # @return [Command::Cmd]
    def request(tag, kind, **opts)
      id = generate_id
      custom_timeout = opts.delete(:timeout)
      Command::Cmd.new(
        type: :effect,
        payload: {id: id, tag: tag, kind: kind.to_s, opts: opts, timeout: custom_timeout}
      )
    end

    # Returns the default timeout for the given effect kind.
    # @param kind [String, Symbol]
    # @return [Integer]
    def default_timeout(kind)
      case kind.to_s
      when "file_open", "file_open_multiple", "file_save",
        "directory_select", "directory_select_multiple"
        TIMEOUT_FILE
      when "clipboard_read", "clipboard_write", "clipboard_read_html",
        "clipboard_write_html", "clipboard_clear",
        "clipboard_read_primary", "clipboard_write_primary"
        TIMEOUT_CLIPBOARD
      when "notification"
        TIMEOUT_NOTIFICATION
      else
        30_000
      end
    end

    # Monotonic counter backing `generate_id`. Matches the format
    # used by the other host SDKs so log / debug output is
    # comparable across implementations.
    @counter = 0
    @counter_mutex = Mutex.new

    # @return [String] unique wire correlation ID
    def generate_id
      @counter_mutex.synchronize do
        @counter += 1
        "ef_#{@counter}"
      end
    end
  end
end
