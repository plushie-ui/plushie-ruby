# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the checkbox widget (Layer 2 API).
    #
    # Construct a Checkbox, set properties via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node} for the view tree.
    class Checkbox < BuiltIn
      wire_type :checkbox
      children :none
      positional :label
      positional :is_toggled, default: false
      prop :label, :is_toggled, :spacing, :width, :size, :text_size, :font,
        :line_height, :shaping, :wrapping, :style, :icon, :disabled, :a11y

      # Remap :is_toggled to :checked on the wire via prepend so
      # the override survives lazy finalization.
      module CheckedRemap
        def build
          node = super
          props = node.props.dup
          if props.key?(:is_toggled)
            props[:checked] = props.delete(:is_toggled)
          end
          Node.new(id: node.id, type: node.type, props: props)
        end
      end
      prepend CheckedRemap
    end
  end
end
