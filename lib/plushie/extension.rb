# frozen_string_literal: true

module Plushie
  # Module for declaring pure Ruby composite widget extensions.
  #
  # Include in a class to declare a widget with typed props and a render
  # method that composes existing widgets:
  #
  #   class MyGauge
  #     include Plushie::Extension
  #
  #     widget :gauge
  #     prop :value, :number, default: 0
  #     prop :max, :number, default: 100
  #     prop :color, :color, default: :blue
  #
  #     def render(id, props)
  #       # Return a Node tree using Widget builders or the UI DSL
  #     end
  #   end
  #
  # The Extension module generates:
  # - initialize(id, **opts) with defaults from prop declarations
  # - setter methods for each prop (returning a dup)
  # - build method that calls render and returns a Node
  # - type_names class method
  # - prop_names class method
  #
  module Extension
    KNOWN_PROP_TYPES = %i[
      number string boolean color length padding
      alignment style font atom map any
    ].freeze

    RESERVED_PROP_NAMES = %i[id type children a11y event_rate].freeze

    def self.included(base)
      base.extend(ClassMethods)
      base.instance_variable_set(:@_extension_widget, nil)
      base.instance_variable_set(:@_extension_props, [])
      base.instance_variable_set(:@_extension_commands, [])
      base.instance_variable_set(:@_extension_container, false)
    end

    module ClassMethods
      # Declares the widget type name.
      #   widget :gauge
      #   widget :labeled_input, container: true
      def widget(type_name, **opts)
        @_extension_widget = type_name
        @_extension_container = opts.fetch(:container, false)
      end

      # Declares a typed prop with optional default.
      #   prop :value, :number, default: 0
      def prop(name, type, **opts)
        name = name.to_sym
        type = type.to_sym

        unless KNOWN_PROP_TYPES.include?(type)
          raise ArgumentError,
            "unsupported prop type #{type.inspect} for prop #{name.inspect}. " \
            "Supported: #{KNOWN_PROP_TYPES.inspect}"
        end

        if RESERVED_PROP_NAMES.include?(name)
          raise ArgumentError,
            "prop name #{name.inspect} is reserved. Reserved: #{RESERVED_PROP_NAMES.inspect}"
        end

        @_extension_props << {name: name, type: type, default: opts[:default]}
      end

      # Declares a command (for native extensions, informational in Ruby).
      #   command :set_value, value: :number
      def command(name, **params)
        @_extension_commands << {name: name.to_sym, params: params}
      end

      # Returns the widget type names this extension handles.
      def type_names
        [@_extension_widget]
      end

      # Returns all declared prop names (including auto-added :a11y, :event_rate).
      def prop_names
        @_extension_props.map { _1[:name] } + %i[a11y event_rate]
      end

      # Returns the declared props metadata.
      def extension_props
        @_extension_props
      end

      # Whether this is a container widget.
      def container?
        @_extension_container
      end

      # Hook called when a class that includes Extension is first subclassed
      # or when the class body finishes. We use it to finalize the class by
      # generating initialize, setters, and build.
      def finalize!
        return if @_finalized

        _validate!
        _generate_initialize!
        _generate_setters!
        _generate_build!
        @_finalized = true
      end

      private

      def _validate!
        unless @_extension_widget
          raise ArgumentError, "missing `widget :type_name` declaration in #{name}"
        end
      end

      def _generate_initialize!
        props = @_extension_props
        klass = self

        define_method(:initialize) do |id, **opts|
          @id = id.to_s
          @a11y = opts.delete(:a11y)
          @event_rate = opts.delete(:event_rate)

          props.each do |prop|
            val = opts.fetch(prop[:name], prop[:default])
            instance_variable_set(:"@#{prop[:name]}", val)
          end
        end

        # Define attr_reader for id, a11y, event_rate, and all props
        attr_reader :id, :a11y, :event_rate
        props.each do |prop|
          attr_reader prop[:name]
        end
      end

      def _generate_setters!
        @_extension_props.each do |prop|
          pname = prop[:name]
          define_method(:"set_#{pname}") do |value|
            dup.tap { _1.instance_variable_set(:"@#{pname}", value) }
          end
        end

        # a11y and event_rate setters
        define_method(:set_a11y) do |value|
          dup.tap { _1.instance_variable_set(:@a11y, value) }
        end

        define_method(:set_event_rate) do |value|
          dup.tap { _1.instance_variable_set(:@event_rate, value) }
        end
      end

      def _generate_build!
        props = @_extension_props

        define_method(:build) do
          props_hash = {}
          props.each do |prop|
            val = instance_variable_get(:"@#{prop[:name]}")
            props_hash[prop[:name]] = val unless val.nil?
          end
          props_hash[:a11y] = @a11y unless @a11y.nil?
          props_hash[:event_rate] = @event_rate unless @event_rate.nil?

          if respond_to?(:render)
            render(@id, props_hash)
          else
            type_str = self.class.type_names.first.to_s
            Plushie::Node.new(id: @id, type: type_str, props: props_hash)
          end
        end
      end
    end

    # Auto-finalize when method_added triggers (for render) or at first instantiation.
    def self.finalize_on_new(base)
      base.class_eval do
        class << self
          alias_method :_orig_new, :new

          def new(...)
            finalize! unless @_finalized
            _orig_new(...)
          end
        end
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
      base.instance_variable_set(:@_extension_widget, nil)
      base.instance_variable_set(:@_extension_props, [])
      base.instance_variable_set(:@_extension_commands, [])
      base.instance_variable_set(:@_extension_container, false)
      base.instance_variable_set(:@_finalized, false)
      finalize_on_new(base)
    end
  end
end
