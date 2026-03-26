# frozen_string_literal: true

require "fileutils"

module Plushie
  module Test
    # Test helper methods for interacting with a Plushie test session.
    #
    # Include this module in your test class to get click, find!, assert_text,
    # and other helpers. The session is stored in Thread.current.
    #
    # @example With Minitest
    #   class CounterTest < Plushie::Test::Case
    #     app Counter
    #     def test_increment
    #       click("#increment")
    #       assert_text "#count", "Count: 1"
    #     end
    #   end
    #
    # @see ~/projects/toddy-elixir/lib/plushie/test/helpers.ex
    module Helpers
      # @return [Session] the current test session
      def session
        Thread.current[:_plushie_test_session] ||
          raise("No Plushie test session. Use Plushie::Test::Case or call plushie_start first.")
      end

      # -- Interactions --------------------------------------------------------

      # Click a button widget.
      # @param selector [String] "#id" or "text content"
      def click(selector) = session.click(selector)

      # Type text into a text_input or text_editor.
      # @param selector [String]
      # @param text [String]
      def type_text(selector, text) = session.type_text(selector, text)

      # Submit a text_input (press Enter).
      # @param selector [String]
      def submit(selector) = session.submit(selector)

      # Toggle a checkbox or toggler.
      # @param selector [String]
      def toggle(selector) = session.toggle(selector)

      # Select a value from pick_list, combo_box, or radio.
      # @param selector [String]
      # @param value [String]
      def select(selector, value) = session.select(selector, value)

      # Slide a slider to a value.
      # @param selector [String]
      # @param value [Numeric]
      def slide(selector, value) = session.slide(selector, value)

      # Press a key (key down).
      # @param key [String]
      def press(key) = session.press(key)

      # Release a key (key up).
      # @param key [String]
      def release(key) = session.release(key)

      # Type a key (press + release).
      # @param key [String]
      def type_key(key) = session.type_key(key)

      # Move cursor to coordinates.
      # @param x [Numeric]
      # @param y [Numeric]
      def move_to(x, y) = session.move_to(x, y)

      # Click a canvas element by injecting a synthetic canvas_element_click event.
      # @param canvas_id [String] the canvas widget ID (e.g. "#chart")
      # @param element_id [String] the element ID within the canvas
      def click_element(canvas_id, element_id) = session.interact("canvas_element_click", canvas_id, {"element_id" => element_id})

      # Focus a canvas element by sending a focus_element command.
      # @param canvas_id [String] the canvas widget ID
      # @param element_id [String] the element ID within the canvas
      def focus_element(canvas_id, element_id) = session.command(Command.focus_element(canvas_id, element_id))

      # -- Queries -------------------------------------------------------------

      # Find a widget by selector. Returns the node hash or nil.
      # @param selector [String]
      # @return [Hash, nil]
      def find(selector) = session.find(selector)

      # Find a widget by selector. Raises if not found.
      # @param selector [String]
      # @return [Hash]
      def find!(selector) = session.find!(selector)

      # @return [Object] current app model
      def model = session.model

      # @return [Hash] current tree from the renderer
      def tree = session.tree

      # Extract text content from an element hash.
      # @param element [Hash]
      # @return [String, nil]
      def text(element) = session.element_text(element)

      # Capture a structural tree hash.
      # @param name [String]
      # @return [Hash]
      def tree_hash(name) = session.tree_hash(name)

      # Capture a screenshot.
      # @param name [String]
      # @return [Hash]
      def screenshot(name, **opts) = session.screenshot(name, **opts)

      # Reset the session to initial state.
      def reset = session.reset

      # Wait for a tagged async task to complete.
      # In test mode, async commands run synchronously, so this is
      # effectively a no-op. Exists for API compatibility.
      #
      # @param tag [Symbol] the async command tag
      # @param timeout [Integer] max wait in milliseconds (unused)
      # @return [:ok]
      def await_async(tag, timeout = 5000)
        :ok
      end

      # Register an effect stub with the renderer.
      # The renderer will return the given response immediately for
      # any effect of the given kind.
      #
      # @param kind [String] effect kind (e.g. "clipboard_read")
      # @param response [Object] the canned response to return
      def register_effect_stub(kind, response)
        session.register_effect_stub(kind, response)
      end

      # Remove a previously registered effect stub.
      #
      # @param kind [String] effect kind
      def unregister_effect_stub(kind)
        session.unregister_effect_stub(kind)
      end

      # Assert that no prop validation diagnostics have been emitted.
      # Clears the diagnostic list after checking.
      #
      # @raise [Minitest::Assertion] if diagnostics are pending
      def assert_no_diagnostics
        diagnostics = session.get_diagnostics
        return if diagnostics.empty?

        details = diagnostics.map { |d| "  - #{d.data.inspect}" }.join("\n")
        flunk "Expected no prop validation diagnostics, but found:\n#{details}"
      end

      # Find a widget by accessibility role.
      # @param role [Symbol, String] e.g. :button, "textbox"
      # @return [Hash, nil]
      def find_by_role(role)
        session.find({by: "role", value: role.to_s})
      end

      # Find a widget by accessibility label.
      # @param label [String]
      # @return [Hash, nil]
      def find_by_label(label)
        session.find({by: "label", value: label})
      end

      # Find the currently focused widget.
      # @return [Hash, nil]
      def find_focused
        session.find({by: "focused"})
      end

      # Capture a screenshot and save as PNG to test/screenshots/.
      # @param name [String] screenshot name
      # @return [Hash] screenshot response
      def save_screenshot(name, **opts)
        result = screenshot(name, **opts)
        if result && (rgba = result[:rgba] || result["rgba"])
          dir = "test/screenshots"
          FileUtils.mkdir_p(dir)
          File.binwrite(File.join(dir, "#{name}.rgba"), rgba)
        end
        result
      end

      # -- Assertions ----------------------------------------------------------

      # Assert that a widget contains the expected text.
      # @param selector [String]
      # @param expected [String]
      def assert_text(selector, expected)
        element = find!(selector)
        actual = text(element)
        assert_equal expected, actual,
          "Expected text #{expected.inspect} for #{selector}, got #{actual.inspect}"
      end

      # Assert that a widget exists.
      # @param selector [String]
      def assert_exists(selector)
        result = find(selector)
        assert result, "Expected widget #{selector} to exist, but it was not found"
      end

      # Assert that a widget does NOT exist.
      # @param selector [String]
      def assert_not_exists(selector)
        result = find(selector)
        assert_nil result, "Expected widget #{selector} not to exist, but it was found"
      end

      # Assert model equals expected value.
      # @param expected [Object]
      def assert_model(expected)
        assert_equal expected, model
      end

      # -- Session lifecycle (for non-Case usage) ------------------------------

      # Start a test session manually.
      # @param app_class [Class]
      def plushie_start(app_class, **opts)
        pool = Plushie::Test.pool
        session_id = pool.register
        Thread.current[:_plushie_test_session] = Session.new(app_class, pool: pool, session_id: session_id)
      end

      # Stop the current test session.
      def plushie_stop
        Thread.current[:_plushie_test_session]&.stop
        Thread.current[:_plushie_test_session] = nil
      end
    end
  end
end
