# frozen_string_literal: true

module Plushie
  # Module for declaring widget extensions (pure Ruby or native Rust).
  #
  # Include in a class to declare a widget with typed props and a render
  # method that composes existing widgets. The Extension module generates:
  #
  # - +initialize(id, **opts)+ with defaults from prop declarations
  # - +set_<prop>(value)+ setter methods for each prop (returns a dup)
  # - +build+ method that calls +render+ and returns a {Plushie::Node}
  # - +type_names+ and +prop_names+ class methods
  #
  # Two kinds of extensions are supported:
  #
  # - +:widget+ (default) -- pure Ruby composite. Implements +render+ to
  #   compose existing widgets. No Rust, no binary rebuild.
  # - +:native_widget+ -- Rust-backed. Requires +rust_crate+ and
  #   +rust_constructor+ declarations. Built via +rake plushie:build+.
  #
  # @example Defining a composite gauge widget
  #   class MyGauge
  #     include Plushie::Extension
  #
  #     widget :gauge
  #     prop :value, :number, default: 0
  #     prop :max, :number, default: 100
  #     prop :color, :color, default: :blue
  #
  #     def render(id, props)
  #       Plushie::Widget::ProgressBar.new(id, {0, props[:max]}, props[:value]).build
  #     end
  #   end
  #
  # @example Native Rust widget
  #   class SparklineExtension
  #     include Plushie::Extension
  #
  #     widget :sparkline, kind: :native_widget
  #     rust_crate "native/sparkline"
  #     rust_constructor "sparkline::SparklineExtension::new()"
  #
  #     prop :data, :any, default: []
  #     prop :color, :color, default: :blue
  #     prop :stroke_width, :number, default: 2
  #
  #     command :push_data, values: :any
  #   end
  #
  # @example Using the generated API
  #   gauge = MyGauge.new("cpu", value: 72, max: 100)
  #   gauge = gauge.set_value(85)
  #   node = gauge.build
  #
  module Extension
    KNOWN_PROP_TYPES = %i[
      number string boolean color length padding
      alignment style font atom map any
    ].freeze

    RESERVED_PROP_NAMES = %i[id type children a11y event_rate].freeze

    module ClassMethods
      VALID_KINDS = %i[widget native_widget].freeze

      # Declares the widget type name.
      #
      # @param type_name [Symbol] the wire type name for this widget
      # @param opts [Hash] options
      # @option opts [Symbol] :kind (:widget) either +:widget+ or +:native_widget+
      # @option opts [Boolean] :container (false) whether this widget accepts children
      # @return [void]
      #
      # @example Pure Ruby widget
      #   widget :gauge
      # @example Native Rust widget
      #   widget :sparkline, kind: :native_widget
      def widget(type_name, **opts)
        kind = opts.fetch(:kind, :widget)
        unless VALID_KINDS.include?(kind)
          raise ArgumentError,
            "unsupported widget kind #{kind.inspect}. Supported: #{VALID_KINDS.inspect}"
        end

        @_extension_widget = type_name
        @_extension_kind = kind
        @_extension_container = opts.fetch(:container, false)
      end

      # Declares the relative path to the Rust crate directory.
      # Required for +:native_widget+ extensions.
      #
      # @param path [String] relative path from the project root to the crate
      # @return [void]
      #
      # @example
      #   rust_crate "native/sparkline"
      def rust_crate(path)
        @_extension_native_crate = path.to_s
      end

      # Declares the Rust constructor expression used in the generated main.rs.
      # Required for +:native_widget+ extensions.
      #
      # @param expr [String] a valid Rust expression (e.g. "MyExt::new()")
      # @return [void]
      #
      # @example
      #   rust_constructor "sparkline::SparklineExtension::new()"
      def rust_constructor(expr)
        @_extension_rust_constructor = expr.to_s
      end

      # Returns the native crate path declared via +rust_crate+.
      #
      # @return [String, nil]
      def native_crate
        @_extension_native_crate
      end

      # Returns the Rust constructor expression declared via +rust_constructor+.
      #
      # @return [String, nil]
      def rust_constructor_expr
        @_extension_rust_constructor
      end

      # Whether this is a native (Rust-backed) extension.
      #
      # @return [Boolean]
      def native?
        @_extension_kind == :native_widget
      end

      # Declares a typed prop with optional default.
      #
      # @param name [Symbol] prop name (must not conflict with reserved names)
      # @param type [Symbol] one of {KNOWN_PROP_TYPES}
      # @param opts [Hash] options
      # @option opts [Object] :default default value for this prop
      # @return [void]
      # @raise [ArgumentError] if type is unsupported or name is reserved
      #
      # @example
      #   prop :value, :number, default: 0
      #   prop :label, :string
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
      #
      # In pure Ruby extensions this is informational only. For native
      # Rust-backed extensions, declared commands map to wire commands
      # sent to the renderer.
      #
      # @param name [Symbol] command name
      # @param params [Hash{Symbol => Symbol}] parameter names to types
      # @return [void]
      #
      # @example
      #   command :set_value, value: :number
      def command(name, **params)
        @_extension_commands << {name: name.to_sym, params: params}
      end

      # Returns the widget type names this extension handles.
      #
      # @return [Array<Symbol>]
      def type_names
        [@_extension_widget]
      end

      # Returns all declared prop names (including auto-added :a11y, :event_rate).
      #
      # @return [Array<Symbol>]
      def prop_names
        @_extension_props.map { _1[:name] } + %i[a11y event_rate]
      end

      # Returns the declared props metadata.
      #
      # @return [Array<Hash{Symbol => Object}>] each hash has :name, :type, :default keys
      def extension_props
        @_extension_props
      end

      # Whether this is a container widget.
      #
      # @return [Boolean]
      def container?
        @_extension_container
      end

      # Finalize the extension class by generating initialize, setters, and build.
      #
      # Called automatically on first instantiation. Can also be called
      # explicitly after all widget/prop/command declarations are complete.
      #
      # @return [void]
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

        if @_extension_kind == :native_widget
          unless @_extension_native_crate
            raise ArgumentError,
              "native_widget #{name} requires a `rust_crate` declaration"
          end
          unless @_extension_rust_constructor
            raise ArgumentError,
              "native_widget #{name} requires a `rust_constructor` declaration"
          end
        end
      end

      def _generate_initialize!
        props = @_extension_props

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
      base.instance_variable_set(:@_extension_kind, :widget)
      base.instance_variable_set(:@_extension_props, [])
      base.instance_variable_set(:@_extension_commands, [])
      base.instance_variable_set(:@_extension_container, false)
      base.instance_variable_set(:@_extension_native_crate, nil)
      base.instance_variable_set(:@_extension_rust_constructor, nil)
      base.instance_variable_set(:@_finalized, false)
      finalize_on_new(base)
    end
  end
end
