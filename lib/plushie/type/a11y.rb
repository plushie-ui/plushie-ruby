# frozen_string_literal: true

module Plushie
  module Type
    # Accessibility properties for widgets.
    #
    # Any tree node can carry an `a11y` hash in its props to control
    # accessibility behaviour. All fields are optional.
    #
    # @example
    #   button("save", "Save", a11y: { label: "Save document", description: "Saves to disk" })
    #
    # @example Full struct
    #   A11y.from_opts(role: :button, label: "Submit", description: "Send the form")
    module A11y
      # Recognized field keys for accessibility specs.
      # @api private
      FIELD_KEYS = %i[
        role label description hidden expanded required level live
        busy invalid modal read_only mnemonic toggled selected value
        orientation labelled_by described_by error_message disabled
        position_in_set size_of_set has_popup
      ].freeze

      # Valid accessibility roles.
      # @api private
      VALID_ROLES = %i[
        alert alertdialog application article banner button cell
        checkbox columnheader combobox complementary contentinfo
        definition dialog directory document feed figure form grid
        gridcell group heading img link list listbox listitem log
        main marquee math menu menubar menuitem menuitemcheckbox
        menuitemradio navigation none note option presentation
        progressbar radio radiogroup region row rowgroup rowheader
        scrollbar search searchbox separator slider spinbutton
        status switch tab tablist tabpanel term textbox timer toolbar
        tooltip tree treegrid treeitem
      ].freeze

      # Immutable spec; use {#with} to create modified copies.
      Spec = Data.define(*FIELD_KEYS) do
        def initialize(**fields)
          defaults = FIELD_KEYS.each_with_object({}) { |k, h| h[k] = nil }
          super(**defaults.merge(fields))
        end

        # Returns a copy with the given fields updated.
        def with(**changes)
          self.class.new(**to_h.merge(changes))
        end

        # @return [Hash] wire-ready map with nil fields stripped
        def to_wire
          to_h.compact
        end
      end

      module_function

      # Construct from keyword options.
      # @param opts [Hash] any combination of A11y fields
      # @return [Spec]
      def from_opts(opts)
        Spec.new(**opts.slice(*FIELD_KEYS))
      end

      # Normalise any a11y input to a wire-ready hash.
      # @param value [Spec, Hash, nil]
      # @return [Hash, nil]
      def cast(value)
        case value
        when Spec then value.to_wire
        when Hash then value.compact
        when nil then nil
        else raise ArgumentError, "invalid a11y: #{value.inspect}"
        end
      end

      # Encode for the wire protocol.
      # @param value [Spec, Hash, nil]
      # @return [Hash, nil]
      def encode(value)
        cast(value)
      end
    end
  end
end
