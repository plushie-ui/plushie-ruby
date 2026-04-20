# frozen_string_literal: true

module Plushie
  module Event
    # Typed diagnostic variants emitted by the renderer.
    #
    # Each variant is a Data class carrying the structured fields
    # the renderer included for that diagnostic. Pattern-match on the
    # class to react to specific diagnostic kinds:
    #
    #   case event.diagnostic
    #   in Diagnostic::DuplicateId[id:, window_id:]
    #     logger.warn("duplicate widget id #{id} in window #{window_id}")
    #   in Diagnostic::FontFamilyNotFound[family:]
    #     logger.warn("font missing: #{family}")
    #   end
    #
    # Surfaced through Event::DiagnosticMessage which carries the
    # session, severity level, and the typed variant. Decoded from the
    # renderer's `diagnostic` wire message.
    module Diagnostic
      # The kind discriminator -> Data class mapping. Ordered to match
      # the renderer's plushie-core::Diagnostic enum.
      KINDS = {} #: Hash[String, untyped]

      # A widget ID collided with one already declared within the same
      # window scope.
      DuplicateId = Data.define(:id, :window_id) do
        def initialize(id:, window_id: nil)
          super
        end
      end
      KINDS["duplicate_id"] = DuplicateId

      # A view declared a widget with an empty ID where a non-empty
      # one was expected.
      EmptyId = Data.define(:type_name)
      KINDS["empty_id"] = EmptyId

      # The top level of the view tree holds more than one window child.
      MultipleTopLevelWindows = Data.define(:window_ids)
      KINDS["multiple_top_level_windows"] = MultipleTopLevelWindows

      # A subscription was declared for a window that is not in the tree.
      UnknownWindow = Data.define(:window_id, :subscription_tag)
      KINDS["unknown_window"] = UnknownWindow

      # A `__widget__` placeholder had no registered expander.
      UnrecognizedWidgetPlaceholder = Data.define(:id)
      KINDS["unrecognized_widget_placeholder"] = UnrecognizedWidgetPlaceholder

      # Tree traversal reached the global depth cap.
      TreeDepthExceeded = Data.define(:id, :max_depth)
      KINDS["tree_depth_exceeded"] = TreeDepthExceeded

      # Duplicate-ID validation stopped collecting at the configured cap.
      TooManyDuplicates = Data.define(:limit)
      KINDS["too_many_duplicates"] = TooManyDuplicates

      # A user-authored widget ID violated the canonical ID ruleset.
      WidgetIdInvalid = Data.define(:reason, :type_name, :id, :detail)
      KINDS["widget_id_invalid"] = WidgetIdInvalid

      # A widget that requires a screen-reader-announcable name was
      # declared without one.
      MissingAccessibleName = Data.define(:type_name, :id)
      KINDS["missing_accessible_name"] = MissingAccessibleName

      # A cross-widget a11y reference did not resolve to any declared
      # widget.
      A11yRefUnresolved = Data.define(:id, :key, :value, :is_member)
      KINDS["a11y_ref_unresolved"] = A11yRefUnresolved

      # A numeric prop was outside its declared range and clamped.
      PropRangeExceeded = Data.define(:id, :type_name, :prop, :raw, :clamped, :non_finite)
      KINDS["prop_range_exceeded"] = PropRangeExceeded

      # A prop value had an unexpected JSON type.
      PropTypeMismatch = Data.define(:id, :type_name, :prop, :value_debug, :expected_debug)
      KINDS["prop_type_mismatch"] = PropTypeMismatch

      # A widget carried a prop name not in its declared schema.
      PropUnknown = Data.define(:id, :type_name, :prop, :known_debug)
      KINDS["prop_unknown"] = PropUnknown

      # A text-like content prop exceeded its per-widget byte cap and
      # was truncated.
      ContentLengthExceeded = Data.define(:id, :field, :actual, :cap, :truncated)
      KINDS["content_length_exceeded"] = ContentLengthExceeded

      # The leaked font-family-name cache reached its entry cap.
      FontCacheCapExceeded = Data.define(:max)
      KINDS["font_cache_cap_exceeded"] = FontCacheCapExceeded

      # Inline fonts declared in Settings exceeded the process-wide cap.
      FontCapExceeded = Data.define(:max, :requested, :granted, :dropped)
      KINDS["font_cap_exceeded"] = FontCapExceeded

      # A font family from default_font or its fallback chain did not
      # resolve to a loaded or built-in family.
      FontFamilyNotFound = Data.define(:family)
      KINDS["font_family_not_found"] = FontFamilyNotFound

      # The Settings payload failed typed deny_unknown_fields validation.
      InvalidSettings = Data.define(:detail)
      KINDS["invalid_settings"] = InvalidSettings

      # The Settings handshake declared one or more native widget type
      # names that the renderer does not know about.
      RequiredWidgetsMissing = Data.define(:missing)
      KINDS["required_widgets_missing"] = RequiredWidgetsMissing

      # A non-trusted widget panicked inside the registry's catch_unwind
      # firewall.
      WidgetPanic = Data.define(:id, :type_name, :label)
      KINDS["widget_panic"] = WidgetPanic

      # SVG decode returned a parse error.
      SvgParseError = Data.define(:id, :source, :detail)
      KINDS["svg_parse_error"] = SvgParseError

      # SVG decode exceeded its wall-clock budget.
      SvgDecodeTimeout = Data.define(:id, :source, :deadline_debug)
      KINDS["svg_decode_timeout"] = SvgDecodeTimeout

      # The leaked dash-segment cache reached its entry cap.
      DashCacheCapExceeded = Data.define(:max)
      KINDS["dash_cache_cap_exceeded"] = DashCacheCapExceeded

      # The renderer-lib event coalesce map hit its cap and was
      # force-flushed.
      EmitterCoalesceCapExceeded = Data.define(:cap)
      KINDS["emitter_coalesce_cap_exceeded"] = EmitterCoalesceCapExceeded

      # A composite widget ID was registered against two different
      # widget types.
      WidgetIdTypeCollision = Data.define(:id, :existing_type, :incoming_type)
      KINDS["widget_id_type_collision"] = WidgetIdTypeCollision

      # The view function panicked and was caught by the runtime's
      # safety net.
      ViewPanicked = Data.define(:consecutive, :message)
      KINDS["view_panicked"] = ViewPanicked

      # The update function panicked and was caught by the runtime.
      # The model is reverted to the last-good snapshot so the app
      # keeps running; the consecutive counter is shared with
      # ViewPanicked so the frozen-UI overlay surfaces after enough
      # total panics across either callback.
      UpdatePanicked = Data.define(:consecutive, :message)
      KINDS["update_panicked"] = UpdatePanicked

      # A wire message carried a `type` field the SDK does not recognise.
      UnknownMessageType = Data.define(:msg_type)
      KINDS["unknown_message_type"] = UnknownMessageType

      KINDS.freeze

      module_function

      # Build a typed Diagnostic from a raw wire payload (`{"kind": ...}`
      # plus variant-specific fields).
      #
      # @param payload [Hash]
      # @return [Object] a typed variant from the constants above
      # @raise [ArgumentError] when the kind is unknown
      def decode(payload)
        raise ArgumentError, "diagnostic payload must be a Hash, got #{payload.inspect}" unless payload.is_a?(Hash)

        kind = payload["kind"]
        klass = KINDS[kind]
        unless klass
          raise ArgumentError,
            "Unknown diagnostic kind #{kind.inspect}. The renderer emitted a " \
              "diagnostic this SDK version does not recognize. Ensure the SDK and " \
              "renderer versions are compatible."
        end

        members = klass.members
        attrs = {} #: Hash[Symbol, untyped]
        members.each do |m|
          attrs[m] = payload[m.to_s]
        end
        klass.new(**attrs)
      end
    end

    # A structured diagnostic delivered through the renderer's
    # diagnostic wire channel.
    #
    # Wire shape: `{type: "diagnostic", session, level, diagnostic: {kind, ...}}`.
    # The +diagnostic+ field is one of the typed variants in
    # {Plushie::Event::Diagnostic}.
    #
    # @!attribute [r] session [String] session ID the diagnostic is attributed to
    # @!attribute [r] level [Symbol] :info, :warn, or :error
    # @!attribute [r] diagnostic [Object] typed diagnostic variant
    DiagnosticMessage = Data.define(:session, :level, :diagnostic) do
      def initialize(session:, level:, diagnostic:)
        super
      end
    end
  end
end
