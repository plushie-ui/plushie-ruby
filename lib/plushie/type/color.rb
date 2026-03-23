# frozen_string_literal: true

module Plushie
  module Type
    # Color type for widget properties.
    #
    # All colors are canonical hex strings: "#rrggbb" or "#rrggbbaa".
    # Short forms (#rgb, #rgba) are NOT accepted by the renderer -- the
    # SDK normalises all input to 6-char or 8-char hex.
    #
    # Supports all 148 CSS Color Module Level 4 named colors plus :transparent.
    #
    # @example Named color
    #   text("msg", "Hello", color: :red)
    #   text("msg", "Hello", color: :cornflowerblue)
    #
    # @example Hex string
    #   text("msg", "Hello", color: "#ff8800")
    #   text("msg", "Hello", color: "#ff880080")  # with alpha
    #
    # @example RGB constructor
    #   Color.from_rgb(255, 128, 0)   # => "#ff8000"
    #   Color.from_rgba(255, 128, 0, 128) # => "#ff800080"
    module Color
      # All 148 CSS Color Module Level 4 named colors + transparent.
      NAMED_COLORS = {
        aliceblue: "#f0f8ff", antiquewhite: "#faebd7", aqua: "#00ffff",
        aquamarine: "#7fffd4", azure: "#f0ffff", beige: "#f5f5dc",
        bisque: "#ffe4c4", black: "#000000", blanchedalmond: "#ffebcd",
        blue: "#0000ff", blueviolet: "#8a2be2", brown: "#a52a2a",
        burlywood: "#deb887", cadetblue: "#5f9ea0", chartreuse: "#7fff00",
        chocolate: "#d2691e", coral: "#ff7f50", cornflowerblue: "#6495ed",
        cornsilk: "#fff8dc", crimson: "#dc143c", cyan: "#00ffff",
        darkblue: "#00008b", darkcyan: "#008b8b", darkgoldenrod: "#b8860b",
        darkgray: "#a9a9a9", darkgreen: "#006400", darkgrey: "#a9a9a9",
        darkkhaki: "#bdb76b", darkmagenta: "#8b008b", darkolivegreen: "#556b2f",
        darkorange: "#ff8c00", darkorchid: "#9932cc", darkred: "#8b0000",
        darksalmon: "#e9967a", darkseagreen: "#8fbc8f", darkslateblue: "#483d8b",
        darkslategray: "#2f4f4f", darkslategrey: "#2f4f4f",
        darkturquoise: "#00ced1", darkviolet: "#9400d3", deeppink: "#ff1493",
        deepskyblue: "#00bfff", dimgray: "#696969", dimgrey: "#696969",
        dodgerblue: "#1e90ff", firebrick: "#b22222", floralwhite: "#fffaf0",
        forestgreen: "#228b22", fuchsia: "#ff00ff", gainsboro: "#dcdcdc",
        ghostwhite: "#f8f8ff", gold: "#ffd700", goldenrod: "#daa520",
        gray: "#808080", green: "#008000", greenyellow: "#adff2f",
        grey: "#808080", honeydew: "#f0fff0", hotpink: "#ff69b4",
        indianred: "#cd5c5c", indigo: "#4b0082", ivory: "#fffff0",
        khaki: "#f0e68c", lavender: "#e6e6fa", lavenderblush: "#fff0f5",
        lawngreen: "#7cfc00", lemonchiffon: "#fffacd", lightblue: "#add8e6",
        lightcoral: "#f08080", lightcyan: "#e0ffff",
        lightgoldenrodyellow: "#fafad2", lightgray: "#d3d3d3",
        lightgreen: "#90ee90", lightgrey: "#d3d3d3", lightpink: "#ffb6c1",
        lightsalmon: "#ffa07a", lightseagreen: "#20b2aa",
        lightskyblue: "#87cefa", lightslategray: "#778899",
        lightslategrey: "#778899", lightsteelblue: "#b0c4de",
        lightyellow: "#ffffe0", lime: "#00ff00", limegreen: "#32cd32",
        linen: "#faf0e6", magenta: "#ff00ff", maroon: "#800000",
        mediumaquamarine: "#66cdaa", mediumblue: "#0000cd",
        mediumorchid: "#ba55d3", mediumpurple: "#9370db",
        mediumseagreen: "#3cb371", mediumslateblue: "#7b68ee",
        mediumspringgreen: "#00fa9a", mediumturquoise: "#48d1cc",
        mediumvioletred: "#c71585", midnightblue: "#191970",
        mintcream: "#f5fffa", mistyrose: "#ffe4e1", moccasin: "#ffe4b5",
        navajowhite: "#ffdead", navy: "#000080", oldlace: "#fdf5e6",
        olive: "#808000", olivedrab: "#6b8e23", orange: "#ffa500",
        orangered: "#ff4500", orchid: "#da70d6", palegoldenrod: "#eee8aa",
        palegreen: "#98fb98", paleturquoise: "#afeeee",
        palevioletred: "#db7093", papayawhip: "#ffefd5",
        peachpuff: "#ffdab9", peru: "#cd853f", pink: "#ffc0cb",
        plum: "#dda0dd", powderblue: "#b0e0e6", purple: "#800080",
        rebeccapurple: "#663399", red: "#ff0000", rosybrown: "#bc8f8f",
        royalblue: "#4169e1", saddlebrown: "#8b4513", salmon: "#fa8072",
        sandybrown: "#f4a460", seagreen: "#2e8b57", seashell: "#fff5ee",
        sienna: "#a0522d", silver: "#c0c0c0", skyblue: "#87ceeb",
        slateblue: "#6a5acd", slategray: "#708090", slategrey: "#708090",
        snow: "#fffafa", springgreen: "#00ff7f", steelblue: "#4682b4",
        tan: "#d2b48c", teal: "#008080", thistle: "#d8bfd8",
        tomato: "#ff6347", transparent: "#00000000", turquoise: "#40e0d0",
        violet: "#ee82ee", wheat: "#f5deb3", white: "#ffffff",
        whitesmoke: "#f5f5f5", yellow: "#ffff00", yellowgreen: "#9acd32"
      }.freeze

      # Pattern for 3-digit hex colors.
      # @api private
      HEX3_RE = /\A#[0-9a-fA-F]{3}\z/
      # Pattern for 4-digit hex colors.
      # @api private
      HEX4_RE = /\A#[0-9a-fA-F]{4}\z/
      # Pattern for 6-digit hex colors.
      # @api private
      HEX6_RE = /\A#[0-9a-fA-F]{6}\z/
      # Pattern for 8-digit hex colors.
      # @api private
      HEX8_RE = /\A#[0-9a-fA-F]{8}\z/

      module_function

      # Construct a color from RGB components (0-255).
      #
      # @param r [Integer] red (0-255)
      # @param g [Integer] green (0-255)
      # @param b [Integer] blue (0-255)
      # @return [String] "#rrggbb"
      def from_rgb(r, g, b)
        "#%02x%02x%02x" % [r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255)]
      end

      # Construct a color from RGBA components (0-255).
      #
      # @param r [Integer] red (0-255)
      # @param g [Integer] green (0-255)
      # @param b [Integer] blue (0-255)
      # @param a [Integer] alpha (0-255)
      # @return [String] "#rrggbbaa"
      def from_rgba(r, g, b, a)
        "#%02x%02x%02x%02x" % [r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), a.clamp(0, 255)]
      end

      # Normalise a hex string to the canonical "#rrggbb" or "#rrggbbaa" form.
      # Accepts with or without the leading "#". Short forms (#rgb, #rgba)
      # are expanded by doubling each digit.
      #
      # @param hex [String] hex color string
      # @return [String] "#rrggbb" or "#rrggbbaa"
      def from_hex(hex)
        hex = "##{hex}" unless hex.start_with?("#")
        hex = hex.downcase

        # Expand short forms: #rgb -> #rrggbb, #rgba -> #rrggbbaa
        if hex.match?(HEX3_RE)
          hex = "##{hex[1] * 2}#{hex[2] * 2}#{hex[3] * 2}"
        elsif hex.match?(HEX4_RE)
          hex = "##{hex[1] * 2}#{hex[2] * 2}#{hex[3] * 2}#{hex[4] * 2}"
        end

        unless hex.match?(HEX6_RE) || hex.match?(HEX8_RE)
          raise ArgumentError, "invalid hex color: #{hex.inspect}. Expected #rgb, #rgba, #rrggbb, or #rrggbbaa"
        end
        hex
      end

      # Normalise any supported color input to a canonical hex string.
      #
      # Accepts: named color symbol (:red), named color string ("red"),
      # hex string ("#ff0000" or "ff0000"), or an already-canonical hex string.
      #
      # @param value [Symbol, String] color input
      # @return [String] "#rrggbb" or "#rrggbbaa"
      def cast(value)
        case value
        when Symbol
          NAMED_COLORS.fetch(value) { raise ArgumentError, "unknown named color: #{value.inspect}" }
        when String
          if value.start_with?("#")
            from_hex(value)
          elsif NAMED_COLORS.key?(value.to_sym)
            NAMED_COLORS[value.to_sym]
          else
            from_hex(value)
          end
        else
          raise ArgumentError, "invalid color: #{value.inspect}. Use a hex string or named color symbol"
        end
      end

      # Encode a color for the wire protocol. Alias for cast.
      #
      # @param value [Symbol, String]
      # @return [String]
      def encode(value)
        cast(value)
      end
    end
  end
end
