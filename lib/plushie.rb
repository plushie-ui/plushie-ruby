# frozen_string_literal: true

require_relative "plushie/version"
require_relative "plushie/model"
require_relative "plushie/node"
require_relative "plushie/event"
require_relative "plushie/command"
require_relative "plushie/subscription"
require_relative "plushie/effect"

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
require_relative "plushie/type/line_height"

# Encoding and DSL
require_relative "plushie/encode"
require_relative "plushie/dsl/buildable"

# Widget system and builder modules
require_relative "plushie/widget/build"
require_relative "plushie/widget"
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
require_relative "plushie/widget/pointer_area"
require_relative "plushie/widget/sensor"
require_relative "plushie/widget/themer"
require_relative "plushie/widget/pane_grid"
require_relative "plushie/widget/overlay"
require_relative "plushie/widget/responsive"
require_relative "plushie/widget/stack"

# Canvas shapes
require_relative "plushie/canvas/shape"

# Canvas widget extension system
require_relative "plushie/canvas_widget"

require_relative "plushie/ui"
require_relative "plushie/app"
require_relative "plushie/tree"
require_relative "plushie/protocol"
require_relative "plushie/transport/framing"
require_relative "plushie/transport/socket_adapter"
require_relative "plushie/thread_pool"
require_relative "plushie/bounded_queue"
require_relative "plushie/renderer_env"
require_relative "plushie/connection"
require_relative "plushie/bridge"
require_relative "plushie/runtime"
require_relative "plushie/binary"
require_relative "plushie/cargo_plushie"

# State helpers
require_relative "plushie/animation"
require_relative "plushie/route"
require_relative "plushie/selection"
require_relative "plushie/undo"
require_relative "plushie/data"
require_relative "plushie/state"
require_relative "plushie/key_modifiers"
require_relative "plushie/dev_server"
require_relative "plushie/widget_set"
require_relative "plushie/renderer_exit"

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

  # Raised when the renderer's advertised protocol version differs
  # from the version the SDK was built against. Carries both versions
  # so callers can decide retry vs abort without string parsing.
  class ProtocolVersionMismatchError < Error
    # @return [Integer] protocol version this SDK was built for.
    attr_reader :expected
    # @return [Integer, nil] protocol version the renderer advertised.
    attr_reader :got

    def initialize(expected:, got:)
      super("protocol version mismatch: expected #{expected}, got #{got.inspect}")
      @expected = expected
      @got = got
    end
  end

  # Global configuration for the Plushie SDK.
  #
  # @example Basic setup
  #   Plushie.configure do |config|
  #     config.binary_path = "/opt/plushie/bin/plushie"
  #     config.source_path = "~/projects/plushie"
  #   end
  #
  # @example With custom widgets
  #   Plushie.configure do |config|
  #     config.widgets = [MyGauge, MyChart]
  #     config.build_name = "my-dashboard-plushie"
  #     config.widget_config = {
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
    # Equivalent to PLUSHIE_RUST_SOURCE_PATH env var.
    # @return [String, nil]
    attr_accessor :source_path

    # Custom binary name for native widget builds.
    # Defaults to "plushie-custom". Used as the Cargo binary target name
    # and the installed filename.
    # @return [String]
    attr_accessor :build_name

    # Widget classes to include in custom builds.
    # @return [Array<Class>]
    attr_accessor :widgets

    # Runtime configuration map passed to native widgets via
    # the Settings wire message. Keyed by widget type.
    # @return [Hash]
    attr_accessor :widget_config

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

    # Enable renderer-side prop validation. When true, the renderer
    # emits diagnostic events for unknown or invalid props.
    # @return [Boolean]
    attr_accessor :validate_props

    def initialize
      @binary_path = nil
      @source_path = nil
      @build_name = "plushie-custom"
      @widgets = []
      @widget_config = {}
      @test_backend = nil
      @artifacts = [:bin]
      @bin_file = nil
      @wasm_dir = nil
      @validate_props = false
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

  # Run an app from a standalone entry point and block until it exits.
  #
  # Uses PLUSHIE_SOCKET when present. Otherwise starts the renderer as a
  # child process through normal binary resolution, including
  # PLUSHIE_BINARY_PATH.
  #
  # Token resolution precedence:
  #   1. Explicit +token:+ keyword argument
  #   2. +PLUSHIE_TOKEN+ environment variable
  #   3. Single JSON line read from stdin with a 1-second timeout
  #
  # When a socket is present but no token can be resolved, raises with
  # a clear error message rather than silently connecting without one.
  def self.connect(app_class, socket: ENV["PLUSHIE_SOCKET"], token: ENV["PLUSHIE_TOKEN"], format: :msgpack)
    if socket.nil? || socket.empty?
      return run(app_class, token: token, format: format)
    end

    if token.nil? || token.empty?
      token = read_token_from_stdin
      if token.nil?
        raise Error, "renderer-parent token not provided: pass token, set PLUSHIE_TOKEN, or write a JSON token line on stdin"
      end
    end

    adapter = Transport::SocketAdapter.connect(socket)
    run(app_class, transport: [:iostream, adapter], token: token, format: format)
  end

  # Try to read a JSON token line from stdin within +timeout+ seconds.
  #
  # Returns the token string on success, or +nil+ if stdin is closed or
  # the timeout expires with no data.
  #
  # Raises +Error+ if data arrives but cannot be parsed as a JSON object
  # with a "token" string key.
  def self.read_token_from_stdin(timeout: 1.0)
    require "json"
    ready = IO.select([$stdin], nil, nil, timeout)
    return nil if ready.nil?

    line = $stdin.gets
    return nil if line.nil? || line.strip.empty?

    begin
      obj = JSON.parse(line.strip)
    rescue JSON::ParserError
      raise Error, "renderer-parent token stdin must be JSON object with 'token' string"
    end

    unless obj.is_a?(Hash) && obj["token"].is_a?(String)
      raise Error, "renderer-parent token stdin must be JSON object with 'token' string"
    end

    obj["token"]
  end
end
