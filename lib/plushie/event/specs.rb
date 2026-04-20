# frozen_string_literal: true

module Plushie
  module Event
    # Canonical event specs for all built-in widget event types.
    #
    # Each spec describes the payload shape a WidgetEvent carries:
    #
    # - `carrier: :none` - no payload (just id/scope)
    # - `carrier: :value, value_type: :string` - scalar in value
    # - `carrier: :value, fields: {name: type}` - Hash in value with declared keys
    #
    # Used by the canvas widget emit path, protocol decoder, and as
    # the authoritative reference for what each event type carries.
    #
    # @example Query a spec
    #   Event::Specs.for(:press)
    #   # => {carrier: :value, fields: {x: :float, y: :float, ...}}
    #
    # @example Check if an event type exists
    #   Event::Specs.builtin?(:click) # => true
    #
    # @example Category predicates on Widget events
    #   event.pointer?  # true for press, release, move, scroll, ...
    #   event.keyboard? # true for key_press, key_release
    module Specs
      # Carrier for events with no payload (just id, type, scope).
      NONE = :none
      # Carrier for events with data in the Widget `value` field.
      VALUE = :value

      # -- Event categories (Sets for O(1) predicate lookups) -----------------

      # @return [Set<Symbol>]
      POINTER_TYPES = Set[:press, :release, :move, :scroll, :enter, :exit, :double_click].freeze
      # @return [Set<Symbol>]
      KEYBOARD_TYPES = Set[:key_press, :key_release].freeze
      # @return [Set<Symbol>]
      PANE_TYPES = Set[:pane_resized, :pane_dragged, :pane_clicked, :pane_focus_cycle].freeze
      # @return [Set<Symbol>]
      FOCUS_TYPES = Set[:focused, :blurred].freeze
      # @return [Set<Symbol>]
      DRAG_TYPES = Set[:drag, :drag_end].freeze

      # -- Built-in event specs -----------------------------------------------

      BUILTIN = {
        # Standard widget events
        status: {carrier: VALUE, value_type: :string},
        click: {carrier: NONE},
        input: {carrier: VALUE, value_type: :string},
        submit: {carrier: VALUE, value_type: :string},
        toggle: {carrier: VALUE, value_type: :boolean},
        select: {carrier: VALUE, value_type: :any},
        slide: {carrier: VALUE, value_type: :float},
        slide_release: {carrier: VALUE, value_type: :float},
        paste: {carrier: VALUE, value_type: :string},
        open: {carrier: NONE},
        close: {carrier: NONE},
        option_hovered: {carrier: VALUE, value_type: :any},
        # steep:ignore:start
        key_binding: {carrier: VALUE, fields: {}},
        # steep:ignore:end
        link_click: {carrier: VALUE, value_type: :string},
        sort: {carrier: VALUE, value_type: :string},
        scrolled: {
          carrier: VALUE,
          fields: {
            absolute_x: :float, absolute_y: :float,
            relative_x: :float, relative_y: :float,
            bounds_width: :float, bounds_height: :float,
            content_width: :float, content_height: :float
          }
        },

        # Focus and blur (generic element events)
        focused: {carrier: NONE},
        blurred: {carrier: NONE},

        # Drag events
        drag: {
          carrier: VALUE,
          fields: {x: :float, y: :float, delta_x: :float, delta_y: :float}
        },
        drag_end: {
          carrier: VALUE,
          fields: {x: :float, y: :float}
        },

        # Widget-scoped key events
        key_press: {
          carrier: VALUE,
          fields: {
            key: :key, modified_key: :string, physical_key: :string,
            location: :string, modifiers: :key_modifiers,
            text: :string, repeat: :boolean
          },
          required: %i[key modifiers]
        },
        key_release: {
          carrier: VALUE,
          fields: {
            key: :key, modified_key: :string, physical_key: :string,
            location: :string, modifiers: :key_modifiers,
            text: :string, repeat: :boolean
          },
          required: %i[key modifiers]
        },

        # Unified pointer events
        press: {
          carrier: VALUE,
          fields: {
            x: :float, y: :float, button: :pointer,
            pointer: :symbol, finger: :float, modifiers: :any
          }
        },
        release: {
          carrier: VALUE,
          fields: {
            x: :float, y: :float, button: :pointer,
            pointer: :symbol, finger: :float, modifiers: :any
          }
        },
        move: {
          carrier: VALUE,
          fields: {x: :float, y: :float, pointer: :symbol, finger: :float, modifiers: :any}
        },
        scroll: {
          carrier: VALUE,
          fields: {
            x: :float, y: :float, delta_x: :float, delta_y: :float,
            pointer: :symbol, modifiers: :any
          }
        },
        # steep:ignore:start
        enter: {carrier: VALUE, fields: {x: :float, y: :float}, required: []},
        exit: {carrier: VALUE, fields: {x: :float, y: :float}, required: []},
        # steep:ignore:end
        double_click: {
          carrier: VALUE,
          fields: {x: :float, y: :float, pointer: :symbol, modifiers: :any}
        },
        resize: {carrier: VALUE, fields: {width: :float, height: :float}},

        # Pane grid events
        pane_resized: {carrier: VALUE, fields: {split: :any, ratio: :float}},
        pane_dragged: {
          carrier: VALUE,
          fields: {pane: :any, target: :any, action: :any, region: :any, edge: :any}
        },
        pane_clicked: {carrier: VALUE, fields: {pane: :any}},
        pane_focus_cycle: {carrier: VALUE, fields: {pane: :any}},

        # Animation events
        transition_complete: {carrier: VALUE, fields: {tag: :any, prop: :string}}
      }.each_value { |spec|
        spec.each_value(&:freeze)
        spec.freeze
      }.freeze

      # Look up the spec for a built-in event type.
      #
      # @param type [Symbol] event type name
      # @return [Hash, nil] the spec, or nil if not a built-in type
      def self.for(type)
        BUILTIN[type]
      end

      # All built-in event specs.
      #
      # @return [Hash{Symbol => Hash}]
      def self.all
        BUILTIN
      end

      # Check if a type is a recognized built-in event.
      #
      # @param type [Symbol]
      # @return [Boolean]
      def self.builtin?(type)
        BUILTIN.key?(type)
      end

      # Return the declared field names for a structured event type.
      # Returns nil for scalar or no-payload events.
      #
      # @param type [Symbol]
      # @return [Array<Symbol>, nil]
      def self.fields(type)
        spec = BUILTIN[type]
        return nil unless spec
        fields = spec[:fields]
        fields&.keys
      end

      # Return the required fields for a structured event type.
      # Defaults to all declared fields when :required is not specified.
      #
      # @param type [Symbol]
      # @return [Array<Symbol>, nil]
      def self.required_fields(type)
        spec = BUILTIN[type]
        return nil unless spec
        fields = spec[:fields]
        return nil unless fields
        spec[:required] || fields.keys
      end
    end
  end
end
