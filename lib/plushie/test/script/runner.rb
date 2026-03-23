# frozen_string_literal: true

module Plushie
  module Test
    module Script
      # Executes a parsed .plushie script against a test session.
      #
      # Creates a Session from the header's app declaration, then
      # runs each instruction sequentially.
      #
      # @example
      #   parsed = Plushie::Test::Script.parse_file("test/scripts/counter.plushie")
      #   runner = Plushie::Test::Script::Runner.new(parsed)
      #   runner.run
      class Runner
        # @param script [ParsedScript] parsed script
        # @param pool [SessionPool, nil] override pool (uses default if nil)
        def initialize(script, pool: nil)
          @script = script
          @pool = pool || Plushie::Test.pool
          @session = nil
        end

        # Execute the script.
        #
        # @return [Session] the session after execution
        def run
          app_class = resolve_app_class(@script.header["app"])
          session_id = @pool.register
          @session = Session.new(app_class, pool: @pool, session_id: session_id)

          @script.instructions.each do |instruction|
            execute(instruction)
          end

          @session
        ensure
          @session&.stop
        end

        private

        # Resolve an app class name string to a constant.
        #
        # @param name [String] e.g. "Counter" or "MyApp::Main"
        # @return [Class]
        def resolve_app_class(name)
          raise "No app declared in script header" unless name && !name.empty?
          Object.const_get(name)
        end

        # Execute a single instruction.
        #
        # @param instruction [Instruction]
        def execute(instruction)
          case instruction.command
          when "click"
            @session.click(instruction.args[0])
          when "type"
            @session.type_text(instruction.args[0], instruction.args[1])
          when "type_key"
            @session.type_key(instruction.args[0])
          when "press"
            @session.press(instruction.args[0])
          when "release"
            @session.release(instruction.args[0])
          when "expect"
            expected = instruction.args[0]
            tree = @session.tree
            json = tree.is_a?(String) ? tree : tree.to_s
            unless json.include?(expected)
              raise "expect failed: #{expected.inspect} not found in tree"
            end
          when "tree_hash"
            @session.tree_hash(instruction.args[0])
          when "screenshot"
            @session.screenshot(instruction.args[0])
          when "assert_text"
            selector = instruction.args[0]
            expected = instruction.args[1]
            element = @session.find!(selector)
            actual = @session.element_text(element)
            unless actual == expected
              raise "assert_text failed: expected #{expected.inspect} for #{selector}, got #{actual.inspect}"
            end
          when "assert_model"
            # Evaluate the expression in the context of the model.
            # In script mode, this is limited to string comparison.
            expected = instruction.args[0]
            actual = @session.model.to_s
            unless actual == expected
              raise "assert_model failed: expected #{expected.inspect}, got #{actual.inspect}"
            end
          when "wait"
            seconds = Float(instruction.args[0])
            sleep(seconds)
          when "move"
            coords = instruction.args[0].split(",")
            x = Float(coords[0])
            y = Float(coords[1])
            @session.move_to(x, y)
          else
            raise "Unknown script instruction: #{instruction.command}"
          end
        end
      end
    end
  end
end
