# frozen_string_literal: true

require_relative "plushie/version"
require_relative "plushie/model"
require_relative "plushie/node"
require_relative "plushie/event"
require_relative "plushie/command"
require_relative "plushie/subscription"
require_relative "plushie/ui"
require_relative "plushie/app"
require_relative "plushie/tree"
require_relative "plushie/protocol"
require_relative "plushie/bridge"
require_relative "plushie/runtime"
require_relative "plushie/binary"

module Plushie
  class Error < StandardError; end

  # Start a Plushie app and block until it exits.
  #
  #   Plushie.run(Counter)
  #   Plushie.run(Counter, transport: :spawn, format: :msgpack)
  #
  def self.run(app_class, **opts)
    app = app_class.new
    runtime = Runtime.new(app:, **opts)
    runtime.run
  end

  # Start a Plushie app in the background. Returns a handle
  # that can be stopped later.
  #
  #   handle = Plushie.start(Counter)
  #   handle.stop
  #
  def self.start(app_class, **opts)
    app = app_class.new
    runtime = Runtime.new(app:, **opts)
    runtime.start
    runtime
  end
end
