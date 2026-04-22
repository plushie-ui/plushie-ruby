# frozen_string_literal: true

module Plushie
  # Unified widget system for declaring all widget types.
  #
  # One system handles leaf widgets, containers, composite widgets,
  # stateful widgets, and native Rust-backed widgets. Two entry points:
  #
  # - +Widget.define+ for declarative widgets (no custom methods needed)
  # - +include Plushie::Widget+ for behavioral widgets (with view, handle_event)
  #
  # Both use the same underlying DSL, finalization, and build pipeline.
  #
  # == Widget.define (declarative, factory pattern)
  #
  # Returns a fully-formed class. Mirrors +Data.define+ convention.
  # Best for leaf widgets, containers, and prop-to-wire mappings.
  #
  #   Button = Plushie::Widget.define(:button) do
  #     children :none
  #     positional :label
  #     prop :label, :width, :height, :style, :disabled
  #     default_a11y role: :button, label_from: :label
  #   end
  #
  # == include Plushie::Widget (behavioral, class pattern)
  #
  # For widgets with custom Ruby methods, view callbacks, or state.
  #
  #   class StarRating
  #     include Plushie::Widget
  #
  #     widget :star_rating
  #     prop :rating, :number, default: 0
  #     state :hover, default: nil
  #     event :select
  #
  #     def self.init = {hover: nil}
  #     def self.handle_event(event, state) = ...
  #     def self.view(id, props, state) = ...
  #   end
  #
  module Widget
    # Recognized property type names for typed props.
    # Untyped props (bare name declarations) bypass this check.
    # @api private
    KNOWN_PROP_TYPES = %i[
      number string boolean color length padding
      alignment style font atom map any
    ].freeze

    # Private sentinel for "no default provided, this arg is required."
    # Using a frozen Object prevents collision with any user-supplied value.
    # @api private
    REQUIRED = Object.new.freeze

    # Property names reserved by the framework that the DSL rejects when
    # declared via `prop`. `:id`, `:type`, and `:children` are structural
    # fields, not props. `:a11y` and `:event_rate` are auto-wired on
    # every widget but callers may also list them in `prop :...` for
    # discoverability; the DSL accepts those declarations as no-ops.
    STRUCTURAL_PROP_NAMES = %i[id type children].freeze
    AUTO_WIRED_PROP_NAMES = %i[a11y event_rate].freeze
    RESERVED_PROP_NAMES = (STRUCTURAL_PROP_NAMES + AUTO_WIRED_PROP_NAMES).freeze

    # Create a widget class from declarative block.
    #
    # Returns a fully-formed class with all generated methods.
    # The block is class_eval'd, so +def+ defines instance methods
    # and DSL methods (+prop+, +children+, etc.) are available.
    #
    # @param type_name [Symbol] wire protocol type name
    # @param opts [Hash] options (passed to {CustomDSL#widget})
    # @yield declarations block (class_eval context)
    # @return [Class] the finalized widget class
    #
    # @example Leaf widget
    #   Button = Widget.define(:button) do
    #     positional :label
    #     prop :label, :style, :disabled
    #   end
    #
    # @example Container with custom methods
    #   Container = Widget.define(:container) do
    #     children :single
    #     prop :padding, :width, :height, :align_x, :align_y
    #
    #     def center_x(width = :fill)
    #       dup.tap { |c| c.instance_variable_set(:@width, width)
    #                      c.instance_variable_set(:@align_x, :center) }
    #     end
    #   end
    def self.define(type_name, **opts, &block)
      klass = Class.new
      klass.include(Plushie::Widget)
      klass.widget(type_name, **opts)
      klass.class_eval(&block) if block
      klass.finalize!
      klass
    end

    # DSL methods added to classes that include Plushie::Widget
    # or are created via Widget.define.
    module CustomDSL
      # Valid widget kind values.
      # @api private
      VALID_KINDS = %i[widget native_widget].freeze

      # Declares the widget type name.
      #
      # @param type_name [Symbol] the wire type name for this widget
      # @param opts [Hash] options
      # @option opts [Symbol] :kind (:widget) either +:widget+ or +:native_widget+
      # @return [void]
      def widget(type_name, **opts)
        kind = opts.fetch(:kind, :widget)
        unless VALID_KINDS.include?(kind)
          raise ArgumentError,
            "unsupported widget kind #{kind.inspect}. Supported: #{VALID_KINDS.inspect}"
        end

        @_widget_type = type_name
        @_widget_kind = kind

        return unless opts.key?(:container)

        mode = (opts[:container] == true) ? :many : opts[:container]
        children(mode)
      end

      # Declare one or more props.
      #
      # Supports three forms:
      # - Simple: +prop :label, :width, :height+ (names only, untyped)
      # - Typed: +prop :value, :number, default: 0+ (name + type)
      # - Rich: +prop :label, type: :string, doc: "Text label"+ (name + metadata)
      #
      # Types are informational: they document the prop for introspection
      # and future tooling. Values pass through to the wire protocol
      # where the renderer handles validation.
      #
      # @param names [Array<Symbol>] prop names
      # @param type [Symbol, nil] type hint (rich form)
      # @param doc [String, nil] documentation (rich form)
      # @param default [Object] default value
      # @return [void]
      def prop(*names, type: nil, doc: nil, default: nil)
        if names.length == 1 && (type || doc)
          # Rich form: prop :name, type: :string, doc: "..."
          name = names[0].to_sym
          if type && !KNOWN_PROP_TYPES.include?(type.to_sym)
            raise ArgumentError,
              "unsupported prop type #{type.inspect} for #{name.inspect}. " \
              "Known types: #{KNOWN_PROP_TYPES.inspect}"
          end
          is_auto = _check_prop_name!(name)
          unless is_auto
            @_widget_props << {name: name, type: type, default: default}
            (@_prop_meta ||= {})[name] = {type: type, doc: doc}.compact
          end
        elsif names.length == 2 && KNOWN_PROP_TYPES.include?(names[1].to_sym)
          # Typed form: prop :name, :string, default: 0
          name = names[0].to_sym
          type_val = names[1].to_sym
          is_auto = _check_prop_name!(name)
          unless is_auto
            @_widget_props << {name: name, type: type_val, default: default}
          end
        else
          # Simple form: prop :name1, :name2, ...
          if default
            raise ArgumentError,
              "default: cannot be used with the multi-name prop form. " \
              "Use `prop :#{names.first}, type: :any, default: ...` for a single prop with a default"
          end
          names.each do |n|
            sym = n.to_sym
            is_auto = _check_prop_name!(sym)
            next if is_auto

            @_widget_props << {name: sym, type: nil, default: nil}
          end
        end
      end

      # Declare a positional constructor argument.
      #
      # Call order determines argument order after +id+.
      # The name must also be a declared prop.
      #
      # @param name [Symbol] argument name
      # @param default [Object] default value (omit for mandatory)
      # @return [void]
      def positional(name, default: REQUIRED)
        @_widget_positionals << {name: name.to_sym, default: default}
      end

      # Declare children mode.
      #
      # @param mode [:none, :single, :many, Integer] child constraint
      # @return [void]
      def children(mode)
        @_widget_children_mode = mode
        @_widget_container = mode && mode != :none
      end

      # Declare default a11y annotations for this widget type.
      #
      # Merged into the widget's a11y prop during build when the user
      # hasn't provided explicit overrides. User values win per field.
      #
      # @param defaults [Hash] default a11y fields
      # @option defaults [Symbol] :role accessible role
      # @option defaults [Symbol] :label_from prop name to derive label from
      # @return [void]
      # @example
      #   default_a11y role: :button, label_from: :label
      def default_a11y(**defaults)
        @_a11y_defaults = defaults.freeze
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

      # Declares a cache key function for view-level caching.
      #
      # When the cache key proc returns the same value as the previous
      # render, the widget's view is skipped and the cached normalized
      # output is reused. Complementary to memo (subtree-level caching).
      #
      # @param fn [Proc] receives (props, state), returns a cache key
      # @example
      #   cache_key ->(props, state) { [props[:version], state[:zoom]] }
      def cache_key(fn)
        @_widget_cache_key = fn
      end

      # Declares an event that this widget can emit.
      #
      # Event declarations document the widget's public event contract.
      # Widgets with event declarations or +handle_event+ participate
      # in the event dispatch chain.
      #
      # With +fields:+, declares typed fields that are validated at emit
      # time. Fields are required by default. Use
      # +{type: Class, required: false}+ to make a field optional.
      #
      # @param name [Symbol] event name (e.g. +:select+, +:change+)
      # @param fields [Hash{Symbol => Class, Hash}] typed field declarations
      # @return [void]
      #
      # @example Simple event
      #   event :click
      #
      # @example Event with typed required fields
      #   event :change, fields: {hue: Numeric, saturation: Numeric}
      #
      # @example Event with optional field
      #   event :change, fields: {
      #     hue: Numeric,
      #     saturation: Numeric,
      #     modifier: {type: String, required: false}
      #   }
      def event(name, fields: nil)
        name = name.to_sym
        spec = if fields && !fields.empty?
          resolved_fields = fields.each_with_object({}) do |(k, v), h|
            h[k] = if v.is_a?(Hash)
              {type: v[:type], required: v.fetch(:required, true)}
            else
              {type: v, required: true}
            end
          end
          {name: name, fields: resolved_fields}
        else
          {name: name, fields: nil}
        end
        @_widget_events << spec
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
      # @param path [String] path to crate
      # @return [void]
      def rust_crate(path)
        @_widget_native_crate = path.to_s
      end

      # Declares the Rust constructor expression used in the generated main.rs.
      # Required for +:native_widget+ widgets.
      # @param expr [String] Rust expression
      # @return [void]
      def rust_constructor(expr)
        @_widget_rust_constructor = expr.to_s
      end

      # -- Accessors -----------------------------------------------------------

      # @return [String, nil] Rust crate path
      def native_crate = @_widget_native_crate

      # @return [String, nil] Rust constructor expression
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

      # Returns all declared prop names (plus auto-added :a11y, :event_rate).
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
      def widget_events = @_widget_events.map { |e| e[:name] }

      # Returns the declared event specs with field definitions.
      # @return [Array<Hash{Symbol => Object}>]
      def widget_event_specs = @_widget_events

      # Whether this is a container widget (accepts children).
      # @return [Boolean]
      def container? = @_widget_container

      # Returns the children mode (:none, :single, :many, or Integer).
      # @return [Symbol, Integer, nil]
      def children_mode = @_widget_children_mode

      # Returns the cache key function, or nil.
      # @return [Proc, nil]
      def cache_key_fn = @_widget_cache_key

      # Returns metadata for declared props (type, doc).
      # @return [Hash{Symbol => Hash}]
      def prop_meta = @_prop_meta || {}

      # Returns the default a11y annotations, or nil.
      # @return [Hash, nil]
      def a11y_defaults = @_a11y_defaults

      # @api private
      # @return [Array<Hash>] positional argument declarations
      def widget_positionals = @_widget_positionals

      # -- Finalization --------------------------------------------------------

      # Finalize the widget class by generating initialize, setters, and build.
      #
      # Called automatically on first instantiation, or explicitly by
      # Widget.define after the block has been evaluated.
      # @return [void]
      def finalize!
        return if @_finalized

        _validate!
        _set_defaults!
        _generate_readers!
        _generate_initialize!
        _generate_setters!
        _generate_push! if container?
        _generate_build!
        @_finalized = true
      end

      private

      # Check that a declared prop name is legal. Structural names
      # (`:id`, `:type`, `:children`) are always rejected. Auto-wired
      # names (`:a11y`, `:event_rate`) are allowed as no-op declarations
      # for discoverability; the macro still handles them internally.
      #
      # @return [Boolean] true if the name is an auto-wired declaration
      #   that should be silently dropped from `@_widget_props`.
      def _check_prop_name!(name)
        if STRUCTURAL_PROP_NAMES.include?(name)
          raise ArgumentError,
            "prop name #{name.inspect} is reserved. Structural props: #{STRUCTURAL_PROP_NAMES.inspect}"
        end
        AUTO_WIRED_PROP_NAMES.include?(name)
      end

      def _validate!
        raise ArgumentError, "missing `widget :type_name` declaration in #{name || "(anonymous)"}" unless @_widget_type

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

        return unless stateful? && !respond_to?(:view)

        raise ArgumentError,
          "stateful widget #{name} requires a `def self.view(id, props, state)` class method"
      end

      # Provide default implementations for stateful callbacks.
      def _set_defaults!
        return unless stateful?

        unless respond_to?(:init)
          fields = @_widget_state_fields
          define_singleton_method(:init) do
            fields.each_with_object({}) { |f, h| h[f[:name]] = f[:default] }
          end
        end

        unless respond_to?(:handle_event)
          has_events = !@_widget_events.empty?
          define_singleton_method(:handle_event) do |_event, state|
            has_events ? [:consumed, state] : [:ignored, state]
          end
        end

        return if respond_to?(:subscribe)

        define_singleton_method(:subscribe) { |_props, _state| [] }
      end

      def _generate_readers!
        all = [:id] + @_widget_props.map { _1[:name] } + %i[a11y event_rate]
        all << :children if container?
        all.each { |name| attr_reader name }
      end

      def _generate_initialize!
        props = @_widget_props
        positionals = @_widget_positionals
        is_container = container?

        define_method(:initialize) do |id, *args, **opts|
          @id = id.to_s

          n_required = positionals.count { _1[:default].equal?(REQUIRED) }

          if args.length > positionals.size
            raise ArgumentError,
              "#{self.class}: " \
              "expected at most #{positionals.size} positional arg(s), got #{args.length}"
          end

          if args.length < n_required
            missing = positionals
              .select { _1[:default].equal?(REQUIRED) }
              .drop(args.length)
              .map { _1[:name] }
            raise ArgumentError,
              "#{self.class}: " \
              "missing required positional arg(s): #{missing.join(", ")}"
          end

          positionals.each_with_index do |spec, i|
            next if opts.key?(spec[:name])

            if i < args.length
              opts[spec[:name]] = args[i]
            elsif !spec[:default].equal?(REQUIRED)
              opts[spec[:name]] = spec[:default]
            end
          end

          @children = opts.delete(:children) || [] if is_container
          @a11y = opts.delete(:a11y)
          @event_rate = opts.delete(:event_rate)

          props.each do |prop|
            val = opts.key?(prop[:name]) ? opts[prop[:name]] : prop[:default]
            self.class.validate_prop_type(prop[:name], val, prop[:type]) unless val.nil? || !prop[:type]
            instance_variable_set(:"@#{prop[:name]}", val)
          end
        end
      end

      def _generate_setters!
        @_widget_props.each do |prop|
          pname = prop[:name]
          ptype = prop[:type]
          if ptype
            define_method(:"set_#{pname}") do |value|
              self.class.validate_prop_type(pname, value, ptype) unless value.nil?
              dup.tap { _1.instance_variable_set(:"@#{pname}", value) }
            end
          else
            define_method(:"set_#{pname}") do |value|
              dup.tap { _1.instance_variable_set(:"@#{pname}", value) }
            end
          end
        end

        define_method(:set_a11y) do |value|
          dup.tap { _1.instance_variable_set(:@a11y, value) }
        end

        define_method(:set_event_rate) do |value|
          dup.tap { _1.instance_variable_set(:@event_rate, value) }
        end
      end

      def _generate_push!
        define_method(:push) do |child|
          dup.tap { |copy| copy.instance_variable_set(:@children, @children + [child]) }
        end
      end

      # Validate a prop value against its declared type.
      # Supports Class/module types, :numeric, :boolean, and composite
      # types ({tuple: [T1, T2]}, {enum: [:a, :b]}, {list: T}).
      def validate_prop_type(name, value, type)
        case type
        when Class, Module
          unless value.is_a?(type)
            raise ArgumentError,
              "#{name} expects #{type}, got #{value.class}: #{value.inspect}"
          end
        when :numeric
          unless value.is_a?(Numeric)
            raise ArgumentError,
              "#{name} expects a Numeric, got #{value.class}: #{value.inspect}"
          end
        when :boolean
          unless [true, false].include?(value)
            raise ArgumentError,
              "#{name} expects true or false, got #{value.inspect}"
          end
        when :symbol
          unless value.is_a?(Symbol)
            raise ArgumentError,
              "#{name} expects a Symbol, got #{value.class}: #{value.inspect}"
          end
        when Hash
          validate_composite_type(name, value, type)
        end
      end

      def validate_composite_type(name, value, type_spec)
        if (tuple_types = type_spec[:tuple])
          unless value.is_a?(Array) && value.length == tuple_types.length
            raise ArgumentError,
              "#{name} expects a #{tuple_types.length}-element Array, " \
              "got #{value.inspect}"
          end
          tuple_types.each_with_index do |elem_type, i|
            validate_prop_type("#{name}[#{i}]", value[i], elem_type)
          end
        elsif (enum_values = type_spec[:enum])
          unless enum_values.include?(value)
            raise ArgumentError,
              "#{name} expects one of #{enum_values.inspect}, got #{value.inspect}"
          end
        elsif (list_type = type_spec[:list])
          raise ArgumentError, "#{name} expects an Array, got #{value.class}" unless value.is_a?(Array)

          value.each_with_index do |elem, i|
            validate_prop_type("#{name}[#{i}]", elem, list_type)
          end
        elsif (map_types = type_spec[:map])
          raise ArgumentError, "#{name} expects a Hash, got #{value.class}" unless value.is_a?(Hash)

          map_types.each do |key, val_type|
            validate_prop_type("#{name}[#{key.inspect}]", value[key], val_type) if value.key?(key)
          end
        end
      end

      public :validate_prop_type, :validate_composite_type

      def _generate_build!
        if stateful?
          _generate_stateful_build!
        else
          _generate_direct_build!
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
          node = Plushie::Node.new(id: @id, type: "widget_placeholder", props: {}, meta: meta)

          parent = Plushie::UI::Context.current
          parent << node if parent

          node
        end
      end

      # Non-stateful widgets produce a Node directly.
      # If a view method exists, calls it. Otherwise builds from props.
      def _generate_direct_build!
        props_list = @_widget_props
        children_mode = @_widget_children_mode
        is_container = container?
        a11y_defaults = @_a11y_defaults

        define_method(:build) do
          # Validate children constraints.
          if is_container
            case children_mode
            when :single
              Build.validate_single_child!(@id, self.class.type_names.first.to_s, @children)
            when Integer
              Build.validate_children_count!(@id, self.class.type_names.first.to_s, @children, children_mode)
            end
          end

          # Build props hash, skipping nils.
          props_hash = {}
          props_list.each do |prop|
            val = instance_variable_get(:"@#{prop[:name]}")
            props_hash[prop[:name]] = val unless val.nil?
          end

          # Inject a11y defaults (user overrides win per field).
          if a11y_defaults
            resolved = Build.resolve_a11y(props_hash.merge(a11y: @a11y), a11y_defaults)
            props_hash[:a11y] = resolved if resolved
          elsif @a11y
            props_hash[:a11y] = @a11y
          end

          props_hash[:event_rate] = @event_rate unless @event_rate.nil?

          node = if respond_to?(:view)
            view(@id, props_hash)
          elsif is_container
            Plushie::Node.new(
              id: @id,
              type: self.class.type_names.first.to_s,
              props: props_hash,
              children: Build.children_to_nodes(@children)
            )
          else
            Plushie::Node.new(
              id: @id,
              type: self.class.type_names.first.to_s,
              props: props_hash
            )
          end

          parent = Plushie::UI::Context.current
          parent << node if parent

          node
        end
      end
    end

    # Auto-finalize when first instantiated.
    # @api private
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

    # @api private
    def self.included(base)
      base.extend(CustomDSL)
      base.instance_variable_set(:@_widget_type, nil)
      base.instance_variable_set(:@_widget_kind, :widget)
      base.instance_variable_set(:@_widget_props, [])
      base.instance_variable_set(:@_widget_positionals, [])
      base.instance_variable_set(:@_widget_state_fields, [])
      base.instance_variable_set(:@_widget_events, [])
      base.instance_variable_set(:@_widget_commands, [])
      base.instance_variable_set(:@_widget_container, false)
      base.instance_variable_set(:@_widget_children_mode, nil)
      base.instance_variable_set(:@_widget_native_crate, nil)
      base.instance_variable_set(:@_widget_rust_constructor, nil)
      base.instance_variable_set(:@_widget_cache_key, nil)
      base.instance_variable_set(:@_a11y_defaults, nil)
      base.instance_variable_set(:@_prop_meta, nil)
      base.instance_variable_set(:@_finalized, false)
      finalize_on_new(base)
    end
  end
end
