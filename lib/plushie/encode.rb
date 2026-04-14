# frozen_string_literal: true

module Plushie
  # Value encoding for the wire protocol.
  #
  # The single canonical encoding path for all prop values. Called by
  # Tree.normalize on each prop value and by Tree::Diff when encoding
  # changed props in patch operations.
  #
  # Encoding rules:
  # - true, false, nil, Integer, Float, String: pass through
  # - Symbol: converted to string
  # - Array: recursive encode
  # - Hash: keys to strings, values recursive encode
  # - Objects with +to_wire+: call to_wire, then encode the result
  # - Objects with +to_h+: convert to hash, then encode
  # - Unknown: raise ArgumentError (fail-fast, no silent passthrough)
  module Encode
    module_function

    # Encode a single value for the wire protocol.
    #
    # @param value [Object] any Ruby value
    # @return [Object] wire-safe value (primitives, strings, arrays, hashes)
    # @raise [ArgumentError] if value cannot be encoded
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
        acc = {} #: Hash[untyped, untyped]
        value.each_with_object(acc) do |(k, v), h|
          h[k.is_a?(Symbol) ? k.to_s : k] = encode_value(v)
        end
      else
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

    # Encode a props hash for the wire protocol.
    #
    # Converts all keys to strings and all values via {encode_value}.
    # Used by Tree.node_to_wire and Tree::Diff for patch operations.
    #
    # @param props [Hash] prop hash (symbol or string keys)
    # @return [Hash{String => Object}] wire-ready props
    def encode_props(props)
      result = {} #: Hash[String, untyped]
      props.each do |k, v|
        result[k.to_s] = encode_value(v)
      end
      result
    end
  end
end
