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
require_relative "plushie/widget/toggler"
require_relative "plushie/widget/vertical_slider"
require_relative "plushie/widget/pick_list"
require_relative "plushie/widget/combo_box"
require_relative "plushie/widget/radio"
require_relative "plushie/widget/progress_bar"
require_relative "plushie/widget/text_editor"
require_relative "plushie/widget/svg"
require_relative "plushie/widget/markdown"
require_relative "plushie/widget/qr_code"
require_relative "plushie/widget/rich_text"
require_relative "plushie/widget/rule"
require_relative "plushie/widget/space"
require_relative "plushie/widget/tooltip"
require_relative "plushie/widget/grid"
require_relative "plushie/widget/keyed_column"
require_relative "plushie/widget/pin"
require_relative "plushie/widget/floating"
require_relative "plushie/widget/mouse_area"
require_relative "plushie/widget/sensor"
require_relative "plushie/widget/themer"
require_relative "plushie/widget/pane_grid"
require_relative "plushie/widget/overlay"
require_relative "plushie/widget/responsive"
require_relative "plushie/widget/stack"

# Canvas shapes
require_relative "plushie/canvas/shape"

# Extension system
require_relative "plushie/extension"
require_relative "plushie/canvas_widget"

require_relative "plushie/ui"
require_relative "plushie/app"
require_relative "plushie/tree"
require_relative "plushie/protocol"
require_relative "plushie/transport/framing"
require_relative "plushie/thread_pool"
require_relative "plushie/renderer_env"
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

# Native desktop GUI framework for Ruby, powered by iced.
#
# Plushie implements the Elm architecture (init/update/view) for building
# desktop applications. The rendering is handled by a precompiled binary
# that communicates with Ruby over stdin/stdout using MessagePack.
#
# @example Run an app
#   Plushie.run(Counter)
#
# @example Start in background
#   handle = Plushie.start(Counter)
#   handle.stop
#
# @see Plushie::App
# @see Plushie::Runtime
module Plushie
  # Base error class for all Plushie exceptions.
  class Error < StandardError; end

  # Global configuration for the Plushie SDK.
  #
  # @example Basic setup
  #   Plushie.configure do |config|
  #     config.binary_path = "/opt/plushie/bin/plushie"
  #     config.source_path = "~/projects/plushie"
  #   end
  #
  # @example With extensions
  #   Plushie.configure do |config|
  #     config.extensions = [MyGauge, MyChart]
  #     config.build_name = "my-dashboard-plushie"
  #     config.extension_config = {
  #       "sparkline" => {"max_samples" => 1000}
  #     }
  #   end
  #
  class Configuration
    # Explicit path to the plushie binary. Overrides all resolution.
    # Equivalent to PLUSHIE_BINARY_PATH env var.
    # @return [String, nil]
    attr_accessor :binary_path

    # Path to the plushie Rust source checkout. Used by `rake plushie:build`.
    # Equivalent to PLUSHIE_SOURCE_PATH env var.
    # @return [String, nil]
    attr_accessor :source_path

    # Custom binary name for extension builds.
    # Defaults to "plushie-custom". Used as the Cargo binary target name
    # and the installed filename.
    # @return [String]
    attr_accessor :build_name

    # Extension classes to include in custom builds.
    # @return [Array<Class>]
    attr_accessor :extensions

    # Runtime configuration map passed to widget extensions via
    # the Settings wire message. Keyed by extension widget type.
    # @return [Hash]
    attr_accessor :extension_config

    # Test backend (:mock, :headless, :windowed).
    # Equivalent to PLUSHIE_TEST_BACKEND env var.
    # @return [Symbol, nil]
    attr_accessor :test_backend

    # Which artifacts to install with download/build tasks.
    # Default: +[:bin]+. Set to +[:bin, :wasm]+ for projects that
    # need both the native binary and the WASM renderer.
    # @return [Array<Symbol>]
    attr_accessor :artifacts

    # Override destination path for the native binary.
    # Used by +rake plushie:download+ and +rake plushie:build+.
    # Env var +PLUSHIE_BIN_FILE+ takes precedence.
    # @return [String, nil]
    attr_accessor :bin_file

    # Override output directory for WASM renderer files.
    # Used by +rake plushie:download+.
    # Env var +PLUSHIE_WASM_DIR+ takes precedence.
    # @return [String, nil]
    attr_accessor :wasm_dir

    def initialize
      @binary_path = nil
      @source_path = nil
      @build_name = "plushie-custom"
      @extensions = []
      @extension_config = {}
      @test_backend = nil
      @artifacts = [:bin]
      @bin_file = nil
      @wasm_dir = nil
    end
  end

  @configuration = Configuration.new

  # @return [Configuration] the global configuration
  def self.configuration
    @configuration
  end

  # Configure the SDK via a block.
  #
  # @yield [Configuration]
  def self.configure
    yield @configuration
  end

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
