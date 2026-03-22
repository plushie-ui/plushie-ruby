# frozen_string_literal: true

module Plushie
  # Event types delivered to update/2.
  #
  # All event types are immutable Data classes. Pattern match on them
  # in your update method:
  #
  #   case event
  #   in Event::Widget[type: :click, id: "save"]
  #     model.with(saved: true)
  #   in Event::Key[type: :press, key: "s", modifiers: { command: true }]
  #     [model, Command.async(-> { save(model) }, :save_result)]
  #   end
  #
  module Event
    # Widget interaction events (clicks, input, toggles, etc.)
    Widget = Data.define(:type, :id, :value, :scope, :data) do
      def initialize(type:, id:, value: nil, scope: [], data: nil)
        super
      end
    end

    # Keyboard events
    Key = Data.define(:type, :key, :modified_key, :physical_key,
      :location, :modifiers, :text, :repeat, :captured) do
      def initialize(type:, key:, modified_key: nil, physical_key: nil,
        location: :standard, modifiers: {}, text: nil, repeat: false, captured: false)
        super
      end
    end

    # Mouse events (global, via subscription)
    Mouse = Data.define(:type, :x, :y, :button, :delta_x, :delta_y, :unit, :captured) do
      def initialize(type:, x: nil, y: nil, button: nil,
        delta_x: nil, delta_y: nil, unit: nil, captured: false)
        super
      end
    end

    # Touch events
    Touch = Data.define(:type, :finger_id, :x, :y, :captured) do
      def initialize(type:, finger_id: nil, x: nil, y: nil, captured: false)
        super
      end
    end

    # IME (Input Method Editor) events
    Ime = Data.define(:type, :id, :scope, :text, :cursor, :captured) do
      def initialize(type:, id: nil, scope: [], text: nil, cursor: nil, captured: false)
        super
      end
    end

    # Window lifecycle events
    Window = Data.define(:type, :window_id, :x, :y, :width, :height,
      :scale_factor, :path) do
      def initialize(type:, window_id: nil, x: nil, y: nil,
        width: nil, height: nil, scale_factor: nil, path: nil)
        super
      end
    end

    # Canvas interaction events
    Canvas = Data.define(:type, :id, :x, :y, :button, :delta_x, :delta_y, :scope) do
      def initialize(type:, id:, x: nil, y: nil, button: nil,
        delta_x: nil, delta_y: nil, scope: [])
        super
      end
    end

    # Mouse area events
    MouseArea = Data.define(:type, :id, :x, :y, :delta_x, :delta_y, :scope) do
      def initialize(type:, id:, x: nil, y: nil, delta_x: nil, delta_y: nil, scope: [])
        super
      end
    end

    # Pane grid events
    Pane = Data.define(:type, :id, :pane, :target, :split, :ratio, :scope,
      :action, :region, :edge) do
      def initialize(type:, id:, pane: nil, target: nil, split: nil, ratio: nil,
        scope: [], action: nil, region: nil, edge: nil)
        super
      end
    end

    # Sensor events (size detection)
    Sensor = Data.define(:type, :id, :width, :height, :scope) do
      def initialize(type:, id:, width: nil, height: nil, scope: [])
        super
      end
    end

    # Modifier key state changes
    Modifiers = Data.define(:modifiers, :captured) do
      def initialize(modifiers:, captured: false)
        super
      end
    end

    # Effect (platform operation) results
    Effect = Data.define(:request_id, :result)

    # System events (theme changes, animation frames)
    System = Data.define(:type, :tag, :data) do
      def initialize(type:, tag: nil, data: nil)
        super
      end
    end

    # Timer events (from Subscription.every)
    Timer = Data.define(:tag, :timestamp)

    # Async command results
    Async = Data.define(:tag, :result)

    # Stream command chunks
    Stream = Data.define(:tag, :value)

    # Reconstruct the full scoped path as a forward-order string.
    #
    #   Event.target(widget_event) # => "sidebar/form/save"
    #
    def self.target(event)
      return event.id if event.scope.empty?
      (event.scope.reverse + [event.id]).join("/")
    end
  end
end
