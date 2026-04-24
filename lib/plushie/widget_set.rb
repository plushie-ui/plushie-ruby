# frozen_string_literal: true

require_relative "node"
require_relative "canvas/shape"
require_relative "ui"

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
    OVERRIDEABLE_WIDGET_METHODS = %i[
      button canvas checkbox column combo_box container floating grid image
      keyed_column markdown overlay pane_grid pick_list pin pointer_area
      progress_bar qr_code radio responsive rich_text row rule scrollable
      sensor slider space stack svg table table_row cell text text_editor
      text_input themer toggler tooltip vertical_slider window
    ].freeze
    private_constant :OVERRIDEABLE_WIDGET_METHODS

    # Create a widget set module with the given overrides.
    #
    # @param overrides [Hash{Symbol => Class}] widget name -> replacement class
    # @return [Module] a module that can be included for the overridden DSL
    def self.create(**overrides)
      overrides.each_key do |name|
        unless OVERRIDEABLE_WIDGET_METHODS.include?(name)
          raise ArgumentError,
            "#{name.inspect} is not a Plushie::UI widget method. " \
            "Available: #{OVERRIDEABLE_WIDGET_METHODS.sort.inspect}"
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
