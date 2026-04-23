# frozen_string_literal: true

module Plushie
  # Create widget set modules that override built-in widget DSL methods.
  #
  # A widget set re-exports all of Plushie::UI but replaces specific
  # widget methods with alternatives:
  #
  #   MaterialUI = Plushie::WidgetSet.create(
  #     button: MyApp::MaterialButton,
  #     text_input: MyApp::MaterialTextInput
  #   )
  #
  #   # In view methods:
  #   include MaterialUI
  #   button("save", "Save")  # uses MaterialButton
  #
  # Override widget classes must respond to +new(id, *args, **opts)+
  # and +#build+ (returning a Node), matching the Widget.define API.
  #
  module WidgetSet
    # Create a widget set module with the given overrides.
    #
    # @param overrides [Hash{Symbol => Class}] widget name -> replacement class
    # @return [Module] a module that can be included for the overridden DSL
    def self.create(**overrides)
      # Validate all override names are actual UI methods
      ui_methods = Plushie::UI.private_instance_methods(false) +
        Plushie::UI.instance_methods(false)

      overrides.each_key do |name|
        unless ui_methods.include?(name)
          raise ArgumentError,
            "#{name.inspect} is not a Plushie::UI widget method. " \
            "Available: #{ui_methods.sort.inspect}"
        end
      end

      Module.new do
        include Plushie::UI

        overrides.each do |name, widget_class|
          define_method(name) do |id, *args, **opts, &block|
            builder = widget_class.new(id, *args, **opts)
            if block
              unless builder.respond_to?(:push)
                raise ArgumentError,
                  "#{name} override #{widget_class} does not accept children"
              end

              children = []
              UI::Context.push(children)
              begin
                block.call
              ensure
                UI::Context.pop
              end
              children.each do |child|
                next_builder = builder.push(child)
                builder = next_builder if next_builder
              end
            end
            node = builder.build
            ctx = UI::Context.current
            ctx << node if ctx&.none? { |child| child.equal?(node) }
            node
          end
          private name
        end
      end
    end
  end
end
