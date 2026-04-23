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
      def click_element(canvas_id, element_id) = session.interact("canvas_element_click", canvas_id, element_id: element_id)

      # Focus a canvas element via scoped path.
      # Use Command.focus("canvas/element") for the same effect.
      # @param canvas_id [String] the canvas widget ID
      # @param element_id [String] the element ID within the canvas
      def focus_element(canvas_id, element_id)
        session.command(Command.focus("#{canvas_id}/#{element_id}"))
      end

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
      # @param kind [Symbol, String] effect kind (e.g. :clipboard_read)
      # @param response [Object] the canned response to return
      def register_effect_stub(kind, response)
        session.register_effect_stub(kind.to_s, response)
      end

      # Remove a previously registered effect stub.
      #
      # @param kind [Symbol, String] effect kind
      def unregister_effect_stub(kind)
        session.unregister_effect_stub(kind.to_s)
      end

      # Assert that no diagnostics have been emitted by the renderer.
      # Clears the diagnostic list after checking.
      #
      # @raise [Minitest::Assertion] if diagnostics are pending
      def assert_no_diagnostics
        diagnostics = session.get_diagnostics
        return if diagnostics.empty?

        details = diagnostics.map { |d| "  - #{d.diagnostic.inspect}" }.join("\n")
        plushie_flunk "Expected no diagnostics, but found:\n#{details}"
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

      # -- Animation helpers ---------------------------------------------------

      # Advance the renderer's animation clock to the given timestamp.
      # Causes the renderer to evaluate all active animations at that
      # point in time, potentially triggering transition_complete events.
      #
      # @param timestamp [Integer] animation clock time in milliseconds
      def advance_frame(timestamp)
        session.command(Command.advance_frame(timestamp))
      end

      # Skip all active renderer-side transitions to completion.
      #
      # Advances the animation clock far enough to complete any reasonable
      # animation. Triggers transition_complete events for any animations
      # with on_complete tags.
      def skip_transitions
        advance_frame(10_000)
      end

      # -- Assertions ----------------------------------------------------------

      # Assert that a widget contains the expected text.
      # @param selector [String]
      # @param expected [String]
      def assert_text(selector, expected)
        element = find!(selector)
        actual = text(element)
        plushie_assert_equal expected, actual,
          "Expected text #{expected.inspect} for #{selector}, got #{actual.inspect}"
      end

      # Assert that a widget exists.
      # @param selector [String]
      def assert_exists(selector)
        result = find(selector)
        plushie_assert result, "Expected widget #{selector} to exist, but it was not found"
      end

      # Assert that a widget does NOT exist.
      # @param selector [String]
      def assert_not_exists(selector)
        result = find(selector)
        plushie_assert_nil result, "Expected widget #{selector} not to exist, but it was found"
      end

      # Assert model equals expected value.
      # @param expected [Object]
      def assert_model(expected)
        plushie_assert_equal expected, model
      end

      # Return the resolved a11y hash for a widget.
      #
      # Layers render-pipeline inference (placeholder -> description for
      # text-entry widgets, alt -> label for media widgets) on top of
      # the normalized `a11y` prop so tests see what assistive
      # technology will see. Normalizer-populated defaults (role,
      # implicit radio_group, required/validation projections, tooltip
      # described_by) are already carried on the tree.
      #
      # @param selector [String]
      # @return [Hash] symbol-keyed a11y map (empty if no state)
      def resolved_a11y(selector)
        element = find!(selector)
        ::Plushie::Test::Helpers.resolve_a11y_for_element(element)
      end

      # Assert that a widget's resolved a11y matches expected values.
      # Reads through {#resolved_a11y} so inferred defaults compose
      # with the author's explicit overrides.
      #
      # @param selector [String]
      # @param expected [Hash] expected key-value pairs
      def assert_a11y(selector, expected)
        a11y = resolved_a11y(selector)
        expected.each do |key, value|
          actual = a11y[key] || a11y[key.to_s]
          plushie_assert_equal value, actual,
            "a11y #{key.inspect} mismatch for #{selector}\nFull a11y: #{a11y.inspect}"
        end
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

      private

      def plushie_assert_equal(expected, actual, message = nil)
        return assert_equal(expected, actual, message) if respond_to?(:assert_equal)
        return if expected == actual

        plushie_flunk(message || "Expected #{expected.inspect}, got #{actual.inspect}")
      end

      def plushie_assert(value, message)
        return assert(value, message) if respond_to?(:assert)
        return if value

        plushie_flunk(message)
      end

      def plushie_assert_nil(value, message)
        return assert_nil(value, message) if respond_to?(:assert_nil)
        return if value.nil?

        plushie_flunk(message)
      end

      def plushie_flunk(message)
        return flunk(message) if respond_to?(:flunk)

        if defined?(::RSpec::Expectations::ExpectationNotMetError)
          raise ::RSpec::Expectations::ExpectationNotMetError, message
        elsif defined?(::Minitest::Assertion)
          raise ::Minitest::Assertion, message
        else
          raise Plushie::Error, message
        end
      end
    end

    module Helpers
      PLACEHOLDER_A11Y_WIDGETS = %w[text_input text_editor combo_box pick_list].freeze
      ALT_A11Y_WIDGETS = %w[image svg qr_code].freeze

      # Apply widget-sdk-equivalent a11y inference on top of the
      # normalized `a11y` prop. Kept aligned with the Rust SDK's
      # `resolve_a11y_for_node` so cross-SDK parity holds.
      #
      # @param element [Hash] renderer node (string or symbol keyed)
      # @return [Hash] resolved a11y map with symbol keys
      def self.resolve_a11y_for_element(element)
        type = (element[:type] || element["type"]).to_s
        props = element[:props] || element["props"] || {}
        explicit = symbolize_keys(props[:a11y] || props["a11y"] || {})
        inferred = infer_a11y(type, props)
        inferred.merge(explicit)
      end

      def self.infer_a11y(type, props)
        if PLACEHOLDER_A11Y_WIDGETS.include?(type)
          ph = props[:placeholder] || props["placeholder"]
          return {description: ph} if ph.is_a?(String) && !ph.empty?
        elsif ALT_A11Y_WIDGETS.include?(type)
          alt = props[:alt] || props["alt"]
          return {label: alt} if alt.is_a?(String) && !alt.empty?
        end
        {}
      end

      def self.symbolize_keys(map)
        return {} unless map.is_a?(Hash)
        out = {}
        map.each { |k, v| out[k.is_a?(String) ? k.to_sym : k] = v }
        out
      end
    end
  end
end
