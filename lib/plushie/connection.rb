# frozen_string_literal: true

module Plushie
  # Low-level protocol client for the plushie renderer.
  #
  # Manages a bidirectional pipe to the renderer binary, handles wire
  # framing, and provides thread-safe message sending. Messages are
  # read by a dedicated reader thread and dispatched to a callback
  # or queue.
  #
  # This layer is usable standalone for scripting and REPL exploration
  # without the full Elm architecture:
  #
  #   conn = Plushie::Connection.spawn(format: :json)
  #   conn.send_settings(antialiasing: true)
  #   hello = conn.read_message
  #   conn.send_snapshot(tree)
  #   conn.close
  #
  class Connection
    # TODO: implement
  end
end
