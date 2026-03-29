# frozen_string_literal: true

module Plushie
  # Module for declaring custom widgets (pure Ruby or native Rust).
  #
  # Include in a class to declare a widget with typed props and a render
  # method that composes existing widgets. Generates:
  #
  # - +initialize(id, **opts)+ with defaults from prop declarations
  # - +set_<prop>(value)+ setter methods for each prop (returns a dup)
  # - +build+ method that calls +render+ and returns a {Plushie::Node}
  # - +type_names+ and +prop_names+ class methods
  #
  # Three kinds of widgets are supported:
  #
  # - **Render-only composite** (default): define an instance-level +render+
  #   that composes existing widgets. No state, no event handling.
  # - **Stateful widget**: declare +state+ fields and/or define class-level
  #   +self.init+, +self.handle_event+, +self.render(id, props, state)+.
  #   The runtime manages state via a registry and renders the widget
  #   during tree normalization. Events in the widget's scope are
  #   dispatched through its +handle_event+ callback.
  # - **Native widget** (Rust-backed): +widget :name, kind: :native_widget+.
  #   Requires +rust_crate+ and +rust_constructor+ declarations.
  #
  # @example Render-only composite
  #   class MyGauge
  #     include Plushie::Widget
  #
  #     widget :gauge
  #     prop :value, :number, default: 0
  #     prop :max, :number, default: 100
  #
  #     def render(id, props)
  #       Plushie::UI.progress_bar(id, {0, props[:max]}, props[:value])
  #     end
  #   end
  #
  # @example Stateful widget with events
  #   class StarRating
  #     include Plushie::Widget
  #
  #     widget :star_rating
  #     prop :rating, :number, default: 0
  #     state :hover, default: nil
  #     event :select
  #
  #     def self.init = {hover: nil}
  #
  #     def self.handle_event(event, state)
  #       case event
  #       in Event::Widget[type: :canvas_element_click, data: {element_id: star}]
  #         [:emit, :select, star.to_i + 1]
  #       else
  #         [:consumed, state]
  #       end
  #     end
  #
  #     def self.render(id, props, state)
  #       # ... returns canvas shapes ...
  #     end
  #   end
  #
  module Widget
    # Recognized property type names for custom widgets.
    # @api private
    KNOWN_PROP_TYPES = %i[
      number string boolean color length padding
      alignment style font atom map any
    ].freeze

    # Property names reserved by the framework.
    # @api private
    RESERVED_PROP_NAMES = %i[id type children a11y event_rate].freeze

    # Methods added to classes that include Plushie::Widget.
    module CustomDSL
      # Valid widget kind values.
      # @api private
      VALID_KINDS = %i[widget native_widget].freeze

      # Declares the widget type name.
      #
      # @param type_name [Symbol] the wire type name for this widget
      # @param opts [Hash] options
      # @option opts [Symbol] :kind (:widget) either +:widget+ or +:native_widget+
      # @option opts [Boolean] :container (false) whether this widget accepts children
      # @return [void]
      def widget(type_name, **opts)
        kind = opts.fetch(:kind, :widget)
        unless VALID_KINDS.include?(kind)
          raise ArgumentError,
            "unsupported widget kind #{kind.inspect}. Supported: #{VALID_KINDS.inspect}"
        end

        @_widget_type = type_name
        @_widget_kind = kind
        @_widget_container = opts.fetch(:container, false)
      end

      # Declares a typed prop with optional default.
      #
      # @param name [Symbol] prop name (must not conflict with reserved names)
      # @param type [Symbol] one of {KNOWN_PROP_TYPES}
      # @param opts [Hash] options
      # @option opts [Object] :default default value for this prop
      # @return [void]
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

        @_widget_props << {name: name, type: type, default: opts[:default]}
      end

      # Declares a state field with a default value.
      #
      # Declaring any state field makes the widget stateful: the runtime
      # manages its state via a registry, renders it during tree
      # normalization, and dispatches events through +handle_event+.
      #
      # @param name [Symbol] state field name
      # @param default [Object] initial value
      # @return [void]
      def state(name, default: nil)
        @_widget_state_fields << {name: name.to_sym, default: default}
      end

      # Declares an event that this widget can emit.
      #
      # Event declarations are informational -- they document the widget's
      # public event contract. Widgets with event declarations or
      # +handle_event+ participate in the event dispatch chain.
      #
      # @param name [Symbol] event name (e.g. +:select+, +:change+)
      # @return [void]
      def event(name)
        @_widget_events << name.to_sym
      end

      # Declares a command (for native widgets, informational in Ruby).
      #
      # @param name [Symbol] command name
      # @param params [Hash{Symbol => Symbol}] parameter names to types
      # @return [void]
      def command(name, **params)
        @_widget_commands << {name: name.to_sym, params: params}
      end

      # Declares the relative path to the Rust crate directory.
      # Required for +:native_widget+ widgets.
      def rust_crate(path)
        @_widget_native_crate = path.to_s
      end

      # Declares the Rust constructor expression used in the generated main.rs.
      # Required for +:native_widget+ widgets.
      def rust_constructor(expr)
        @_widget_rust_constructor = expr.to_s
      end

      # @return [String, nil]
      def native_crate = @_widget_native_crate

      # @return [String, nil]
      def rust_constructor_expr = @_widget_rust_constructor

      # Whether this is a native (Rust-backed) widget.
      # @return [Boolean]
      def native? = @_widget_kind == :native_widget

      # Whether this widget is stateful (has state, events, or handle_event).
      # @return [Boolean]
      def stateful?
        !@_widget_state_fields.empty? ||
          !@_widget_events.empty? ||
          respond_to?(:init) ||
          respond_to?(:handle_event)
      end

      # Returns the widget type names this widget handles.
      # @return [Array<Symbol>]
      def type_names = [@_widget_type]

      # Returns all declared prop names (including auto-added :a11y, :event_rate).
      # @return [Array<Symbol>]
      def prop_names
        @_widget_props.map { _1[:name] } + %i[a11y event_rate]
      end

      # Returns the declared props metadata.
      # @return [Array<Hash{Symbol => Object}>]
      def widget_props = @_widget_props

      # Returns the declared state fields.
      # @return [Array<Hash{Symbol => Object}>]
      def widget_state_fields = @_widget_state_fields

      # Returns the declared event names.
      # @return [Array<Symbol>]
      def widget_events = @_widget_events

      # Whether this is a container widget.
      # @return [Boolean]
      def container? = @_widget_container

      # Finalize the widget class by generating initialize, setters, and build.
      #
      # Called automatically on first instantiation. Can also be called
      # explicitly after all widget/prop/command declarations are complete.
      # @return [void]
      def finalize!
        return if @_finalized

        _validate!
        _set_defaults!
        _generate_initialize!
        _generate_setters!
        _generate_build!
        @_finalized = true
      end

      private

      def _validate!
        unless @_widget_type
          raise ArgumentError, "missing `widget :type_name` declaration in #{name}"
        end

        if @_widget_kind == :native_widget
          unless @_widget_native_crate
            raise ArgumentError,
              "native_widget #{name} requires a `rust_crate` declaration"
          end
          unless @_widget_rust_constructor
            raise ArgumentError,
              "native_widget #{name} requires a `rust_constructor` declaration"
          end
        end
      end

      # Provide default implementations for stateful callbacks.
      def _set_defaults!
        return unless stateful?

        # Default init builds state from declared state fields.
        unless respond_to?(:init)
          fields = @_widget_state_fields
          define_singleton_method(:init) do
            fields.each_with_object({}) { |f, h| h[f[:name]] = f[:default] }
          end
        end

        # Default handle_event: widgets with events are opaque (:consumed),
        # widgets without events are transparent (:ignored).
        unless respond_to?(:handle_event)
          has_events = !@_widget_events.empty?
          define_singleton_method(:handle_event) do |_event, state|
            has_events ? [:consumed, state] : [:ignored, state]
          end
        end

        # Default subscribe: no subscriptions.
        unless respond_to?(:subscribe)
          define_singleton_method(:subscribe) { |_props, _state| [] }
        end
      end

      def _generate_initialize!
        props = @_widget_props

        define_method(:initialize) do |id, **opts|
          @id = id.to_s
          @a11y = opts.delete(:a11y)
          @event_rate = opts.delete(:event_rate)

          props.each do |prop|
            val = opts.fetch(prop[:name], prop[:default])
            instance_variable_set(:"@#{prop[:name]}", val)
          end
        end

        attr_reader :id, :a11y, :event_rate
        props.each { |prop| attr_reader prop[:name] }
      end

      def _generate_setters!
        @_widget_props.each do |prop|
          pname = prop[:name]
          define_method(:"set_#{pname}") do |value|
            dup.tap { _1.instance_variable_set(:"@#{pname}", value) }
          end
        end

        define_method(:set_a11y) do |value|
          dup.tap { _1.instance_variable_set(:@a11y, value) }
        end

        define_method(:set_event_rate) do |value|
          dup.tap { _1.instance_variable_set(:@event_rate, value) }
        end
      end

      def _generate_build!
        if stateful?
          _generate_stateful_build!
        else
          _generate_composite_build!
        end
      end

      # Stateful widgets produce a placeholder node that the runtime
      # renders during tree normalization with current state.
      def _generate_stateful_build!
        props = @_widget_props
        widget_class = self

        define_method(:build) do
          props_hash = {}
          props.each do |prop|
            val = instance_variable_get(:"@#{prop[:name]}")
            props_hash[prop[:name]] = val unless val.nil?
          end
          props_hash[:a11y] = @a11y unless @a11y.nil?
          props_hash[:event_rate] = @event_rate unless @event_rate.nil?

          meta = {
            CanvasWidget::META_KEY => widget_class,
            CanvasWidget::PROPS_KEY => props_hash
          }.freeze
          Plushie::Node.new(id: @id, type: "canvas", props: {}, meta: meta)
        end
      end

      # Render-only composites render immediately in build.
      def _generate_composite_build!
        props = @_widget_props

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

    # Auto-finalize when first instantiated.
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
      base.extend(CustomDSL)
      base.instance_variable_set(:@_widget_type, nil)
      base.instance_variable_set(:@_widget_kind, :widget)
      base.instance_variable_set(:@_widget_props, [])
      base.instance_variable_set(:@_widget_state_fields, [])
      base.instance_variable_set(:@_widget_events, [])
      base.instance_variable_set(:@_widget_commands, [])
      base.instance_variable_set(:@_widget_container, false)
      base.instance_variable_set(:@_widget_native_crate, nil)
      base.instance_variable_set(:@_widget_rust_constructor, nil)
      base.instance_variable_set(:@_finalized, false)
      finalize_on_new(base)
    end
  end
end
