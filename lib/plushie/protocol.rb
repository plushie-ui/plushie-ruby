# frozen_string_literal: true

require "json"

module Plushie
  # Wire protocol between the Ruby runtime and the Rust renderer.
  #
  # Supports two formats:
  # - :json    -- newline-delimited JSON (debugging/observability)
  # - :msgpack -- MessagePack with 4-byte length prefix (default, production)
  #
  module Protocol
    PROTOCOL_VERSION = 1

    autoload :Encode, "plushie/protocol/encode"
    autoload :Decode, "plushie/protocol/decode"
  end
end
