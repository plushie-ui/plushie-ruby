# frozen_string_literal: true

module Plushie
  module DSL
    # Behaviour for types that participate in the DSL block-form pattern.
    #
    # Types that include this module can be constructed from keyword options
    # inside DSL do-blocks:
    #
    #   container "box" do
    #     border do        # <- Buildable: Border.from_opts called with
    #       color "#333"   #    collected keyword pairs
    #       width 2
    #     end
    #   end
    #
    # Implementing types must define:
    # - `self.from_opts(hash)` - construct from keyword hash
    # - `self.field_keys` - array of valid field name symbols
    # - `self.field_types` - hash of field name -> nested type module (for recursive do-blocks)
    #
    # Currently implemented by: Padding, Border, Shadow, Font, StyleMap, A11y
    module Buildable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Override in implementing module.
        # @return [Array<Symbol>] valid field names
        def field_keys
          raise NotImplementedError, "#{self} must define .field_keys"
        end

        # Override in implementing module.
        # @return [Hash{Symbol => Module}] nested type modules for recursive do-blocks
        def field_types
          {}
        end
      end
    end
  end
end
