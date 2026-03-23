# frozen_string_literal: true

require "securerandom"

module Plushie
  # Native platform effect requests.
  #
  # Effects are asynchronous I/O operations handled by the renderer:
  # file dialogs, clipboard access, notifications. Each method returns
  # a Command. Results arrive as Event::Effect in update.
  #
  # @example
  #   def update(model, event)
  #     case event
  #     in Event::Widget[type: :click, id: "open"]
  #       [model, Effects.file_open(title: "Pick a file")]
  #     in Event::Effect[result: [:ok, result]]
  #       model.with(file: result["path"])
  #     in Event::Effect[result: :cancelled]
  #       model
  #     end
  #   end
  #
  # @see ~/projects/plushie-renderer/docs/protocol.md "Effect"
  # @see ~/projects/toddy-elixir/lib/plushie/effects.ex
  module Effects
    # Default timeouts per effect kind (milliseconds).
    TIMEOUT_FILE = 120_000
    # Default timeout for clipboard operations.
    # @api private
    TIMEOUT_CLIPBOARD = 5_000
    # Default timeout for notification operations.
    # @api private
    TIMEOUT_NOTIFICATION = 5_000

    module_function

    # -------------------------------------------------------------------
    # File dialogs
    # -------------------------------------------------------------------

    # Open-file dialog. Returns a Command.
    # @option opts [String] :title dialog title
    # @option opts [String, nil] :directory starting directory
    # @option opts [Array, nil] :filters filter pairs: [["Label", "*.ext"]]
    # @option opts [Integer, nil] :timeout override default timeout
    # @return [Command::Cmd]
    def file_open(**opts) = request(:file_open, **opts)

    # Multi-file open dialog.
    # @return [Command::Cmd]
    def file_open_multiple(**opts) = request(:file_open_multiple, **opts)

    # Save-file dialog.
    # @option opts [String, nil] :default_name suggested filename
    # @return [Command::Cmd]
    def file_save(**opts) = request(:file_save, **opts)

    # Directory picker.
    # @return [Command::Cmd]
    def directory_select(**opts) = request(:directory_select, **opts)

    # Multi-directory picker.
    # @return [Command::Cmd]
    def directory_select_multiple(**opts) = request(:directory_select_multiple, **opts)

    # -------------------------------------------------------------------
    # Clipboard
    # -------------------------------------------------------------------

    # Read clipboard text.
    # @return [Command::Cmd]
    def clipboard_read = request(:clipboard_read)

    # Write text to clipboard.
    # @param text [String]
    # @return [Command::Cmd]
    def clipboard_write(text) = request(:clipboard_write, text: text)

    # Read HTML from clipboard.
    # @return [Command::Cmd]
    def clipboard_read_html = request(:clipboard_read_html)

    # Write HTML to clipboard.
    # @param html [String]
    # @param alt_text [String, nil] plain text fallback
    # @return [Command::Cmd]
    def clipboard_write_html(html, alt_text: nil)
      opts = {html: html}
      opts[:alt_text] = alt_text if alt_text
      request(:clipboard_write_html, **opts)
    end

    # Clear the clipboard.
    # @return [Command::Cmd]
    def clipboard_clear = request(:clipboard_clear)

    # Read primary clipboard (middle-click paste on Linux).
    # @return [Command::Cmd]
    def clipboard_read_primary = request(:clipboard_read_primary)

    # Write to primary clipboard.
    # @param text [String]
    # @return [Command::Cmd]
    def clipboard_write_primary(text) = request(:clipboard_write_primary, text: text)

    # -------------------------------------------------------------------
    # Notifications
    # -------------------------------------------------------------------

    # Show an OS notification.
    # @param title [String]
    # @param body [String]
    # @option opts [String, nil] :icon icon name
    # @option opts [Integer, nil] :timeout auto-dismiss in ms
    # @option opts [Symbol, nil] :urgency :low, :normal, :critical
    # @option opts [String, nil] :sound sound theme name
    # @return [Command::Cmd]
    def notification(title, body, **opts)
      payload = {title: title, body: body}
      payload[:icon] = opts[:icon] if opts[:icon]
      payload[:timeout] = opts[:timeout] if opts[:timeout]
      payload[:urgency] = opts[:urgency].to_s if opts[:urgency]
      payload[:sound] = opts[:sound] if opts[:sound]
      request(:notification, **payload)
    end

    # -------------------------------------------------------------------
    # Internals
    # -------------------------------------------------------------------

    # Generic effect request. Returns a Command with an auto-generated ID.
    # @param kind [Symbol] effect kind
    # @param opts [Hash] effect-specific parameters
    # @return [Command::Cmd]
    def request(kind, **opts)
      id = generate_id
      custom_timeout = opts.delete(:timeout)
      Command::Cmd.new(
        type: :effect,
        payload: {id: id, kind: kind.to_s, opts: opts, timeout: custom_timeout}
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

    # @return [String] unique monotonic effect ID
    def generate_id
      "ef_#{SecureRandom.hex(6)}"
    end
  end
end
