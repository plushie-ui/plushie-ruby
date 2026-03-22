# frozen_string_literal: true

module Plushie
  # Behaviour module for Plushie apps following the Elm architecture.
  #
  # Include this module and implement init, update, and view:
  #
  #   class Counter
  #     include Plushie::App
  #
  #     Model = Plushie::Model.define(:count)
  #
  #     def init(_opts) = Model.new(count: 0)
  #
  #     def update(model, event)
  #       case event
  #       in Event::Widget[type: :click, id: "increment"]
  #         model.with(count: model.count + 1)
  #       else
  #         model
  #       end
  #     end
  #
  #     def view(model)
  #       window("main", title: "Counter") do
  #         column(padding: 16, spacing: 8) do
  #           text("count", "Count: #{model.count}")
  #           button("increment", "+")
  #         end
  #       end
  #     end
  #   end
  #
  module App
    def self.included(base)
      base.include(Plushie::UI)
      base.include(DefaultCallbacks)
      base.include(Aliases)
    end

    module Aliases
      Event = Plushie::Event
      Command = Plushie::Command
      Subscription = Plushie::Subscription
    end

    module DefaultCallbacks
      # Override to return active subscriptions based on the model.
      # Default: no subscriptions.
      def subscribe(_model) = []

      # Override to provide application-level settings to the renderer.
      # Default: empty (renderer defaults).
      def settings = {}

      # Override to configure default window properties.
      # Default: empty (renderer defaults).
      def window_config(_model) = {}

      # Override to handle renderer process exit.
      # Default: return model unchanged.
      def handle_renderer_exit(model, _reason) = model
    end
  end
end
