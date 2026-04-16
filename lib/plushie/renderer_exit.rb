# frozen_string_literal: true

module Plushie
  # Structured renderer exit reason passed to +handle_renderer_exit+.
  #
  # The runtime converts raw internal exit reasons (connection errors, exit
  # statuses, heartbeat timeouts) into a typed object before calling the
  # app callback. This normalizes implementation details into a stable
  # public API.
  #
  # Pattern matching works automatically via Data.define:
  #
  # @example Pattern matching in handle_renderer_exit
  #   def handle_renderer_exit(model, exit)
  #     case exit
  #     in Plushie::RendererExit[type: :heartbeat_timeout]
  #       model.with(status: :unresponsive)
  #     in Plushie::RendererExit[type: :crash]
  #       model.with(status: :crashed)
  #     else
  #       model
  #     end
  #   end
  #
  # @!attribute [r] type [Symbol] exit category (:crash, :connection_lost, :shutdown, :heartbeat_timeout)
  # @!attribute [r] message [String] human-readable description
  # @!attribute [r] details [Object, nil] additional context (exception, exit status, etc.)
  RENDERER_EXIT_TYPES = %i[crash connection_lost shutdown heartbeat_timeout].freeze

  RendererExit = Data.define(:type, :message, :details) do
    def initialize(type:, message:, details: nil)
      unless RENDERER_EXIT_TYPES.include?(type)
        raise ArgumentError,
          "invalid RendererExit type #{type.inspect}, " \
          "expected one of #{RENDERER_EXIT_TYPES.map(&:inspect).join(", ")}"
      end

      super
    end
  end
end
