# frozen_string_literal: true

module Plushie
  # Value encoding for the wire protocol.
  #
  # Converts Ruby values to wire-safe representations during tree
  # normalization. Called by Tree.normalize on each prop value.
  #
  # Encoding rules:
  # - true, false, nil, Integer, Float, String -> pass through
  # - Symbol -> string (except true/false/nil which are not symbols in Ruby)
  # - Array -> recursive encode
  # - Hash -> recursive encode values (keys to strings)
  # - Type module instances (Padding::Pad, Border::Spec, etc.) -> call to_wire
  # - Unknown -> raise (fail-fast, no silent passthrough)
  module Encode
    module_function

    # Encode a value for the wire protocol.
    #
    # @param value [Object] any Ruby value
    # @return [Object] wire-safe value
    def encode_value(value)
      case value
      when true, false, nil, Integer, Float
        value
      when String
        value
      when Symbol
        value.to_s
      when Array
        value.map { |v| encode_value(v) }
      when Hash
        value.each_with_object({}) do |(k, v), h|
          h[k.is_a?(Symbol) ? k.to_s : k] = encode_value(v)
        end
      else
        # Check for types that respond to to_wire (our typed structs)
        if value.respond_to?(:to_wire)
          encode_value(value.to_wire)
        elsif value.respond_to?(:to_h)
          encode_value(value.to_h)
        else
          raise ArgumentError,
            "cannot encode #{value.class} for wire protocol: #{value.inspect}. " \
            "Implement #to_wire or convert to a primitive type."
        end
      end
    end
  end
end
