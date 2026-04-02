# frozen_string_literal: true

module Plushie
  module Widget
    # Declarative base class for built-in widget builders (Layer 2 API).
    #
    # Eliminates boilerplate by generating initialize, attr_readers,
    # immutable setters, push (for containers), and build from
    # declarative class-level calls.
    #
    # @example Leaf widget
    #   class Button < BuiltIn
    #     wire_type :button
    #     children :none
    #     positional :label
    #     prop :label, :width, :height, :padding,
    #          :clip, :style, :disabled, :a11y
    #   end
    #
    # @example Single-child container
    #   class Container < BuiltIn
    #     wire_type :container
    #     children :single
    #     prop :padding, :width, :height, :max_width, :max_height,
    #          :center, :clip, :align_x, :align_y, :background,
    #          :color, :border, :shadow, :style, :a11y
    #   end
    #
    # @example Multi-child container
    #   class Column < BuiltIn
    #     wire_type :column
    #     children :many
    #     prop :spacing, :padding, :width, :height, :max_width,
    #          :clip, :align_x, :align_y, :a11y
    #   end
    #
    class BuiltIn
      class << self
        # Declare the wire protocol type name.
        # @param name [Symbol, String] type sent over the wire
        def wire_type(name)
          @_wire_type = name.to_s
        end

        # Declare children mode.
        # @param mode [:none, :single, :many, Integer] child constraint
        def children(mode)
          @_children_mode = mode
        end

        # Declare a positional constructor argument.
        # Call order determines argument order after +id+.
        # @param name [Symbol] argument name (must also be a declared prop)
        # @param default [Object] default value (:_required_ means mandatory)
        def positional(name, default: :_required_)
          @_positionals << {name: name.to_sym, default: default}
        end

        # Declare one or more props (keyword arguments on the constructor).
        # @param names [Array<Symbol>] prop names
        def prop(*names)
          names.each { |n| @_props << n.to_sym }
        end

        # @api private
        attr_reader :_wire_type
        # @api private
        attr_reader :_children_mode
        # @api private
        attr_reader :_positionals
        # @api private
        attr_reader :_props

        # Whether instances of this widget have children.
        def _container? = @_children_mode && @_children_mode != :none

        # Hook: set up class-level storage when subclassed.
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@_wire_type, nil)
          subclass.instance_variable_set(:@_children_mode, :none)
          subclass.instance_variable_set(:@_positionals, [])
          subclass.instance_variable_set(:@_props, [])
          subclass.instance_variable_set(:@_finalized, false)
        end

        # Lazy finalization on first instantiation.
        def new(...)
          finalize! unless @_finalized
          allocate.tap { |o| o.send(:initialize, ...) }
        end

        # Generate all methods from the declarations.
        def finalize!
          return if @_finalized
          _generate_readers!
          _generate_initialize!
          _generate_setters!
          _generate_push! if _container?
          _generate_build!
          @_finalized = true
        end

        private

        def _generate_readers!
          all = [:id] + @_props
          all << :children if _container?
          all.each { |name| attr_reader name }
        end

        def _generate_initialize!
          props = @_props
          positionals = @_positionals
          container = _container?

          define_method(:initialize) do |id, *args, **opts|
            @id = id.to_s

            # Merge positional args into opts. Keyword args take
            # precedence over positionals (explicit > implicit).
            positionals.each_with_index do |spec, i|
              next if opts.key?(spec[:name])
              if i < args.length
                opts[spec[:name]] = args[i]
              elsif spec[:default] != :_required_
                opts[spec[:name]] = spec[:default]
              end
            end

            # Set children if container.
            @children = opts.delete(:children) || [] if container

            # Set all declared props from opts.
            props.each do |name|
              instance_variable_set(:"@#{name}", opts[name]) if opts.key?(name)
            end
          end
        end

        def _generate_setters!
          @_props.each do |name|
            define_method(:"set_#{name}") do |value|
              dup.tap { |copy| copy.instance_variable_set(:"@#{name}", value) }
            end
          end
        end

        def _generate_push!
          define_method(:push) do |child|
            dup.tap { |copy| copy.instance_variable_set(:@children, @children + [child]) }
          end
        end

        def _generate_build!
          wtype = @_wire_type
          props_list = @_props
          children_mode = @_children_mode
          container = _container?

          define_method(:build) do
            # Validate children constraints.
            case children_mode
            when :single
              Build.validate_single_child!(@id, wtype, @children)
            when Integer
              Build.validate_children_count!(@id, wtype, @children, children_mode)
            end

            # Build props hash, skipping nils.
            props = {}
            props_list.each do |name|
              val = instance_variable_get(:"@#{name}")
              props[name] = val unless val.nil?
            end

            if container
              Node.new(id: @id, type: wtype, props: props,
                children: Build.children_to_nodes(@children))
            else
              Node.new(id: @id, type: wtype, props: props)
            end
          end
        end
      end
    end
  end
end
