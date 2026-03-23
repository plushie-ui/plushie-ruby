# frozen_string_literal: true

module Plushie
  # Builds a filtered environment for the renderer subprocess.
  #
  # The renderer is spawned as a child process via Open3.popen2. By
  # default, child processes inherit the parent's full environment,
  # which can leak sensitive variables (API keys, database credentials,
  # tokens) to the renderer. This is especially concerning for remote
  # rendering where the host runs on a production server.
  #
  # This module builds an explicit environment from a whitelist of
  # variables the renderer actually needs: display server, GPU/Vulkan,
  # fonts, locale, accessibility, and Rust diagnostics.
  #
  # @example
  #   env = RendererEnv.build(log_level: :debug)
  #   Open3.popen2(env, "plushie", "--mock")
  #
  # @see ~/projects/toddy-elixir/lib/plushie/renderer_env.ex
  module RendererEnv
    # Exact environment variable names to pass through.
    ALLOWED_VARS = %w[
      DISPLAY
      WAYLAND_DISPLAY
      WAYLAND_SOCKET
      WINIT_UNIX_BACKEND
      XDG_RUNTIME_DIR
      XDG_DATA_DIRS
      XDG_DATA_HOME
      PATH
      LD_LIBRARY_PATH
      DYLD_LIBRARY_PATH
      DYLD_FALLBACK_LIBRARY_PATH
      LANG
      LANGUAGE
      DBUS_SESSION_BUS_ADDRESS
      GTK_MODULES
      NO_AT_BRIDGE
      WGPU_BACKEND
      RUST_LOG
      RUST_BACKTRACE
      HOME
      USER
    ].freeze

    # Environment variable prefixes to pass through.
    # Any var starting with one of these prefixes is allowed.
    ALLOWED_PREFIXES = %w[
      LC_
      MESA_
      LIBGL_
      __GLX_
      VK_
      GALLIUM_
      AT_SPI_
      FONTCONFIG_
    ].freeze

    # Rust log level mapping from plushie log level symbols.
    RUST_LOG_LEVELS = {
      off: "off",
      error: "plushie=error",
      warning: "plushie=warn",
      warn: "plushie=warn",
      info: "plushie=info",
      debug: "plushie=debug",
      trace: "plushie=trace"
    }.freeze

    module_function

    # Build a filtered environment hash for Open3.popen2.
    #
    # Returns a Hash where:
    # - Whitelisted vars map to their current values
    # - Non-whitelisted vars map to nil (which unsets them)
    # - RUST_LOG is set based on the log_level parameter
    #
    # @param log_level [Symbol] :off, :error, :warning, :info, :debug
    # @return [Hash{String => String, nil}] environment for subprocess
    def build(log_level: :error)
      env = {}

      # Partition current environment into allowed and disallowed
      ENV.each do |key, value|
        env[key] = if allowed?(key)
          value
        else
          nil # nil unsets the var in the child
        end
      end

      # Set RUST_LOG based on configured level (overrides inherited value)
      rust_log = RUST_LOG_LEVELS.fetch(log_level, "plushie=error")
      env["RUST_LOG"] = rust_log

      # Ensure RUST_BACKTRACE is set for diagnostics
      env["RUST_BACKTRACE"] ||= "1"

      env
    end

    # Check if a variable name is in the whitelist.
    #
    # @param name [String] environment variable name
    # @return [Boolean]
    def allowed?(name)
      return true if ALLOWED_VARS.include?(name)
      ALLOWED_PREFIXES.any? { |prefix| name.start_with?(prefix) }
    end
  end
end
