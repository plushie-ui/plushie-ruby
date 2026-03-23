# frozen_string_literal: true

module Plushie
  # Convenience wrapper around Data.define that adds a #with method
  # for partial updates, producing a new immutable instance.
  #
  #   Model = Plushie::Model.define(:count, :name)
  #   m = Model.new(count: 0, name: "test")
  #   m.with(count: 1) # => Model(count: 1, name: "test")
  #
  # Instances are frozen by default (inherited from Data). Attempting
  # to mutate raises FrozenError.
  module Model
    # Define a new model class with the given attributes.
    def self.define(*fields)
      klass = Data.define(*fields)
      klass.include(Extensions)
      klass
    end

    # Methods mixed into Model classes.
    # @api private
    module Extensions
      # Return a new instance with the given fields replaced.
      # Unspecified fields carry over from the current instance.
      #
      #   model.with(count: model.count + 1)
      #
      def with(**changes)
        self.class.new(**to_h.merge(changes))
      end
    end
  end
end
