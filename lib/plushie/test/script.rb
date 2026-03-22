# frozen_string_literal: true

module Plushie
  module Test
    # Parser for the .plushie script format.
    #
    # A .plushie file has a YAML-style header (key: value lines) separated
    # from the instruction body by a line of five or more dashes.
    #
    # Header keys: app, viewport, theme, backend
    # Instructions: click, type, type_key, press, release, expect,
    #   tree_hash, screenshot, assert_text, assert_model, wait, move
    #
    # @example
    #   app Counter
    #   viewport 800x600
    #   theme dark
    #   -----
    #   click "#increment"
    #   click "#increment"
    #   assert_text "#count" "Count: 2"
    module Script
      # Parsed representation of a .plushie script.
      ParsedScript = Data.define(:header, :instructions)

      # A single instruction from the script body.
      Instruction = Data.define(:command, :args)

      module_function

      # Parse a .plushie script string into header + instructions.
      #
      # @param source [String] script content
      # @return [ParsedScript]
      def parse(source)
        lines = source.lines.map(&:chomp)
        separator_index = lines.index { |l| l.match?(/\A-{5,}\z/) }

        header_lines = separator_index ? lines[0...separator_index] : []
        body_lines = separator_index ? lines[(separator_index + 1)..] : lines

        header = parse_header(header_lines)
        instructions = parse_body(body_lines)

        ParsedScript.new(header: header, instructions: instructions)
      end

      # Parse a .plushie script file.
      #
      # @param path [String] file path
      # @return [ParsedScript]
      def parse_file(path)
        parse(File.read(path))
      end

      # Parse header lines into a hash.
      #
      # @param lines [Array<String>]
      # @return [Hash{String => String}]
      def parse_header(lines)
        header = {}
        lines.each do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")
          key, _, value = line.partition(/\s+/)
          header[key] = value.strip if key && !key.empty?
        end
        header
      end

      # Parse body lines into instruction structs.
      #
      # @param lines [Array<String>]
      # @return [Array<Instruction>]
      def parse_body(lines)
        instructions = []
        lines.each do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          tokens = tokenize(line)
          next if tokens.empty?

          command = tokens.shift
          instructions << Instruction.new(command: command, args: tokens)
        end
        instructions
      end

      # Tokenize a script line, respecting quoted strings.
      #
      # @param line [String]
      # @return [Array<String>]
      def tokenize(line)
        tokens = []
        scanner = line.dup
        until scanner.empty?
          scanner.lstrip!
          break if scanner.empty?

          if scanner.start_with?('"')
            # Quoted string
            scanner = scanner[1..]
            end_quote = scanner.index('"')
            if end_quote
              tokens << scanner[0...end_quote]
              scanner = scanner[(end_quote + 1)..]
            else
              # Unterminated quote -- take the rest
              tokens << scanner
              break
            end
          else
            # Unquoted token
            space = scanner.index(/\s/)
            if space
              tokens << scanner[0...space]
              scanner = scanner[space..]
            else
              tokens << scanner
              break
            end
          end
        end
        tokens
      end
    end
  end
end
