# frozen_string_literal: true

module Plushie
  module Widget
    class Image
      PROPS = %i[source width height content_fit rotation opacity border_radius
        filter_method expand scale crop alt description decorative a11y].freeze

      attr_reader :id, *PROPS

      def initialize(id, source = nil, **opts)
        @id = id.to_s
        @source = source
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @source = opts[:source] if opts.key?(:source)
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      def build
        props = {}
        PROPS.each do |key|
          val = instance_variable_get(:"@#{key}")
          Build.put_if(props, key, val)
        end
        Node.new(id: @id, type: "image", props: props)
      end
    end
  end
end
