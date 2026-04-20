# frozen_string_literal: true

module Plushie
  module Widget
    Checkbox = Plushie::Widget.define(:checkbox) do
      children :none
      positional :label
      positional :is_toggled, default: false
      prop :label, :is_toggled, :spacing, :width, :size, :text_size, :font,
        :line_height, :shaping, :wrapping, :style, :icon, :disabled,
        :required, :validation
      prop :a11y, :event_rate
      default_a11y role: :check_box, label_from: :label
    end

    # Checkbox widget with boolean toggle state.
    #
    # @example
    #   Checkbox.new("agree", "I agree", true).build
    class Checkbox
      # Remap :is_toggled to :checked on the wire.
      module CheckedRemap
        # Remap :is_toggled prop to :checked on the wire.
        # @api private
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
