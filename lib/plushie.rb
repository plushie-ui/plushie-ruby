# frozen_string_literal: true

require_relative "plushie/version"
require_relative "plushie/model"
require_relative "plushie/node"
require_relative "plushie/event"
require_relative "plushie/command"
require_relative "plushie/subscription"
require_relative "plushie/effects"

# Property types
require_relative "plushie/type/alignment"
require_relative "plushie/type/anchor"
require_relative "plushie/type/color"
require_relative "plushie/type/content_fit"
require_relative "plushie/type/direction"
require_relative "plushie/type/filter_method"
require_relative "plushie/type/gradient"
require_relative "plushie/type/length"
require_relative "plushie/type/padding"
require_relative "plushie/type/position"
require_relative "plushie/type/shaping"
require_relative "plushie/type/theme"
require_relative "plushie/type/wrapping"
require_relative "plushie/type/border"
require_relative "plushie/type/shadow"
require_relative "plushie/type/font"
require_relative "plushie/type/style_map"
require_relative "plushie/type/a11y"

# Encoding and DSL
require_relative "plushie/encode"
require_relative "plushie/dsl/buildable"

# Widget builder modules (Layer 2 API)
require_relative "plushie/widget/build"
require_relative "plushie/widget/button"
require_relative "plushie/widget/text"
require_relative "plushie/widget/text_input"
require_relative "plushie/widget/column"
require_relative "plushie/widget/row"
require_relative "plushie/widget/container"
require_relative "plushie/widget/window"
require_relative "plushie/widget/checkbox"
require_relative "plushie/widget/slider"
require_relative "plushie/widget/image"
require_relative "plushie/widget/scrollable"
require_relative "plushie/widget/canvas"
require_relative "plushie/widget/table"

# Canvas shapes
require_relative "plushie/canvas/shape"

# Extension system
require_relative "plushie/extension"

require_relative "plushie/ui"
require_relative "plushie/app"
require_relative "plushie/tree"
require_relative "plushie/protocol"
require_relative "plushie/transport/framing"
require_relative "plushie/thread_pool"
require_relative "plushie/connection"
require_relative "plushie/bridge"
require_relative "plushie/runtime"
require_relative "plushie/binary"

# State helpers
require_relative "plushie/animation"
require_relative "plushie/route"
require_relative "plushie/selection"
require_relative "plushie/undo"
require_relative "plushie/data"
require_relative "plushie/state"
require_relative "plushie/key_modifiers"
require_relative "plushie/dev_server"

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
